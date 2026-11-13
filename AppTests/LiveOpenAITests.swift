import IntervalCore
import XCTest
@testable import IntervalTracker

/// The one test that contacts OpenAI. It needs a person with a ChatGPT account, so it runs only
/// when asked for:
///
///     TEST_RUNNER_LIVE_OPENAI=1 xcodebuild test ... -only-testing:IntervalTrackerTests/LiveOpenAITests
///
/// It prints a sign-in address and waits. Open the address in a browser on the Mac that runs the
/// simulator. The simulator shares that Mac's loopback interface, so ChatGPT's redirect reaches the
/// listener inside the app. The test keeps nothing: the tokens live in memory and it signs out.
@MainActor
final class LiveOpenAITests: XCTestCase {
    func testSigningInAndDescribingAWorkoutAgainstOpenAI() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_OPENAI"] == "1", "this test signs in to a real ChatGPT account")
        let suite = "LiveOpenAITests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = URLSessionTransport()
        let account = ChatGPTAccount(transport: transport, store: MemoryVaultStore())
        let model = ChatGPTModel(
            account: account, generator: WorkoutGenerator(account: account, transport: transport), defaults: defaults,
            openInSafari: { print("LIVE_OPENAI sign in at: \($0.absoluteString)") })

        await model.signIn(by: .safari)
        XCTAssertNil(model.signInProblem)
        XCTAssertEqual(model.status, .planUsage)
        XCTAssertFalse(model.models.isEmpty, "a plan lists the models it may use")
        print("LIVE_OPENAI models: \(model.models), chosen: \(model.model ?? "none")")

        switch await model.generate("15-minute hip mobility routine") {
        case .success(let generated):
            guard case .routine(let routine) = generated.workout.plan else {
                return XCTFail("a hip mobility routine is a stretch routine, not \(generated.workout.plan)")
            }
            XCTAssertFalse(routine.stretches.isEmpty)
            print("LIVE_OPENAI workout: \(generated.workout.name), \(routine.stretches.map(\.name)), note: \(generated.note ?? "none")")
        case .failure(let failure):
            XCTFail("OpenAI did not build a workout: \(failure)")
        }

        await model.signOut()
        XCTAssertEqual(model.status, .signedOut)
    }
}
