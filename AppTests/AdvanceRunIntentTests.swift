import IntervalCore
import XCTest
@testable import IntervalTracker

/// The button in the Live Activity. A tap runs `AdvanceRunIntent.perform`, which is what each test calls.
@MainActor
final class AdvanceRunIntentTests: XCTestCase {
    private var display: RecordingDisplay!
    private var card: LiveActivityController!
    private var run: RunModel!
    private var appHandler: (@MainActor (Int) async -> Void)?

    override func setUp() async throws {
        let log = AudioLog()
        display = RecordingDisplay()
        card = LiveActivityController(display: display, log: log)
        run = RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log),
                       liveActivity: card)
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
        let next = try await button()
        XCTAssertEqual(next.advance, .next)

        try await tap(wait: try await button().wait)

        let waiting = try progress()
        XCTAssertEqual(waiting.phase.title, "Child's Pose")
        XCTAssertTrue(waiting.isWaiting, "a timed stretch waits for its own Start")
        XCTAssertNotNil(run.undo, "it can be taken back like Next on the screen")
        XCTAssertEqual(display.shown.last?.state.title, "Child's Pose", "the card has changed by the time the tap returns")
        let startButton = try await button()
        XCTAssertEqual(startButton.advance, .start)

        try await tap(wait: try await button().wait)

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
        let catCow = try await button().wait

        try await tap(wait: catCow)
        let afterOneTap = run.session
        try await tap(wait: catCow)

        XCTAssertEqual(run.session, afterOneTap, "the run waits for Start, and the second tap was on Next")
        XCTAssertTrue(try progress().isWaiting)
    }

    func testATapThatUndoOvertookDoesNotAdvanceTheRunAgain() async throws {
        run.start(.dailyStretch, cues: CuePreferences())
        let catCow = try await button().wait
        try await tap(wait: catCow)
        XCTAssertEqual(try progress().phase.title, "Child's Pose")

        run.undoLast()
        let backAtCatCow = run.session
        try await tap(wait: catCow)

        XCTAssertEqual(run.session, backAtCatCow, "the same tap, delivered a second time after Undo, is not a new press")
        XCTAssertEqual(try progress().phase.title, "Cat-Cow")

        try await tap(wait: try await button().wait)
        XCTAssertEqual(try progress().phase.title, "Child's Pose", "the button that Undo brought back works")
    }

    func testATapFromAnEarlierWorkoutDoesNothingToTheNextOne() async throws {
        run.start(.dailyStretch, cues: CuePreferences())
        let earlier = try await button().wait
        run.end()

        run.start(.dailyStretch, cues: CuePreferences())
        let fresh = run.session
        try await tap(wait: earlier)

        XCTAssertEqual(run.session, fresh, "the new run waits in the same place, and the tap was for the old one")
        XCTAssertEqual(try progress().phase.title, "Cat-Cow")
    }

    func testATapThatArrivesOnceTheHoldCountsNeitherPausesNorSkipsIt() async throws {
        run.start(.dailyStretch, cues: CuePreferences())
        try await tap(wait: try await button().wait)
        let childsPose = try await button().wait
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
        let catCow = try await button().wait
        run.pause()
        let paused = run.session
        try await tap(wait: catCow)
        XCTAssertEqual(run.session, paused, "Start keeps a paused run paused, so a paused wait has no button and takes no tap")

        run.start(.norwegian4x4, cues: CuePreferences())
        let warmUp = run.session
        try await tap(wait: 0)
        XCTAssertEqual(run.session, warmUp, "an interval timer never waits, so it has no button and takes no tap")
        XCTAssertNil(run.undo)
    }

    private func tap(wait: Int) async throws {
        _ = try await AdvanceRunIntent(wait: wait).perform()
    }

    /// What the button on the card says and carries, once the card shows the run as it is now.
    private func button() async throws -> (advance: RunActivityAttributes.Advance, wait: Int) {
        await card.settle()
        guard case .waiting(_, let advance, let wait)? = display.shown.last?.state.clock else { throw NotWaiting() }
        return (advance, wait)
    }

    private func progress() throws -> RunProgress {
        guard case .active(let progress)? = run.session?.snapshot(at: .now) else { throw NotWaiting() }
        return progress
    }

    private struct NotWaiting: Error {}
}
