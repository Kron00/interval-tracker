import IntervalCore
import XCTest
@testable import IntervalTracker

private let tabata = #"""
    {"kind": "intervals", "name": "Bike Tabata", "note": "I added a warm-up.", "stretches": null,
     "intervals": {"warmUpSeconds": 300, "workSeconds": 20, "restSeconds": 10, "rounds": 8,
                   "coolDownSeconds": null, "restAfterLastRound": false}}
    """#

final class WorkoutGeneratorTests: XCTestCase {
    private let transport = StubTransport()
    private let clock = TestClock()

    private func generator(_ vault: Vault?) -> WorkoutGenerator {
        let account = ChatGPTAccount(transport: transport, store: MemoryVaultStore(vault), now: { [clock] in clock.now })
        return WorkoutGenerator(account: account, transport: transport)
    }

    private func onThePlan() -> WorkoutGenerator {
        generator(signedInVault(at: clock))
    }

    private func failure(_ generator: WorkoutGenerator, model: String = "gpt-6-luna") async -> GenerationFailure? {
        do {
            _ = try await generator.generate("Tabata on the bike", model: model)
            return nil
        } catch {
            return error
        }
    }

    private func expectedTabata() throws -> Intervals {
        Intervals(
            warmUp: Span(seconds: 300), work: try XCTUnwrap(Span(seconds: 20)), rest: Span(seconds: 10),
            rounds: try XCTUnwrap(Count(8)), coolDown: nil, restAfterLastRound: false)
    }

    func testTheRequestIsOneThePlanRouteAccepts() async throws {
        transport.queue(.stream(tabata))

        let generated = try await onThePlan().generate("Tabata on the bike", model: "gpt-6-luna")

        XCTAssertEqual(generated.workout.name, "Bike Tabata")
        XCTAssertEqual(generated.workout.plan, .intervals(try expectedTabata()))
        XCTAssertEqual(generated.note, "I added a warm-up.")

        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

        let body = try json(request)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["instructions"] as? String, WorkoutBlueprint.instructions)
        XCTAssertEqual(body["input"] as? [[String: String]], [["role": "user", "content": "Tabata on the bike"]])
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertNotNil(format["name"] as? String)
        let schema = try JSONSerialization.jsonObject(with: Data(WorkoutBlueprint.schema.utf8)) as? NSDictionary
        XCTAssertEqual(format["schema"] as? NSDictionary, schema)

        let rejected = [
            "background", "conversation", "max_output_tokens", "max_tool_calls", "metadata", "moderation", "multi_agent",
            "prompt", "prompt_cache_retention", "safety_identifier", "temperature", "top_logprobs", "top_p", "truncation",
            "user", "previous_response_id",
        ]
        for field in rejected {
            XCTAssertNil(body[field], "the plan route turns down a request that has \(field)")
        }
    }

    func testTheAnswerIsPutTogetherFromItsDeltas() async throws {
        transport.queue(.stream(tabata, deltasOf: 7))
        let generated = try await onThePlan().generate("Tabata on the bike", model: "gpt-6-luna")
        XCTAssertEqual(generated.workout.plan, .intervals(try expectedTabata()))
    }

    func testAStreamThatEndsWithoutCompletedIsNotAnAnswer() async {
        transport.queue(.stream(tabata, ending: nil))
        let cutOff = await failure(onThePlan())
        XCTAssertEqual(cutOff, .incomplete, "the whole text arrived, and the server never said it was the whole text")

        transport.queue(.stream(tabata, ending: #"{"type": "response.incomplete", "response": {"status": "incomplete"}}"#))
        let incomplete = await failure(onThePlan())
        XCTAssertEqual(incomplete, .incomplete)
    }

    func testAFailureInsideTheStreamIsReported() async {
        transport.queue(.stream("{\"kind\"", ending: #"{"type": "response.failed", "response": {"status": "failed", "error": {"code": "subscription_sharing_usage_limit_exceeded", "message": "Usage limit reached."}}}"#))
        let limit = await failure(onThePlan())
        XCTAssertEqual(limit, .usageLimit)

        transport.queue(.stream("", ending: #"{"type": "error", "code": "server_error", "message": "Something went wrong.", "param": null}"#))
        let broken = await failure(onThePlan())
        XCTAssertEqual(broken, .server)
    }

    func testTextAfterCompletedIsNotPartOfTheAnswer() {
        var stream = ResponseStream()
        for line in [
            #"data: {"type": "response.output_text.delta", "delta": "one "}"#,
            #": a comment"#,
            #"event: response.output_text.delta"#,
            #"data: {"type": "response.output_text.delta", "delta": "two"}"#,
            #"data: {"type": "response.output_text.done", "text": "one two"}"#,
            #"data: not json"#,
            #"data: {"type": "response.completed"}"#,
            #"data: {"type": "response.output_text.delta", "delta": " three"}"#,
            #"data: [DONE]"#,
        ] {
            stream.read(line)
        }
        XCTAssertEqual(stream.text, "one two")
        XCTAssertEqual(stream.ending, .completed)
    }

    func testASchemaRefusalIsRetriedOnceWithTheSchemaInTheInstructions() async throws {
        let refusals: [StubTransport.Reply] = [
            .error(400, code: "subscription_sharing_unsupported_capability", param: "text.format"),
            .error(400, code: "subscription_sharing_unsupported_capability"),
            .error(400, code: "unsupported_parameter", param: "text"),
        ]
        for refusal in refusals {
            let transport = StubTransport()
            let account = ChatGPTAccount(transport: transport, store: MemoryVaultStore(signedInVault(at: clock)), now: { [clock] in clock.now })
            transport.queue(refusal, .stream(tabata))

            let generated = try await WorkoutGenerator(account: account, transport: transport)
                .generate("Tabata on the bike", model: "gpt-6-luna")

            XCTAssertEqual(generated.workout.plan, .intervals(try expectedTabata()), refusal.body)
            XCTAssertEqual(transport.requests.count, 2)
            let second = try json(transport.requests[1])
            XCTAssertNil(second["text"], "the retry sends no schema")
            XCTAssertEqual(second["instructions"] as? String, WorkoutBlueprint.instructionsWithSchema)
            XCTAssertEqual(second["store"] as? Bool, false)
            XCTAssertEqual(second["stream"] as? Bool, true)
        }
    }

    func testASecondRefusalIsNotRetried() async {
        transport.queue(
            .error(400, code: "subscription_sharing_unsupported_capability", param: "text.format"),
            .error(400, code: "subscription_sharing_unsupported_capability", param: "text.format"),
            .stream(tabata))
        let refused = await failure(onThePlan())
        XCTAssertEqual(refused, .unsupported(param: "text.format"))
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testARefusalOfSomethingElseIsNotRetried() async {
        transport.queue(.error(400, code: "subscription_sharing_unsupported_capability", param: "model"), .stream(tabata))
        let refused = await failure(onThePlan())
        XCTAssertEqual(refused, .unsupported(param: "model"))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testEachDocumentedErrorIsToldApart() async {
        let cases: [(StubTransport.Reply, GenerationFailure)] = [
            (.error(429, code: "subscription_sharing_usage_limit_exceeded"), .usageLimit),
            (.error(403, code: "subscription_sharing_user_not_eligible"), .notEligible),
            (.error(403, code: "subscription_sharing_route_not_supported"), .routeNotSupported),
            (.error(400, code: "subscription_sharing_unsupported_capability", param: "tools"), .unsupported(param: "tools")),
            (.error(429, code: "rate_limit_exceeded"), .busy),
            (.error(500, code: "server_error"), .server),
            (.init(status: 502, body: "<html>Bad gateway</html>"), .server),
        ]
        for (reply, expected) in cases {
            transport.queue(reply)
            let got = await failure(onThePlan())
            XCTAssertEqual(got, expected, reply.body)
        }
        XCTAssertTrue(GenerationFailure.usageLimit.offersManageUsage)
        XCTAssertFalse(GenerationFailure.notEligible.offersManageUsage)
    }

    func testEveryFailureIsOnePlainSentenceOfItsOwn() {
        let failures: [GenerationFailure] = [
            .signedOut, .planUsageOff, .signInAgain, .keyRejected, .noCredit, .usageLimit, .notEligible, .routeNotSupported,
            .unsupported(param: "text.format"), .busy, .server, .unreachable, .incomplete, .noModels, .unusable(.noStretches),
        ]
        XCTAssertEqual(Set(failures.map(\.message)).count, failures.count)
        for failure in failures {
            XCTAssertFalse(failure.message.isEmpty)
            for raw in ["subscription_sharing", "text.format", "{", "error", "400", "429"] {
                XCTAssertFalse(failure.message.contains(raw), "\(failure) shows the server's own words: \(failure.message)")
            }
        }
    }

    func testATokenTheServerTurnsDownIsRefreshedOnce() async throws {
        transport.queue(
            .error(401, code: "invalid_token"),
            .tokens(access: "access-2", refresh: "refresh-2"),
            .stream(tabata))

        _ = try await onThePlan().generate("Tabata on the bike", model: "gpt-6-luna")

        XCTAssertEqual(transport.requests.map(\.url?.lastPathComponent), ["responses", "token", "responses"])
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testATokenTurnedDownTwiceAsksForANewSignIn() async {
        transport.queue(
            .error(401, code: "invalid_token"),
            .tokens(access: "access-2", refresh: "refresh-2"),
            .error(401, code: "invalid_token"),
            .stream(tabata))
        let ended = await failure(onThePlan())
        XCTAssertEqual(ended, .signInAgain)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testARefreshTokenThatNoLongerWorksAsksForANewSignIn() async {
        let generator = onThePlan()
        clock.advance(by: 3600)
        transport.queue(.error(400, code: "refresh_token_expired"))
        let ended = await failure(generator)
        XCTAssertEqual(ended, .signInAgain)
        XCTAssertEqual(transport.requests.map(\.url?.lastPathComponent), ["token"], "nothing was sent to the model")
    }

    func testAnAPIKeyPaysWhenNobodyIsSignedIn() async throws {
        let generator = generator(Vault(apiKey: "sk-test"))
        transport.queue(.stream(tabata))
        _ = try await generator.generate("Tabata on the bike", model: "gpt-6-luna")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        transport.queue(.error(401, code: "invalid_api_key"))
        let rejected = await failure(generator)
        XCTAssertEqual(rejected, .keyRejected)
        XCTAssertEqual(transport.requests.count, 2, "a key cannot be refreshed, so nothing is retried")

        transport.queue(.error(429, code: "insufficient_quota"))
        let empty = await failure(generator)
        XCTAssertEqual(empty, .noCredit)
    }

    func testNothingIsSentWhenNothingCanPay() async {
        let signedOut = await failure(generator(nil))
        XCTAssertEqual(signedOut, .signedOut)
        let declined = await failure(generator(signedInVault(scope: "openid profile email offline_access", at: clock)))
        XCTAssertEqual(declined, .planUsageOff)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testNoConnectionIsReported() async {
        let offline = await failure(onThePlan())
        XCTAssertEqual(offline, .unreachable)
    }

    func testAnAnswerThatIsNotAWorkoutIsReported() async {
        transport.queue(.stream(#"{"kind": "routine", "name": "Nothing", "note": null, "intervals": null, "stretches": []}"#))
        let empty = await failure(onThePlan())
        XCTAssertEqual(empty, .unusable(.noStretches))

        transport.queue(.stream("I can only help with workouts."))
        let prose = await failure(onThePlan())
        XCTAssertEqual(prose, .unusable(.unreadable))
    }

    func testThePlanListsOnlyTheModelsMarkedForListing() async throws {
        transport.queue(.init(body: #"""
            {"models": [
              {"slug": "gpt-6.1-sol", "visibility": "list"},
              {"slug": "gpt-6-internal", "visibility": "hide"},
              {"slug": "gpt-6-luna", "visibility": "list"},
              {"slug": "gpt-6-unmarked"}
            ]}
            """#))

        let models = try await onThePlan().models()

        XCTAssertEqual(models, ["gpt-6.1-sol", "gpt-6-luna"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
    }

    func testAnAPIKeyListsTheChatModelsItCanReach() async throws {
        transport.queue(.init(body: #"{"object": "list", "data": [{"id": "text-embedding-4"}, {"id": "gpt-6.1-sol"}, {"id": "gpt-6-luna"}, {"id": "whisper-2"}]}"#))
        let models = try await generator(Vault(apiKey: "sk-test")).models()
        XCTAssertEqual(models, ["gpt-6-luna", "gpt-6.1-sol"])
    }

    func testTheSmallestListedModelIsTheDefault() {
        XCTAssertEqual(ModelList.smallest(of: ["gpt-6.1-sol", "gpt-6-luna"]), "gpt-6-luna")
        XCTAssertEqual(ModelList.smallest(of: ["gpt-7", "gpt-7-mini"]), "gpt-7-mini")
        // The list a ChatGPT plan returned on 12 November 2026. The newest small model comes first.
        XCTAssertEqual(ModelList.smallest(of: ["gpt-6.1-sol", "gpt-6-astra", "gpt-6.1-terra", "gpt-6-sol", "gpt-6-luna",
                                                "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]), "gpt-6-luna")
        XCTAssertEqual(ModelList.smallest(of: ["gpt-7", "gpt-7-pro"]), "gpt-7", "with no small model named, the first one listed")
        XCTAssertNil(ModelList.smallest(of: []))
    }
}
