import Foundation
import IntervalCore

struct GeneratedWorkout: Equatable, Sendable {
    let workout: Workout
    /// What the model wanted the user to know about its answer.
    let note: String?
}

enum GenerationFailure: Error, Equatable, Sendable {
    case signedOut
    case planUsageOff
    case signInAgain
    case keyRejected
    case noCredit
    case usageLimit
    case notEligible
    case routeNotSupported
    case unsupported(param: String?)
    case busy
    case server
    case unreachable
    case incomplete
    case noModels
    case unusable(BlueprintError)

    /// One plain sentence and a way forward. Never the server's own words.
    var message: String {
        switch self {
        case .signedOut: "Sign in with ChatGPT to build a workout."
        case .planUsageOff: "This app is not allowed to use your ChatGPT plan. Sign in again to allow it, or add an API key in Settings."
        case .signInAgain: "Your ChatGPT sign-in has ended. Sign in again."
        case .keyRejected: "OpenAI did not accept the API key. Check the key in Settings."
        case .noCredit: "The API key has no credit left. Add credit to your OpenAI account, or sign in with ChatGPT."
        case .usageLimit: "You have reached your ChatGPT plan's limit for now. Check your usage, then try again later."
        case .notEligible: "Your ChatGPT plan cannot be used in other apps. Add an OpenAI API key in Settings to build workouts."
        case .routeNotSupported: "OpenAI did not accept this request on your ChatGPT plan. Update the app, or add an API key in Settings."
        case .unsupported: "OpenAI does not allow part of this request on your ChatGPT plan. Choose another model in Settings, then try again."
        case .busy: "OpenAI is limiting requests right now. Wait a minute, then try again."
        case .server: "OpenAI could not answer. Try again in a moment."
        case .unreachable: "Could not reach OpenAI. Check your connection, then try again."
        case .incomplete: "The answer stopped before it was finished. Try again."
        case .noModels: "Your account lists no model that this app can use. Try again later."
        case .unusable(let error): "The answer \(error.reason), so there is no workout to show. Try again, or describe it another way."
        }
    }

    var offersManageUsage: Bool { self == .usageLimit }

    /// What an error answer means. `status` is 200 for a failure that arrives inside the stream.
    init(status: Int, _ error: OpenAI.Failure, paidBy bearer: Bearer) {
        self = switch (error.code, status) {
        case ("subscription_sharing_usage_limit_exceeded", _): .usageLimit
        case ("subscription_sharing_user_not_eligible", _): .notEligible
        case ("subscription_sharing_route_not_supported", _): .routeNotSupported
        case ("subscription_sharing_unsupported_capability", _): .unsupported(param: error.param)
        case ("insufficient_quota", _): .noCredit
        case (_, 401): if case .plan = bearer { .signInAgain } else { .keyRejected }
        case (_, 429): .busy
        case (_, 400) where error.param?.hasPrefix("text") == true: .unsupported(param: error.param)
        default: .server
        }
    }

    /// OpenAI has not said whether a plan request may carry a schema. A refusal that names `text`, or
    /// names nothing, is taken to be about the schema.
    fileprivate var isAboutTheSchema: Bool {
        if case .unsupported(let param) = self { param?.hasPrefix("text") ?? true } else { false }
    }
}

/// Turns a description into a workout: one request to the Responses API, read as a stream.
/// It is an actor so that the answer is decoded and checked away from the main thread.
actor WorkoutGenerator {
    private let account: ChatGPTAccount
    private let transport: any OpenAITransport

    init(account: ChatGPTAccount, transport: any OpenAITransport) {
        self.account = account
        self.transport = transport
    }

    func generate(_ description: String, model: String) async throws(GenerationFailure) -> GeneratedWorkout {
        var bearer = try await authorization()
        var format = ResponsesRequest.Format.schema
        var mayRefresh = true
        while true {
            do {
                let request = ResponsesRequest(description: description, model: model, format: format)
                return try Self.workout(from: try await answer(to: request, paidBy: bearer))
            } catch let failure where failure.isAboutTheSchema && format == .schema {
                format = .instructions
            } catch .signInAgain where mayRefresh {
                // The server can end a token before its time. One refresh settles whether the sign-in is still good.
                mayRefresh = false
                await account.rejected(bearer)
                bearer = try await authorization()
            }
        }
    }

    /// The models the account may use, in the server's order.
    func models() async throws(GenerationFailure) -> [String] {
        let bearer = try await authorization()
        var request = URLRequest(url: OpenAI.models)
        request.setValue("Bearer \(bearer.secret)", forHTTPHeaderField: "Authorization")
        let reply: (status: Int, body: Data)
        do {
            reply = try await transport.send(request)
        } catch {
            throw .unreachable
        }
        guard reply.status == 200 else {
            throw GenerationFailure(status: reply.status, OpenAI.Failure(body: reply.body), paidBy: bearer)
        }
        return ModelList(body: reply.body).slugs
    }

    private func authorization() async throws(GenerationFailure) -> Bearer {
        do {
            return try await account.bearer()
        } catch {
            throw switch error {
            case .signedOut: .signedOut
            case .planUsageOff: .planUsageOff
            case .signInAgain: .signInAgain
            case .unreachable: .unreachable
            }
        }
    }

    private func answer(to request: ResponsesRequest, paidBy bearer: Bearer) async throws(GenerationFailure) -> String {
        do {
            let (status, lines) = try await transport.open(request.urlRequest(paidBy: bearer))
            guard status == 200 else {
                var body = ""
                for try await line in lines { body += line + "\n" }
                throw GenerationFailure(status: status, OpenAI.Failure(body: Data(body.utf8)), paidBy: bearer)
            }
            var stream = ResponseStream()
            for try await line in lines {
                stream.read(line)
                if stream.ending != nil { break }
            }
            switch stream.ending {
            case .completed: return stream.text
            case .failed(let error): throw GenerationFailure(status: 200, error, paidBy: bearer)
            case .incomplete, nil: throw GenerationFailure.incomplete
            }
        } catch let failure as GenerationFailure {
            throw failure
        } catch {
            throw .unreachable
        }
    }

    private static func workout(from text: String) throws(GenerationFailure) -> GeneratedWorkout {
        do {
            let blueprint = try WorkoutBlueprint(modelOutput: text)
            let note = blueprint.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            return GeneratedWorkout(workout: try blueprint.workout(), note: note?.isEmpty == false ? note : nil)
        } catch {
            throw .unusable(error)
        }
    }
}

