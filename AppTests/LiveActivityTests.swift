import IntervalCore
import XCTest
@testable import IntervalTracker

/// Stands in for ActivityKit. Each call gives way once before it lands, as a real update does, so a
/// second update has the chance to overtake the first.
@MainActor
final class RecordingDisplay: RunActivityDisplay {
    enum Event: Equatable {
        case show(RunActivityCard, alerting: Bool)
        case clear
    }

    var isAllowed = true
    var failure: (any Error)?
    private(set) var events: [Event] = []

    var shown: [RunActivityCard] {
        events.compactMap { if case .show(let card, _) = $0 { card } else { nil } }
    }

    func show(_ card: RunActivityCard, alerting: Bool) async throws {
        await Task.yield()
        if let failure { throw failure }
        events.append(.show(card, alerting: alerting))
    }

    func clear() async {
        await Task.yield()
        events.append(.clear)
    }
}

@MainActor
final class LiveActivityContentTests: XCTestCase {
    private typealias State = RunActivityAttributes.ContentState
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testACountingPhaseCarriesItsStartAndEndAndNothingThatChangesWithTheClock() {
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        let warmUp = State(
            title: "Warm-up", caption: nil, upNext: "Work 4:00", tone: .prepare,
            clock: .counting(from: start, to: start + 300), isHeadsUp: false)
        for second in [0.0, 0.1, 1, 137.3, 269.9] {
            XCTAssertEqual(State(session, at: start + second), warmUp, "\(second)")
        }
    }

    func testTheHeadsUpTurnsOnThirtySecondsBeforeWorkAndOffWhenWorkBegins() {
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        XCTAssertFalse(State(session, at: start + 269.9).isHeadsUp)
        XCTAssertEqual(State(session, at: start + 270), State(
            title: "Warm-up", caption: nil, upNext: "Work 4:00", tone: .prepare,
            clock: .counting(from: start, to: start + 300), isHeadsUp: true))
        XCTAssertEqual(State(session, at: start + 300), State(
            title: "Work", caption: "Round 1 of 4", upNext: "Rest 3:00", tone: .effort,
            clock: .counting(from: start + 300, to: start + 540), isHeadsUp: false))
        XCTAssertEqual(State(session, at: start + 700), State(
            title: "Rest", caption: "Round 1 of 4", upNext: "Work 4:00", tone: .recover,
            clock: .counting(from: start + 540, to: start + 720), isHeadsUp: true))
    }

    func testAPausedRunShowsTheTimeLeftAndStaysAsItIs() {
        var session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        session.pause(at: start + 310)
        let paused = State(
            title: "Work", caption: "Round 1 of 4", upNext: "Rest 3:00", tone: .paused,
            clock: .paused("3:50"), isHeadsUp: false)
        XCTAssertEqual(State(session, at: start + 310), paused)
        XCTAssertEqual(State(session, at: start + 5000), paused)

        session.resume(at: start + 1000)
        XCTAssertEqual(State(session, at: start + 1000).clock, .counting(from: start + 990, to: start + 1230))
    }

    /// Daily Stretch opens on Cat-Cow, 10 reps. Child's Pose for 0:45 and Cobra for 0:30 follow.
    func testAStretchCountedInRepsWaitsForNextWithItsCount() {
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        let waiting = State(
            title: "Cat-Cow", caption: "Stretch 1 of 10", upNext: "Child's Pose 0:45", tone: .stretch,
            clock: .waiting("10 reps", for: .next), isHeadsUp: false)
        XCTAssertEqual(State(session, at: start), waiting)
        XCTAssertEqual(State(session, at: start + 900), waiting)

        session.pause(at: start + 900)
        XCTAssertEqual(State(session, at: start + 900).clock, .paused("10 reps"))
        XCTAssertEqual(State(session, at: start + 900).tone, .paused)
    }

    func testATimedHoldWaitsForStartWithItsLengthThenCountsInAndHolds() {
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        session.perform(.next, at: start + 8)
        let waiting = State(
            title: "Child's Pose", caption: "Stretch 2 of 10", upNext: "Cobra 0:30", tone: .prepare,
            clock: .waiting("0:45", for: .start), isHeadsUp: false)
        XCTAssertEqual(State(session, at: start + 8), waiting)
        XCTAssertEqual(State(session, at: start + 900), waiting, "nothing counts until Start")

        session.perform(.next, at: start + 900)
        let countIn = State(
            title: "Child's Pose", caption: "Get ready", upNext: "Cobra 0:30", tone: .prepare,
            clock: .counting(from: start + 900, to: start + 903), isHeadsUp: false)
        XCTAssertEqual(State(session, at: start + 900), countIn, "a count-in says to get ready, and it is not a heads-up")
        XCTAssertEqual(State(session, at: start + 902.9), countIn)

        let hold = State(
            title: "Child's Pose", caption: "Stretch 2 of 10", upNext: "Cobra 0:30", tone: .stretch,
            clock: .counting(from: start + 903, to: start + 948), isHeadsUp: false)
        XCTAssertEqual(State(session, at: start + 903), hold)
        XCTAssertEqual(State(session, at: start + 947.9), hold)

        XCTAssertEqual(State(session, at: start + 5000), State(
            title: "Cobra", caption: "Stretch 3 of 10", upNext: "Hip Flexor Couch Stretch 0:45", tone: .prepare,
            clock: .waiting("0:30", for: .start), isHeadsUp: false), "the hold ends by itself and the next stretch waits")
    }

