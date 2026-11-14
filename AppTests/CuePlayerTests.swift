import IntervalCore
import XCTest
@testable import IntervalTracker

@MainActor
final class CuePlayerTests: XCTestCase {
    func testLateVoicesCanBeQueuedBetweenPhrasesWhileTheMusicStaysDucked() throws {
        let work = try XCTUnwrap(Span(seconds: 4))
        let rounds = try XCTUnwrap(Count(2))
        let plan = Plan.intervals(Intervals(
            warmUp: nil, work: work, rest: work, rounds: rounds, coolDown: nil, restAfterLastRound: false))
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = Session(Workout(name: "Short", plan: plan), cues: CuePreferences(), startingAt: start)
        let schedule = try XCTUnwrap(session.cueSchedule)

        let duringThePhrase = start.addingTimeInterval(1)
        let betweenPhrases = start.addingTimeInterval(3)
        XCTAssertTrue(schedule.isDucked(at: duringThePhrase))
        XCTAssertTrue(schedule.isDucked(at: betweenPhrases), "4-second phases keep the music low from start to finish")
        XCTAssertTrue(CuePlayer.voiceIsSounding(in: schedule, at: duringThePhrase))
        XCTAssertFalse(CuePlayer.voiceIsSounding(in: schedule, at: betweenPhrases))
    }

    /// Every skip and every press of back hands the player a new schedule. The player must queue the
    /// new one in place of the old, or a landing the run has already left would still sound.
    func testEachNewScheduleIsQueuedInPlaceOfTheLast() throws {
        let log = AudioLog()
        let player = CuePlayer(bank: SoundBank(log: log), log: log)
        defer { player.reconcile(.none, at: .now) }
        let now = Date.now
        let before = Session(.norwegian4x4, cues: CuePreferences(), startingAt: now - 100)
        var skipped = before
        guard case .active(let warmUp) = before.snapshot(at: now) else { return XCTFail("the run has finished") }
        skipped.skip(warmUp.segment, at: now)
        func queued() -> Int { log.lines.filter { $0.contains("queued") && $0.hasSuffix(" cues") && !$0.hasSuffix("voice cues") }.count }

        player.reconcile(.playing(try XCTUnwrap(skipped.cueSchedule)), at: now)
        if log.cuesAreSilent { throw XCTSkip("This simulator has no audio output: \(log.lines)") }
        XCTAssertEqual(queued(), 1)
        player.reconcile(.playing(try XCTUnwrap(skipped.cueSchedule)), at: now + 0.1)
        XCTAssertEqual(queued(), 1, "the same schedule is not queued again")
        player.reconcile(.playing(try XCTUnwrap(before.cueSchedule)), at: now + 0.2)
        XCTAssertEqual(queued(), 2, "a different schedule is queued, and that stops what the skip queued")
    }
}
