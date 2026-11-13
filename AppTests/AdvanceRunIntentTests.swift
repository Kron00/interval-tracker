import IntervalCore
import XCTest
@testable import IntervalTracker

/// The button in the Live Activity. A tap runs `AdvanceRunIntent.perform`, which is what each test calls.
@MainActor
final class AdvanceRunIntentTests: XCTestCase {
    private var display: RecordingDisplay!
    private var run: RunModel!
    private var appHandler: (@MainActor (Int) async -> Void)?

    override func setUp() async throws {
        let log = AudioLog()
        display = RecordingDisplay()
        run = RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log),
                       liveActivity: LiveActivityController(display: display, log: log))
        // The app that hosts the tests has pointed the intent at its own run.
        appHandler = AdvanceRunIntent.onPerform
        AdvanceRunIntent.onPerform = { [run] in await run?.advance(fromWait: $0) }
    }

    override func tearDown() async throws {
        run.end()
        AdvanceRunIntent.onPerform = appHandler
    }

    /// Daily Stretch opens on Cat-Cow, counted in reps. Child's Pose for 0:45 follows.
    func testATapOnNextThenOnStartMovesAWaitingRunOnAsTheButtonInTheAppDoes() async throws {
        run.start(.dailyStretch, cues: CuePreferences())
        XCTAssertEqual(try button().advance, .next)

        try await tap(wait: try button().wait)

        let waiting = try progress()
        XCTAssertEqual(waiting.phase.title, "Child's Pose")
        XCTAssertTrue(waiting.isWaiting, "a timed stretch waits for its own Start")
        XCTAssertNotNil(run.undo, "it can be taken back like Next on the screen")
        XCTAssertEqual(display.shown.last?.state.title, "Child's Pose", "the card has changed by the time the tap returns")
        XCTAssertEqual(try button().advance, .start)

        try await tap(wait: try button().wait)

        let countIn = try progress()
        XCTAssertEqual(countIn.phase.title, "Child's Pose")
        XCTAssertEqual(countIn.phase.caption, "Get ready")
        XCTAssertFalse(countIn.isWaiting)
        XCTAssertFalse(countIn.isPaused)
        guard case .counting = display.shown.last?.state.clock else {
            return XCTFail("the card should count down, and it shows \(String(describing: display.shown.last))")
        }
    }

    func testASecondTapFromTheSameCardDoesNothing() async throws {
        run.start(.dailyStretch, cues: CuePreferences())
        let catCow = try button().wait

        try await tap(wait: catCow)
        let afterOneTap = run.session
        try await tap(wait: catCow)

        XCTAssertEqual(run.session, afterOneTap, "the run waits for Start, and the second tap was on Next")
        XCTAssertTrue(try progress().isWaiting)
    }

    func testATapThatArrivesOnceTheHoldCountsNeitherPausesNorSkipsIt() async throws {
        run.start(.dailyStretch, cues: CuePreferences())
        try await tap(wait: try button().wait)
        let childsPose = try button().wait
        try await tap(wait: childsPose)
        let counting = run.session

        try await tap(wait: childsPose)

        XCTAssertEqual(run.session, counting)
        XCTAssertFalse(try progress().isPaused)
        XCTAssertFalse(try progress().isWaiting)
        XCTAssertEqual(try progress().phase.title, "Child's Pose")
    }

    func testATapDoesNothingToAPausedWaitOrToAnIntervalTimerOrWithNoRun() async throws {
        try await tap(wait: 0)
        XCTAssertNil(run.session)

        run.start(.dailyStretch, cues: CuePreferences())
        let catCow = try button().wait
        run.pause()
        let paused = run.session
        try await tap(wait: catCow)
        XCTAssertEqual(run.session, paused, "Start keeps a paused run paused, so a paused wait has no button and takes no tap")

        run.start(.norwegian4x4, cues: CuePreferences())
        let warmUp = run.session
        try await tap(wait: 0)
        XCTAssertEqual(run.session, warmUp, "a warm-up is the first segment too, and it is not a wait")
        XCTAssertNil(run.undo)
    }

    private func tap(wait: Int) async throws {
        _ = try await AdvanceRunIntent(wait: wait).perform()
    }

    /// What the button of the card says and carries, as the Live Activity would draw it now.
    private func button() throws -> (advance: RunActivityAttributes.Advance, wait: Int) {
        guard case .waiting(_, let advance, let wait)? = run.session.map({ RunActivityAttributes.ContentState($0, at: .now).clock }) else {
            throw NotWaiting()
        }
        return (advance, wait)
    }

    private func progress() throws -> RunProgress {
        guard case .active(let progress)? = run.session?.snapshot(at: .now) else { throw NotWaiting() }
        return progress
    }

    private struct NotWaiting: Error {}
}
