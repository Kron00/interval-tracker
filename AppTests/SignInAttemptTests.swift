import XCTest
@testable import IntervalTracker

final class SignInAttemptTests: XCTestCase {
    private let hostID = UUID(uuidString: "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10")!

    /// The verifier and the challenge of RFC 7636, appendix B.
    private let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    private let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    private func attempt(port: UInt16 = 51234, clientID: String? = nil) -> SignInAttempt {
        var values = [verifier, "state-1", "nonce-1"].makeIterator()
        return SignInAttempt(port: port, clientID: clientID) { values.next() ?? "" }
    }

    func testAFirstSignInPageCarriesEveryParameterOpenAIAsksFor() {
        let page = attempt().authorizeURL(hostID: hostID, askAgain: false)

        XCTAssertTrue(page.absoluteString.hasPrefix("https://auth.openai.com/api/accounts/authorize?"), page.absoluteString)
        XCTAssertEqual(query(page), [
            "client_id": "dynamic_agent_client",
            "agent_name_hint": "Intervals",
            "ext_agent_host_id": "urn:uuid:0b8e7c52-6a1d-4f0e-9b33-5d2c4a7e9f10",
            "response_type": "code",
            "redirect_uri": "http://127.0.0.1:51234/auth/callback",
            "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
            "resource": "https://api.openai.com/v1",
            "state": "state-1",
            "nonce": "nonce-1",
            "code_challenge_method": "S256",
            "code_challenge": challenge,
        ])
        XCTAssertTrue(
            page.absoluteString.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A51234%2Fauth%2Fcallback&"),
            "the redirect address is one escaped value: \(page.absoluteString)")
    }

    func testALaterSignInUsesTheClientIDThatWasIssued() {
        let page = query(attempt(clientID: "oaiapp_1").authorizeURL(hostID: hostID, askAgain: false))
        XCTAssertEqual(page["client_id"], "oaiapp_1")
        XCTAssertNil(page["agent_name_hint"], "the name is a hint for the first registration only")
        XCTAssertNil(page["prompt"])
    }

    func testAskingAgainForPlanUsageShowsTheConsentPage() {
        let page = query(attempt(clientID: "oaiapp_1").authorizeURL(hostID: hostID, askAgain: true))
        XCTAssertEqual(page["prompt"], "consent")
    }

    func testEveryAttemptHasItsOwnRandomValues() {
        let first = SignInAttempt(port: 1, clientID: nil)
        let second = SignInAttempt(port: 1, clientID: nil)
        let values = [first.verifier, first.state, first.nonce, second.verifier, second.state, second.nonce]
        XCTAssertEqual(Set(values).count, 6)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for value in values {
            XCTAssertEqual(value.count, 43, "32 random bytes in base64url")
            XCTAssertTrue(value.unicodeScalars.allSatisfy(allowed.contains), value)
        }
    }

    func testAValidCallbackGivesTheCodeAndTheIssuedClientID() throws {
        let expected = SignInGrant(code: "the-code", clientID: "oaiapp_1")
        XCTAssertEqual(
            try attempt().grant(from: "/auth/callback?code=the-code&state=state-1&client_id=oaiapp_1&scope=openid%20profile"),
            expected, "as the listener receives it")
        XCTAssertEqual(
            try attempt().grant(from: "  http://127.0.0.1:51234/auth/callback?code=the-code&state=state-1&client_id=oaiapp_1\n"),
            expected, "as pasted from Safari")
        XCTAssertEqual(
            try attempt(clientID: "oaiapp_1").grant(from: "/auth/callback?code=the-code&state=state-1"),
            expected, "a later sign-in keeps the id it already has")
    }

    func testACallbackWithAnotherStateIsRejected() {
        for callback in ["/auth/callback?code=the-code&state=state-2&client_id=oaiapp_1", "/auth/callback?code=the-code&client_id=oaiapp_1"] {
            XCTAssertThrowsError(try attempt().grant(from: callback)) { XCTAssertEqual($0 as? SignInProblem, .otherAttempt) }
        }
    }

    func testARefusalOnTheSignInPageIsReported() {
        XCTAssertThrowsError(try attempt().grant(from: "/auth/callback?error=access_denied&state=state-1")) {
            XCTAssertEqual($0 as? SignInProblem, .denied)
        }
        XCTAssertThrowsError(try attempt().grant(from: "/auth/callback?error=server_error&state=state-1")) {
            XCTAssertEqual($0 as? SignInProblem, .refused)
        }
    }

    func testTextThatIsNotTheCallbackAddressIsRejected() {
        for text in ["", "hello", "https://chatgpt.com/", "http://127.0.0.1:51234/other?code=the-code&state=state-1",
                     "/auth/callback?state=state-1", "/auth/callback"] {
            XCTAssertThrowsError(try attempt().grant(from: text), text) { XCTAssertEqual($0 as? SignInProblem, .notTheAddress, text) }
        }
    }

    func testTheUnregisteredClientIDIsNeverTakenAsTheIssuedOne() {
        XCTAssertThrowsError(try attempt().grant(from: "/auth/callback?code=the-code&state=state-1&client_id=dynamic_agent_client")) {
            XCTAssertEqual($0 as? SignInProblem, .refused)
        }
        XCTAssertThrowsError(try attempt().grant(from: "/auth/callback?code=the-code&state=state-1")) {
            XCTAssertEqual($0 as? SignInProblem, .refused, "a first sign-in must come back with an id")
        }
    }

    func testEveryProblemHasItsOwnSentence() {
        let problems: [SignInProblem] = [.notTheAddress, .otherAttempt, .denied, .refused, .unreachable, .timedOut]
        XCTAssertEqual(Set(problems.map(\.message)).count, problems.count)
    }
}
