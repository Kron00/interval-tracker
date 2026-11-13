import XCTest
@testable import IntervalTracker

final class ChatGPTAccountTests: XCTestCase {
    private let transport = StubTransport()
    private let clock = TestClock()

    private func account(_ store: MemoryVaultStore) -> ChatGPTAccount {
        ChatGPTAccount(transport: transport, store: store, now: { [clock] in clock.now })
    }

    private func signedIn(scope: String = fullScope, apiKey: String? = nil) -> (ChatGPTAccount, MemoryVaultStore) {
        let store = MemoryVaultStore(signedInVault(scope: scope, apiKey: apiKey, at: clock))
        return (account(store), store)
    }

    private func bearerProblem(_ account: ChatGPTAccount) async -> AccountProblem? {
        do {
            _ = try await account.bearer()
            return nil
        } catch {
            return error
        }
    }

    private func signInProblem(_ account: ChatGPTAccount, _ attempt: SignInAttempt) async throws -> SignInProblem? {
        let grant = try attempt.grant(from: "/auth/callback?code=the-code&state=\(attempt.state)&client_id=oaiapp_1")
        do {
            try await account.finishSignIn(attempt, grant)
            return nil
        } catch {
            return error
        }
    }

    /// A server whose answer arrives when the test says so, whether or not the caller still wants it.
    private final class LateTransport: OpenAITransport, @unchecked Sendable {
        private let lock = NSLock()
        private var asked = false
        private var waiting: CheckedContinuation<String, Never>?

        var wasAsked: Bool { lock.withLock { asked } }

        func answer(_ body: String) {
            lock.withLock { waiting }?.resume(returning: body)
        }