/// One request to `POST /v1/responses`. A plan request must set `store` to false and `stream` to
/// true, and the server turns down a list of fields that the ordinary API takes, `temperature` and
/// `max_output_tokens` among them. So the body has these six fields and no others.
struct ResponsesRequest {
    enum Format {
        /// The schema goes with the request, and the server holds the model to it.
        case schema
        /// The schema is written into the instructions, for a server that does not take one.
        case instructions
    }

    let description: String
    let model: String
    let format: Format

    var body: [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "store": false,
            "stream": true,
            "instructions": format == .schema ? WorkoutBlueprint.instructions : WorkoutBlueprint.instructionsWithSchema,
            "input": [["role": "user", "content": description]],
        ]
        if format == .schema, let schema = try? JSONSerialization.jsonObject(with: Data(WorkoutBlueprint.schema.utf8)) {
            body["text"] = ["format": ["type": "json_schema", "name": "workout", "strict": true, "schema": schema]]
        }
        return body
    }

    func urlRequest(paidBy bearer: Bearer) -> URLRequest {
        var request = URLRequest(url: OpenAI.responses)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

/// Reads the server-sent events of one answer. The text is the deltas in order, and it counts only
/// once `response.completed` has arrived: a stream that ends without it was cut off.
struct ResponseStream {
    enum Ending: Equatable {
        case completed
        case incomplete
        case failed(OpenAI.Failure)
    }

    private(set) var text = ""
    private(set) var ending: Ending?

    mutating func read(_ line: String) {
        guard ending == nil, line.hasPrefix("data:") else { return }
        let data = Data(line.dropFirst(5).utf8)
        guard let event = try? JSONDecoder().decode(Event.self, from: data) else { return }
        switch event.type {
        case "response.output_text.delta": text += event.delta ?? ""
        case "response.completed": ending = .completed
        case "response.incomplete": ending = .incomplete
        case "response.failed": ending = .failed(event.response?.error ?? OpenAI.Failure())
        case "error": ending = .failed(OpenAI.Failure(body: data))
        default: break
        }
    }

    private struct Event: Decodable {
        let type: String
        let delta: String?
        let response: Response?

        struct Response: Decodable {
            let error: OpenAI.Failure?
        }
    }
}

/// The answer of `GET /v1/models`. With a plan token it is `models`, each with a `slug` and a
/// `visibility`. With an API key it is `data`, every model the key can reach, each with an `id`.
struct ModelList: Decodable {
    private var models: [Listed]?
    private var data: [Reachable]?

    private struct Listed: Decodable {
        let slug: String
        let visibility: String?
    }

    private struct Reachable: Decodable {
        let id: String
    }

    init(body: Data) {
        self = (try? JSONDecoder().decode(ModelList.self, from: body)) ?? ModelList()
    }

    private init() {}

    var slugs: [String] {
        if let models { return models.filter { $0.visibility == "list" }.map(\.slug) }
        return (data ?? []).map(\.id).filter { $0.hasPrefix("gpt-") }.sorted()
    }

    /// The model to use until the user picks one. A workout is a small job, so this is the smallest
    /// model. The list does not say which one that is, so it goes by the names OpenAI gives its small
    /// models, and falls back to the first one listed.
    static func smallest(of slugs: [String]) -> String? {
        for hint in ["luna", "nano", "mini"] {
            if let match = slugs.first(where: { $0.contains(hint) }) { return match }
        }
        return slugs.first
    }
}
