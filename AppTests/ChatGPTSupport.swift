import Foundation
import XCTest
@testable import IntervalTracker

/// Stands in for OpenAI. It hands out the queued replies in order and keeps every request, so a test
/// can read what the app sent. With no reply queued it fails as a phone with no connection does.
final class StubTransport: OpenAITransport, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = ""
    }

    private let lock = NSLock()
    private var queued: [Reply] = []
    private var sent: [URLRequest] = []
    /// How long each request is out, so that two callers can overlap.
    var delay: Duration = .zero

    var requests: [URLRequest] { lock.withLock { sent } }

    func queue(_ replies: Reply...) {
        lock.withLock { queued += replies }
    }

    func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        lock.withLock { sent.append(request) }
        try await Task.sleep(for: delay)
        guard let reply = lock.withLock({ queued.isEmpty ? nil : queued.removeFirst() }) else {
            throw URLError(.notConnectedToInternet)
        }
        return (reply.status, AsyncThrowingStream { continuation in
            for line in reply.body.split(separator: "\n", omittingEmptySubsequences: true) { continuation.yield(String(line)) }
            continuation.finish()
        })
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var now: Date { lock.withLock { date } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date += seconds }
    }
}

let fullScope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

extension StubTransport.Reply {
    static func tokens(access: String, refresh: String, nonce: String? = nil, scope: String? = fullScope,
                       email: String = "you@example.com") -> StubTransport.Reply {
        var fields: [String: Any] = ["access_token": access, "refresh_token": refresh, "token_type": "Bearer", "expires_in": 3600]
        if let scope { fields["scope"] = scope }
        if let nonce {
            let claims = try! JSONSerialization.data(withJSONObject: ["nonce": nonce, "email": email, "sub": "user-1"])
            fields["id_token"] = "eyJhbGciOiJSUzI1NiJ9.\(claims.base64URLEncoded).signature"
        }
        return StubTransport.Reply(body: String(decoding: try! JSONSerialization.data(withJSONObject: fields), as: UTF8.self))
    }

    static func error(_ status: Int, code: String, param: String? = nil) -> StubTransport.Reply {
        var error: [String: Any] = ["code": code, "message": "The server's own words about \(code).", "type": "invalid_request_error"]
        if let param { error["param"] = param }
        return StubTransport.Reply(
            status: status, body: String(decoding: try! JSONSerialization.data(withJSONObject: ["error": error]), as: UTF8.self))
    }

    /// A streamed answer: the text cut into deltas of `size` characters, then `response.completed`.
    static func stream(_ text: String, deltasOf size: Int = 40, ending: String? = #"{"type": "response.completed", "response": {"status": "completed"}}"#) -> StubTransport.Reply {
        var lines = [#"event: response.created"#, #"data: {"type": "response.created", "response": {"status": "in_progress"}}"#]
        var rest = Substring(text)
        while !rest.isEmpty {
            let delta = try! JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": String(rest.prefix(size))])
            lines += ["event: response.output_text.delta", "data: " + String(decoding: delta, as: UTF8.self), ""]
            rest = rest.dropFirst(size)
        }
        if let ending { lines.append("data: " + ending) }
        return StubTransport.Reply(body: lines.joined(separator: "\n"))
    }
}

/// A session that signed in as `oaiapp_1` an instant ago and may spend the plan.
func signedInVault(scope: String = fullScope, apiKey: String? = nil, at clock: TestClock) -> Vault {
    Vault(clientID: "oaiapp_1", session: Vault.Session(
        accessToken: "access-1", refreshToken: "refresh-1", scope: scope,
        expiresAt: clock.now.addingTimeInterval(3600), email: "you@example.com"), apiKey: apiKey)
}

func form(_ request: URLRequest) -> [String: String] {
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    let items = URLComponents(string: "?" + body)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

func query(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

func json(_ request: URLRequest) throws -> [String: Any] {
    try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
}

struct NeverHappened: Error {}

/// Waits for something that another task is about to do.
@MainActor
func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<1500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw NeverHappened()
}

/// A GET that reports a redirect instead of following it.
func get(_ address: String) async throws -> (status: Int, location: String?, body: String) {
    final class StayHere: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    var request = URLRequest(url: try XCTUnwrap(URL(string: address)))
    request.timeoutInterval = 10
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request, delegate: StayHere())
    let http = try XCTUnwrap(response as? HTTPURLResponse)
    return (http.statusCode, http.value(forHTTPHeaderField: "Location"), String(decoding: data, as: UTF8.self))
}
