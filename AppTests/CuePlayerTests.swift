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
}