    func testAStretchReachedWhilePausedShowsItsLengthAndNotAnEmptyClock() {
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        session.perform(.next, at: start)
        session.perform(.next, at: start)
        session.pause(at: start + 10)
        XCTAssertEqual(State(session, at: start + 10).clock, .paused("0:38"), "7 of the 45 seconds are done")

        session.perform(.next, at: start + 10)
        XCTAssertEqual(State(session, at: start + 10), State(
            title: "Cobra", caption: "Stretch 3 of 10", upNext: "Hip Flexor Couch Stretch 0:45", tone: .paused,
            clock: .paused("0:30"), isHeadsUp: false))
    }

    /// One stretch of 5 seconds, so its count-in is the default 3 seconds.
    func testTheLastTimedHoldFinishesByItself() throws {
        let hold = try XCTUnwrap(Stretch(name: "Calf", amount: .hold(try XCTUnwrap(Span(seconds: 5))), sides: .once, howTo: nil))
        let workout = Workout(name: "Short", plan: .routine(try XCTUnwrap(Routine(stretches: [hold]))))
        var session = Session(workout, cues: CuePreferences(), startingAt: start)
        XCTAssertEqual(State(session, at: start + 60), State(
            title: "Calf", caption: "Stretch 1 of 1", upNext: "Finish", tone: .prepare,
            clock: .waiting("0:05", for: .start), isHeadsUp: false))

        session.perform(.next, at: start + 60)
        XCTAssertEqual(State(session, at: start + 67.9).clock, .counting(from: start + 63, to: start + 68))
        XCTAssertEqual(State(session, at: start + 68), State(
            title: "Workout complete", caption: nil, upNext: nil, tone: .finished,
            clock: .finished("0:08"), isHeadsUp: false), "the count-in and the hold were both worked")
    }

    func testAFinishedRunShowsTheTimeWorked() {
        var session = Session(.audioCheck, cues: CuePreferences(), startingAt: start)
        let finished = State(
            title: "Workout complete", caption: nil, upNext: nil, tone: .finished,
            clock: .finished("1:00"), isHeadsUp: false)
        XCTAssertEqual(State(session, at: start + 60), finished)
        XCTAssertEqual(State(session, at: start + 4000), finished)

        XCTAssertEqual(State(session, at: start + 55).upNext, "Finish")
        session.perform(.next, at: start + 10)
        XCTAssertEqual(State(session, at: start + 100).clock, .finished("0:40"), "20 seconds of the warm-up were skipped")
    }
}

