import Foundation
import UIKit

extension ChatGPTModel {
    /// The model the app runs with. A launch with `-aiStub signedIn` or `-aiStub signedOut` gets
    /// stand-ins for OpenAI and the Keychain, so a UI test needs no account and reaches no network.
    static func forThisLaunch() -> ChatGPTModel {
        let openInSafari: (URL) -> Void = { UIApplication.shared.open($0) }
        guard let stub = UserDefaults.standard.string(forKey: "aiStub") else {
            let transport = URLSessionTransport()
            let account = ChatGPTAccount(transport: transport, store: KeychainVaultStore())
            return ChatGPTModel(
                account: account, generator: WorkoutGenerator(account: account, transport: transport),
                openInSafari: openInSafari)
        }
        let transport = StubOpenAI()
        let account = ChatGPTAccount(
            transport: transport, store: MemoryVaultStore(stub == "signedIn" ? StubOpenAI.signedIn : nil))
        let suite = "aiStub"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return ChatGPTModel(
            account: account, generator: WorkoutGenerator(account: account, transport: transport),
            defaults: UserDefaults(suiteName: suite) ?? .standard,
            openInSafari: openInSafari, signInPage: StubOpenAI.signInPage)
    }
}

/// Answers as OpenAI's token, model and Responses endpoints would, from memory.
final class StubOpenAI: OpenAITransport, @unchecked Sendable {
    private let lock = NSLock()
    private var descriptions = 0
    private var unanswered: [AsyncThrowingStream<String, Error>.Continuation] = []

    static let signedIn = Vault(clientID: "oaiapp_stub", session: Vault.Session(
        accessToken: "stub-access", refreshToken: "stub-refresh", scope: OpenAI.scope,
        expiresAt: .distantFuture, email: "you@example.com"))

    /// Stands in for ChatGPT's sign-in page: an address that goes straight back to the app, as the
    /// real page does once the user has approved. The code carries the nonce so that the token
    /// endpoint below can answer with an ID token that matches the attempt.
    static func signInPage(_ authorize: URL) -> URL {
        let asked = URLComponents(url: authorize, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String { asked.first { $0.name == name }?.value ?? "" }
        var page = URLComponents(string: value("redirect_uri")) ?? URLComponents()
        page.queryItems = [
            URLQueryItem(name: "code", value: "stub." + value("nonce")),
            URLQueryItem(name: "state", value: value("state")),
            URLQueryItem(name: "client_id", value: "oaiapp_stub"),
        ]
        return page.url ?? authorize
    }

    func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        switch request.url {
        case OpenAI.token: return answer(tokens(for: request))
        case OpenAI.revoke: return answer("{}")
        case OpenAI.models: return answer(#"{"models": [{"slug": "gpt-6.1-sol", "visibility": "list"}, {"slug": "gpt-6-luna", "visibility": "list"}, {"slug": "gpt-6-internal", "visibility": "hide"}]}"#)
        case OpenAI.responses:
            // The first description is never answered, so a UI test can look at the waiting screen
            // for as long as it needs and then cancel.
            if lock.withLock({ descriptions += 1; return descriptions }) == 1 {
                return (200, AsyncThrowingStream { continuation in lock.withLock { unanswered.append(continuation) } })
            }
            return answer(events(for: request))
        default: return (404, AsyncThrowingStream { $0.finish() })
        }
    }

    private func answer(_ body: String) -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        (200, AsyncThrowingStream { continuation in
            for line in body.split(separator: "\n") { continuation.yield(String(line)) }
            continuation.finish()
        })
    }

    private func tokens(for request: URLRequest) -> String {
        let form = URLComponents(string: "?" + String(decoding: request.httpBody ?? Data(), as: UTF8.self))?.queryItems ?? []
        let code = form.first { $0.name == "code" }?.value ?? ""
        let claims = try? JSONSerialization.data(withJSONObject: ["nonce": String(code.dropFirst(5)), "email": "you@example.com"])
        let idToken = "e30.\((claims ?? Data()).base64URLEncoded).stub"
        return #"{"access_token": "stub-access", "refresh_token": "stub-refresh", "id_token": "\#(idToken)", "expires_in": 3600, "scope": "\#(OpenAI.scope)"}"#
    }

    private func events(for request: URLRequest) -> String {
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
        let asked = (body?["input"] as? [[String: String]])?.first?["content"] ?? ""
        let workout = asked.localizedCaseInsensitiveContains("tabata") ? Self.tabata : Self.hips
        let half = workout.index(workout.startIndex, offsetBy: workout.count / 2)
        return [String(workout[..<half]), String(workout[half...])]
            .compactMap { try? JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": $0]) }
            .map { "data: " + String(decoding: $0, as: UTF8.self) }
            .joined(separator: "\n") + "\n" + #"data: {"type": "response.completed"}"#
    }

    private static let tabata = #"""
        {"kind": "intervals", "name": "Bike Tabata", "note": null, "stretches": null, "intervals": {"warmUpSeconds": 300, "workSeconds": 20, "restSeconds": 10, "rounds": 8, "coolDownSeconds": 180, "restAfterLastRound": false}}
        """#

    private static let hips = #"""
        {"kind": "routine", "name": "Hip Mobility", "note": "Two moves are counted in reps, so the timed part is about 12 minutes.", "intervals": null, "stretches": [{"name": "Hip Circles", "holdSeconds": null, "reps": 10, "eachSide": true}, {"name": "Hip Flexor Lunge", "holdSeconds": 60, "reps": null, "eachSide": true}, {"name": "Pigeon", "holdSeconds": 90, "reps": null, "eachSide": true}, {"name": "Deep Squat Hold", "holdSeconds": 90, "reps": null, "eachSide": false}, {"name": "Frog Stretch", "holdSeconds": 90, "reps": null, "eachSide": false}, {"name": "Figure Four", "holdSeconds": 60, "reps": null, "eachSide": true}, {"name": "Glute Bridge", "holdSeconds": null, "reps": 12, "eachSide": false}, {"name": "Happy Baby", "holdSeconds": 90, "reps": null, "eachSide": false}]}
        """#
}
