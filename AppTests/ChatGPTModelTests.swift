import IntervalCore
import XCTest
@testable import IntervalTracker

@MainActor
final class ChatGPTModelTests: XCTestCase {
    private let transport = StubTransport()
    private let clock = TestClock()
    private var opened: [URL] = []

    private static let modelList = StubTransport.Reply(
        body: #"{"models": [{"slug": "gpt-6.1-sol", "visibility": "list"}, {"slug": "gpt-6-luna", "visibility": "list"}]}"#)

    private func model(_ vault: Vault? = nil) -> ChatGPTModel {
        let account = ChatGPTAccount(transport: transport, store: MemoryVaultStore(vault), now: { [clock] in clock.now })
        let suite = "ChatGPTModelTests"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return ChatGPTModel(
            account: account, generator: WorkoutGenerator(account: account, transport: transport),
            defaults: UserDefaults(suiteName: suite) ?? .standard, openInSafari: { [weak self] in self?.opened.append($0) })
    }

    /// Starts a Safari sign-in and returns once the sign-in page has been opened.
    private func startSignIn(_ model: ChatGPTModel) async throws -> (running: Task<Void, Never>, page: [String: String]) {
        opened = []
        let running = Task { await model.signIn(by: .safari) }
        try await waitUntil { !self.opened.isEmpty }
        return (running, query(try XCTUnwrap(opened.first)))
    }

    func testASafariSignInIsFinishedByPastingTheAddress() async throws {
        let model = model()
        await model.load()
        XCTAssertEqual(model.status, .signedOut)

        let (running, page) = try await startSignIn(model)
        XCTAssertEqual(model.status, .signingIn)
        XCTAssertEqual(model.signInRoute, .safari)
        let redirect = try XCTUnwrap(page["redirect_uri"])
        XCTAssertTrue(redirect.hasPrefix("http://127.0.0.1:") && redirect.hasSuffix("/auth/callback"), redirect)

        model.paste("\(redirect)?code=the-code&state=someone-elses&client_id=oaiapp_1")
        try await waitUntil { model.signInProblem != nil }
        XCTAssertEqual(model.status, .signingIn, "a wrong paste can be corrected")

        transport.queue(.tokens(access: "access-1", refresh: "refresh-1", nonce: page["nonce"]), Self.modelList)
        model.paste("\(redirect)?code=the-code&state=\(try XCTUnwrap(page["state"]))&client_id=oaiapp_1")
        await running.value

        XCTAssertEqual(model.status, .planUsage)
        XCTAssertNil(model.signInProblem)
        XCTAssertEqual(model.email, "you@example.com")
        XCTAssertEqual(form(try XCTUnwrap(transport.requests.first))["code"], "the-code")
        XCTAssertEqual(model.models, ["gpt-6.1-sol", "gpt-6-luna"])
        XCTAssertEqual(model.model, "gpt-6-luna", "the smallest listed model is the default")
        XCTAssertTrue(model.planNoticeIsShown, "the first grant of plan usage is announced")
    }

    func testTheListenerFinishesTheSignInWhenTheBrowserComesBack() async throws {
        let model = model()
        let (running, page) = try await startSignIn(model)
        transport.queue(.tokens(access: "access-1", refresh: "refresh-1", nonce: page["nonce"]), Self.modelList)
        let redirect = try XCTUnwrap(page["redirect_uri"])

        let stray = try await get("\(redirect)?code=the-code&state=someone-elses&client_id=oaiapp_1")
        XCTAssertEqual(stray.status, 200)
        XCTAssertEqual(model.status, .signingIn, "a request that does not answer this attempt changes nothing")

        let reply = try await get("\(redirect)?code=the-code&state=\(try XCTUnwrap(page["state"]))&client_id=oaiapp_1")
        await running.value

        XCTAssertTrue(reply.body.contains("Go back to Intervals"), reply.body)
        XCTAssertEqual(model.status, .planUsage)
        let after = try? await get("\(redirect)?code=the-code&state=x")
        XCTAssertNil(after, "the listener stops when the sign-in ends")
    }

    func testThePlanNoticeIsShownOnce() async throws {
        let model = model()
        var (running, page) = try await startSignIn(model)
        transport.queue(.tokens(access: "access-1", refresh: "refresh-1", nonce: page["nonce"]), Self.modelList)
        model.paste("\(try XCTUnwrap(page["redirect_uri"]))?code=a&state=\(try XCTUnwrap(page["state"]))&client_id=oaiapp_1")
        await running.value
        XCTAssertTrue(model.planNoticeIsShown)
        model.planNoticeIsShown = false

        transport.queue(.init(body: ""))
        await model.signOut()
        XCTAssertEqual(model.status, .signedOut)
        XCTAssertEqual(model.models, [])

        (running, page) = try await startSignIn(model)
        transport.queue(.tokens(access: "access-2", refresh: "refresh-2", nonce: page["nonce"]), Self.modelList)
        model.paste("\(try XCTUnwrap(page["redirect_uri"]))?code=b&state=\(try XCTUnwrap(page["state"]))&client_id=oaiapp_2")
        await running.value
        XCTAssertEqual(model.status, .planUsage)
        XCTAssertFalse(model.planNoticeIsShown)
    }

    func testCancellingASignInLeavesTheUserSignedOutAndClosesTheListener() async throws {
        let model = model()
        let (running, page) = try await startSignIn(model)
        let redirect = try XCTUnwrap(page["redirect_uri"])

        model.cancelSignIn()
        await running.value

        XCTAssertEqual(model.status, .signedOut)
        XCTAssertNil(model.signInProblem, "the user cancelled, so there is nothing to explain")
        XCTAssertTrue(transport.requests.isEmpty)
        var refused = false
        for _ in 0..<100 where !refused {
            refused = (try? await get("\(redirect)?code=a&state=b")) == nil
            if !refused { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertTrue(refused, "the port stayed open after the sign-in was cancelled")
    }

    func testARefusalOnTheSignInPageEndsTheSignInWithAReason() async throws {
        let model = model()
        let (running, page) = try await startSignIn(model)
        model.paste("\(try XCTUnwrap(page["redirect_uri"]))?error=access_denied&state=\(try XCTUnwrap(page["state"]))")
        await running.value
        XCTAssertEqual(model.status, .signedOut)
        XCTAssertEqual(model.signInProblem, SignInProblem.denied.message)
    }

    func testGeneratingPicksTheSmallestModelAndBuildsTheWorkout() async throws {
        let model = model(signedInVault(at: clock))
        await model.load()
        XCTAssertEqual(model.status, .planUsage)
        XCTAssertNil(model.model)
        transport.queue(Self.modelList, .stream(#"{"kind": "routine", "name": "Hips", "note": null, "intervals": null, "stretches": [{"name": "Pigeon", "holdSeconds": 60, "reps": null, "eachSide": true}]}"#))

        guard case .success(let generated) = await model.generate("hips") else { return XCTFail("nothing was generated") }

        XCTAssertEqual(generated.workout.name, "Hips")
        XCTAssertEqual(generated.workout.plan.summary, "1 stretch · 1 each side")
        XCTAssertEqual(try json(try XCTUnwrap(transport.requests.last))["model"] as? String, "gpt-6-luna")
        XCTAssertFalse(model.planNoticeIsShown, "a sign-in from an earlier launch is not announced again")
    }

    func testASignInThatEndedWhileGeneratingShowsAsSignedOut() async {
        let model = model(signedInVault(at: clock))
        model.model = "gpt-6-luna"
        await model.load()
        clock.advance(by: 3600)
        transport.queue(.error(400, code: "refresh_token_expired"))

        let outcome = await model.generate("hips")

        XCTAssertEqual(outcome, .failure(.signInAgain))
        XCTAssertEqual(model.status, .signedOut)
        XCTAssertFalse(model.canPay)
    }

    func testAnAPIKeyCanBeSavedAndRemoved() async {
        let model = model()
        transport.queue(.init(body: #"{"data": [{"id": "gpt-6-luna"}]}"#))
        await model.setAPIKey("sk-test")
        XCTAssertEqual(model.status, .keyOnly)
        XCTAssertTrue(model.hasAPIKey)
        XCTAssertTrue(model.canPay)
        XCTAssertEqual(model.models, ["gpt-6-luna"])

        await model.setAPIKey(nil)
        XCTAssertEqual(model.status, .signedOut)
        XCTAssertFalse(model.canPay)
    }
}