@MainActor
final class LiveActivityControllerTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testOnePhaseIsShownOnceHoweverOftenItIsReconciled() async {
        let (controller, display) = await make()
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)

        for tick in 0..<50 {
            controller.reconcile(session, at: start + Double(tick) / 10)
            await settle(controller)
        }

        XCTAssertEqual(display.events, [.clear, .show(card(session, at: 0), alerting: false)])
    }

    func testEveryChangeOfStateIsShownInOrderAndOnlyTheHeadsUpAlerts() async {
        let (controller, display) = await make()
        var session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        var expected: [RecordingDisplay.Event] = [.clear]

        for (second, alerting) in [(0.0, false), (269.9, false), (270, true), (299.9, false), (300, false), (690, true), (700, false)] {
            controller.reconcile(session, at: start + second)
            await settle(controller)
            if display.events.count > expected.count {
                expected.append(.show(card(session, at: second), alerting: alerting))
            }
        }
        session.pause(at: start + 705)
        controller.reconcile(session, at: start + 705)
        await settle(controller)
        expected.append(.show(card(session, at: 705), alerting: false))

        XCTAssertEqual(display.events, expected)
        XCTAssertEqual(display.shown.map(\.state.title), ["Warm-up", "Warm-up", "Work", "Rest", "Rest"])
        XCTAssertEqual(display.shown.map(\.state.isHeadsUp), [false, true, false, true, true])
        XCTAssertEqual(display.shown.last?.state.tone, .paused)
    }

    func testAHeadsUpAlertsOnceThoughASkipAndItsUndoComeBackIntoIt() async {
        let (controller, display) = await make()
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        var skipped = session
        skipped.perform(.next, at: start + 280)

        // The warm-up's heads-up begins at 4:30. The skip at 4:40 goes to work, and Undo puts the
        // run back as it was.
        for (run, second) in [(session, 270.0), (skipped, 280), (session, 282)] {
            controller.reconcile(run, at: start + second)
            await settle(controller)
        }
        XCTAssertEqual(display.events, [
            .clear, .show(card(session, at: 270), alerting: true), .show(card(skipped, at: 280), alerting: false),
            .show(card(session, at: 282), alerting: false),
        ])

        // Going back to the start of the warm-up is another run through it, so its heads-up alerts again.
        var again = session
        again.perform(.previous, at: start + 285)
        controller.reconcile(again, at: start + 285)
        await settle(controller)
        controller.reconcile(again, at: start + 285 + 270)
        await settle(controller)
        XCTAssertEqual(display.events.last, .show(RunActivityCard(name: again.workout.name, state: .init(again, at: start + 285 + 270)), alerting: true))
    }

    func testARoutineShowsEachWaitCountInAndHoldOnceAndNeverAlerts() async {
        let (controller, display) = await make()
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        func reconcile(at seconds: TimeInterval...) async {
            for second in seconds {
                controller.reconcile(session, at: start + second)
                await settle(controller)
            }
        }

        await reconcile(at: 0, 0.1, 30)
        session.perform(.next, at: start + 30)
        await reconcile(at: 30, 30.1, 50)
        session.perform(.next, at: start + 50)
        await reconcile(at: 50, 51, 52.9, 53, 60, 97.9, 98, 98.1, 500)

        XCTAssertEqual(display.shown.map(\.state.clock), [
            .waiting("10 reps", for: .next),
            .waiting("0:45", for: .start),
            .counting(from: start + 50, to: start + 53),
            .counting(from: start + 53, to: start + 98),
            .waiting("0:30", for: .start),
        ])
        XCTAssertEqual(display.shown.map(\.state.title), ["Cat-Cow", "Child's Pose", "Child's Pose", "Child's Pose", "Cobra"])
        XCTAssertEqual(display.events.count, 6, "the launch clears, then one card for each state")
        for event in display.events {
            if case .show(_, alerting: true) = event { XCTFail("a routine has no heads-up, yet \(event) alerted") }
        }
    }

    func testChangesThatArriveDuringAnUpdateEndOnTheNewestAndNeverGoBackwards() async {
        let (controller, display) = await make()
        var session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)

        controller.reconcile(session, at: start)
        session.perform(.next, at: start + 1)
        controller.reconcile(session, at: start + 1)
        session.perform(.next, at: start + 2)
        controller.reconcile(session, at: start + 2)
        session.pause(at: start + 3)
        controller.reconcile(session, at: start + 3)
        await settle(controller)

        XCTAssertEqual(display.shown.last, card(session, at: 3))
        XCTAssertEqual(display.shown.last?.state.title, "Rest")
        let order = ["Warm-up", "Work", "Rest"]
        let positions = display.shown.compactMap { order.firstIndex(of: $0.state.title) }
        XCTAssertEqual(positions, positions.sorted(), "\(display.shown.map(\.state.title))")
    }

    func testEndingTheRunClearsTheActivityAndAStoppedRunSendsNothingMore() async {
        let (controller, display) = await make()
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        controller.reconcile(session, at: start)
        await settle(controller)

        controller.reconcile(nil, at: start + 5)
        await settle(controller)
        controller.reconcile(nil, at: start + 6)
        await settle(controller)

        XCTAssertEqual(display.events, [.clear, .show(card(session, at: 0), alerting: false), .clear])
    }

    func testWithLiveActivitiesTurnedOffNothingIsShownAndSettingsIsTold() async {
        let (controller, display) = await make()
        display.isAllowed = false
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)

        controller.reconcile(session, at: start)
        await settle(controller)
        XCTAssertEqual(display.events, [.clear])
        XCTAssertEqual(controller.problem, "Live Activities are turned off for Intervals in the Settings app.")

        display.isAllowed = true
        XCTAssertNil(controller.problem)
        controller.reconcile(session, at: start + 300)
        await settle(controller)
        XCTAssertEqual(display.shown.map(\.state.title), ["Work"], "the next change of phase tries again")
    }

    func testARefusalIsReportedOnceAndTheRunCarriesOn() async {
        let log = AudioLog()
        let display = RecordingDisplay()
        let controller = LiveActivityController(display: display, log: log)
        display.failure = Refused()
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)

        controller.reconcile(session, at: start)
        await settle(controller)
        controller.reconcile(session, at: start + 300)
        await settle(controller)

        XCTAssertEqual(controller.problem, "The Live Activity could not start: the extension is missing")
        XCTAssertEqual(log.lines.filter { $0.contains("live activity") }.count, 1)

        display.failure = nil
        controller.reconcile(session, at: start + 540)
        await settle(controller)
        XCTAssertNil(controller.problem)
        XCTAssertEqual(display.shown.map(\.state.title), ["Rest"])
    }

    private struct Refused: LocalizedError {
        var errorDescription: String? { "the extension is missing" }
    }

    private func make() async -> (LiveActivityController, RecordingDisplay) {
        let display = RecordingDisplay()
        let controller = LiveActivityController(display: display, log: AudioLog())
        await settle(controller)
        return (controller, display)
    }

    private func settle(_ controller: LiveActivityController) async {
        while let worker = controller.worker { await worker.value }
    }

    private func card(_ session: Session, at second: TimeInterval) -> RunActivityCard {
        RunActivityCard(name: session.workout.name, state: .init(session, at: start + second))
    }
}
