import Foundation

/// The addresses and fixed values of OpenAI's "Sign in with ChatGPT" flow for open-source apps, and of
/// the Responses API that the sign-in pays for.
enum OpenAI {
    static let authorize = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let token = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let revoke = URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!
    static let resource = "https://api.openai.com/v1"
    static let responses = URL(string: resource + "/responses")!
    static let models = URL(string: resource + "/models")!
    static let manageUsage = URL(string: "https://chatgpt.com/settings/usage")!

    static let scope = "openid profile email offline_access resource.invoke \(planUsageScope)"
    /// A sign-in may spend the plan only when the granted scope has this.
    static let planUsageScope = "chatgpt.tokens.use.direct"
    /// The client id of a first sign-in. The server answers with an id of its own, and that one is kept.
    static let unregisteredClient = "dynamic_agent_client"
    static let agentName = "Intervals"
}

/// The network, as much of it as this feature uses. Tests and the `-aiStub` launch argument put a
/// stub here, so no test reaches OpenAI.
protocol OpenAITransport: Sendable {
    /// The status and the body, one line at a time, so that a streamed answer is read as it arrives.
    func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>)
}

extension OpenAITransport {
    /// For an answer that is one small document.
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let (status, lines) = try await open(request)
        var body = ""
        for try await line in lines { body += line + "\n" }
        return (status, Data(body.utf8))
    }
}

struct URLSessionTransport: OpenAITransport {
    private let session = URLSession(configuration: .ephemeral)

    func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let reading = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, lines)
    }
}

extension URLRequest {
    /// A POST of `fields` in the form encoding the token endpoints take.
    static func form(_ url: URL, _ fields: KeyValuePairs<String, String>) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(OpenAI.query(fields).utf8)
        return request
    }
}

extension OpenAI {
    /// `fields` as a query string with everything outside the unreserved set escaped, so that a
    /// redirect address or a scope list survives as one value.
    static func query(_ fields: KeyValuePairs<String, String>) -> String {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        func escaped(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
        return fields.map { "\(escaped($0.key))=\(escaped($0.value))" }.joined(separator: "&")
    }

    /// An error as OpenAI's endpoints report it. The token endpoint sends `{"error": "invalid_grant"}`
    /// and the API sends `{"error": {"code": ..., "param": ...}}`.
    struct Failure: Decodable, Equatable {
        var code: String?
        var param: String?

        private enum CodingKeys: String, CodingKey { case error, code, param }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let plain = try? container.decode(String.self, forKey: .error) {
                code = plain
            } else if let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .error) {
                code = try? nested.decode(String.self, forKey: .code)
                param = try? nested.decode(String.self, forKey: .param)
            } else {
                code = try? container.decode(String.self, forKey: .code)
                param = try? container.decode(String.self, forKey: .param)
            }
        }

        init(body: Data) {
            self = (try? JSONDecoder().decode(Failure.self, from: body)) ?? Failure()
        }

        init(code: String? = nil, param: String? = nil) {
            self.code = code; self.param = param
        }
    }
}