        func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
            let body = await withCheckedContinuation { continuation in
                lock.withLock {
                    waiting = continuation
                    asked = true
                }
            }
            return (200, AsyncThrowingStream { continuation in
                continuation.yield(body)
                continuation.finish()
            })
        }
    }

    func testASignInCancelledWhileTheCodeIsExchangedKeepsNothingWhenTheAnswerComes() async throws {
        let late = LateTransport()
        let store = MemoryVaultStore()
        let account = ChatGPTAccount(transport: late, store: store)
        let begun = await account.beginSignIn(port: 51234, askAgain: false)
        let grant = try begun.attempt.grant(from: "/auth/callback?code=the-code&state=\(begun.attempt.state)&client_id=oaiapp_1")
        let exchange = Task { try? await account.finishSignIn(begun.attempt, grant) }
        while !late.wasAsked { try await Task.sleep(for: .milliseconds(10)) }

        exchange.cancel()
        late.answer(StubTransport.Reply.tokens(access: "access-1", refresh: "refresh-1", nonce: begun.attempt.nonce).body)
        await exchange.value

        let summary = await account.summary
        XCTAssertEqual(summary.status, .signedOut)
        XCTAssertNil(store.load()?.session)
        XCTAssertNil(store.load()?.clientID)
    }

    func testSigningInExchangesTheCodeAndKeepsTheTokens() async throws {
        let store = MemoryVaultStore()
        let account = account(store)
        let begun = await account.beginSignIn(port: 51234, askAgain: false)
        XCTAssertEqual(query(begun.page)["client_id"], "dynamic_agent_client")
        transport.queue(.tokens(access: "access-1", refresh: "refresh-1", nonce: begun.attempt.nonce))

        let problem = try await signInProblem(account, begun.attempt)

        XCTAssertNil(problem)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/api/accounts/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(form(request), [
            "grant_type": "authorization_code",
            "client_id": "oaiapp_1",
            "code": "the-code",
            "code_verifier": begun.attempt.verifier,
            "redirect_uri": "http://127.0.0.1:51234/auth/callback",
            "resource": "https://api.openai.com/v1",
        ])
        let summary = await account.summary
        XCTAssertEqual(summary.status, .planUsage)
        XCTAssertEqual(summary.email, "you@example.com")
        let bearer = try await account.bearer()
        XCTAssertEqual(bearer, .plan("access-1"))

        let relaunched = self.account(store)
        let kept = await relaunched.summary
        XCTAssertEqual(kept.status, .planUsage, "the sign-in is in the store, so it outlives the app")
        let again = await relaunched.beginSignIn(port: 51234, askAgain: false)
        XCTAssertEqual(query(again.page)["client_id"], "oaiapp_1", "a later sign-in uses the id that was issued")
        XCTAssertEqual(query(again.page)["ext_agent_host_id"], query(begun.page)["ext_agent_host_id"])
    }

    func testPlanUsageIsOffWhenTheGrantedScopeLacksIt() async throws {
        let account = account(MemoryVaultStore())
        let begun = await account.beginSignIn(port: 51234, askAgain: false)
        transport.queue(.tokens(
            access: "access-1", refresh: "refresh-1", nonce: begun.attempt.nonce,
            scope: "openid profile email offline_access resource.invoke"))

        let problem = try await signInProblem(account, begun.attempt)

        XCTAssertNil(problem, "the sign-in itself worked")
        var summary = await account.summary
        XCTAssertEqual(summary.status, .signedInWithoutPlanUsage)
        XCTAssertFalse(summary.canPay)
        let refused = await bearerProblem(account)
        XCTAssertEqual(refused, .planUsageOff, "a valid ID token alone does not pay for a request")

        await account.setAPIKey("sk-test")
        summary = await account.summary
        XCTAssertEqual(summary.status, .signedInWithoutPlanUsage)
        XCTAssertTrue(summary.canPay)
        let bearer = try await account.bearer()
        XCTAssertEqual(bearer, .apiKey("sk-test"))
    }

    func testAnAnswerWithNoScopeDoesNotGrantPlanUsage() async throws {
        let account = account(MemoryVaultStore())
        let begun = await account.beginSignIn(port: 51234, askAgain: false)
        transport.queue(.tokens(access: "access-1", refresh: "refresh-1", nonce: begun.attempt.nonce, scope: nil))
        _ = try await signInProblem(account, begun.attempt)
        let summary = await account.summary
        XCTAssertEqual(summary.status, .signedInWithoutPlanUsage)
    }

    func testTokensThatDoNotBelongToTheAttemptAreRefused() async throws {
        let replies: [StubTransport.Reply] = [
            .tokens(access: "access-1", refresh: "refresh-1", nonce: "another-nonce"),
            .tokens(access: "access-1", refresh: "refresh-1", nonce: nil),
            .error(400, code: "invalid_grant"),
        ]
        for reply in replies {
            let store = MemoryVaultStore()
            let account = account(store)
            let begun = await account.beginSignIn(port: 51234, askAgain: false)
            transport.queue(reply)

            let problem = try await signInProblem(account, begun.attempt)

            XCTAssertEqual(problem, .refused, reply.body)
            let summary = await account.summary
            XCTAssertEqual(summary.status, .signedOut)
            XCTAssertNil(store.load()?.session)
            XCTAssertNil(store.load()?.clientID)
        }
    }

    func testASignInWithNoConnectionSaysSo() async throws {
        let account = account(MemoryVaultStore())
        let begun = await account.beginSignIn(port: 51234, askAgain: false)
        let problem = try await signInProblem(account, begun.attempt)
        XCTAssertEqual(problem, .unreachable)
    }

    func testATokenWithTimeLeftIsUsedAsItIs() async throws {
        let (account, _) = signedIn()
        clock.advance(by: 3000)
        let bearer = try await account.bearer()
        XCTAssertEqual(bearer, .plan("access-1"))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAnExpiringTokenIsRefreshedAndTheRotatedTokenIsKept() async throws {
        let (account, store) = signedIn()
        clock.advance(by: 3590)
        transport.queue(.tokens(access: "access-2", refresh: "refresh-2", scope: nil))

        let second = try await account.bearer()

        XCTAssertEqual(second, .plan("access-2"))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/api/accounts/oauth/token")
        XCTAssertEqual(form(request), [
            "grant_type": "refresh_token",
            "client_id": "oaiapp_1",
            "refresh_token": "refresh-1",
            "resource": "https://api.openai.com/v1",
        ], "the documented fields, and no scope")
        XCTAssertEqual(store.load()?.session?.refreshToken, "refresh-2")
        let summary = await account.summary
        XCTAssertEqual(summary.status, .planUsage, "a refresh that names no scope keeps the scope it had")

        clock.advance(by: 3600)
        transport.queue(.tokens(access: "access-3", refresh: "refresh-3"))
        let third = try await account.bearer()
        XCTAssertEqual(third, .plan("access-3"))
        XCTAssertEqual(form(try XCTUnwrap(transport.requests.last))["refresh_token"], "refresh-2", "the old token is dead after one use")
    }

    func testTwoCallersAtOnceShareOneRefresh() async throws {
        let (account, _) = signedIn()
        clock.advance(by: 3600)
        transport.delay = .milliseconds(200)
        transport.queue(.tokens(access: "access-2", refresh: "refresh-2"))

        async let first = account.bearer()
        async let second = account.bearer()
        let bearers = try await [first, second]

        XCTAssertEqual(bearers, [.plan("access-2"), .plan("access-2")])
        XCTAssertEqual(transport.requests.count, 1, "a second refresh would have sent a token that the first one had used up")
    }

    func testARefreshTokenThatNoLongerWorksEndsTheSession() async throws {
        let replies: [StubTransport.Reply] = [
            .init(status: 400, body: #"{"error": "invalid_grant", "error_description": "Token is not active"}"#),
            .error(400, code: "refresh_token_expired"),
            .error(401, code: "refresh_token_reused"),
            .error(400, code: "refresh_token_invalidated"),
        ]
        for reply in replies {
            let (account, store) = signedIn(apiKey: "sk-test")
            clock.advance(by: 3600)
            transport.queue(reply)

            let problem = await bearerProblem(account)

            XCTAssertEqual(problem, .signInAgain, reply.body)
            let summary = await account.summary
            XCTAssertEqual(summary.status, .keyOnly, "signed out, with the key still there")
            XCTAssertNil(store.load()?.session)
            let again = await account.beginSignIn(port: 51234, askAgain: false)
            XCTAssertEqual(query(again.page)["client_id"], "oaiapp_1", "the next sign-in is the same user's, so it keeps the client id")
        }
    }

    func testARefreshThatCouldNotBeMadeKeepsTheSession() async throws {
        let (account, store) = signedIn()
        clock.advance(by: 3600)

        let offline = await bearerProblem(account)
        XCTAssertEqual(offline, .unreachable)
        transport.queue(.error(500, code: "server_error"))
        let broken = await bearerProblem(account)
        XCTAssertEqual(broken, .unreachable)

        XCTAssertEqual(store.load()?.session?.refreshToken, "refresh-1")
        transport.queue(.tokens(access: "access-2", refresh: "refresh-2"))
        let bearer = try await account.bearer()
        XCTAssertEqual(bearer, .plan("access-2"), "the same refresh token works once the server answers")
    }

    func testSigningOutRevokesTheRefreshTokenAndForgetsTheUser() async throws {
        let (account, store) = signedIn(apiKey: "sk-test")
        let hostID = try XCTUnwrap(store.load()).hostID
        transport.queue(.init(status: 200, body: ""))

        await account.signOut()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/api/accounts/oauth/revoke")
        XCTAssertEqual(form(request), ["token": "refresh-1", "token_type_hint": "refresh_token", "client_id": "oaiapp_1"])
        XCTAssertEqual(store.load(), Vault(hostID: hostID, apiKey: "sk-test"), "the tokens and the client id are gone, the key is not")
        let summary = await account.summary
        XCTAssertEqual(summary.status, .keyOnly)
        let again = await account.beginSignIn(port: 51234, askAgain: false)
        XCTAssertEqual(query(again.page)["client_id"], "dynamic_agent_client", "the next sign-in may be another user")
        XCTAssertEqual(query(again.page)["ext_agent_host_id"], "urn:uuid:\(hostID.uuidString.lowercased())", "the install is the same")
    }

    func testSigningOutWithNoConnectionStillSignsOut() async {
        let (account, store) = signedIn()
        await account.signOut()
        XCTAssertNil(store.load()?.session)
        let summary = await account.summary
        XCTAssertEqual(summary.status, .signedOut)
    }

    func testAnAPIKeyPaysWhenNobodyIsSignedIn() async throws {
        let store = MemoryVaultStore()
        let account = account(store)
        let nothing = await bearerProblem(account)
        XCTAssertEqual(nothing, .signedOut)

        await account.setAPIKey("  sk-test\n")
        var summary = await account.summary
        XCTAssertEqual(summary.status, .keyOnly)
        let bearer = try await account.bearer()
        XCTAssertEqual(bearer, .apiKey("sk-test"))
        XCTAssertEqual(store.load()?.apiKey, "sk-test")

        await account.setAPIKey(nil)
        summary = await account.summary
        XCTAssertEqual(summary.status, .signedOut)
        XCTAssertNil(store.load()?.apiKey)
    }

    func testThePlanPaysBeforeTheKey() async throws {
        let (account, _) = signedIn(apiKey: "sk-test")
        let bearer = try await account.bearer()
        XCTAssertEqual(bearer, .plan("access-1"))
    }
}
