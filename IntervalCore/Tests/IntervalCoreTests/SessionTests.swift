import Foundation
import IntervalCore
import Testing

struct SnapshotTests {
    @Test func atTheStart() throws {
        let p = try progress(session(), at: 0)
        #expect(describe(p.phase) == "warmUp")
        #expect(p.phaseRemaining == 300)
        #expect(p.phaseDuration == 300)
        #expect(p.totalRemaining == 2280)
        #expect(p.totalDuration == 2280)
        #expect(describe(p.upNext?.phase) == "work 1/4")
        #expect(!p.isPaused)
    }

    @Test func midPhase() throws {
        let p = try progress(session(), at: 420)
        #expect(describe(p.phase) == "work 1/4")
        #expect(p.phaseRemaining == 120)
        #expect(p.phaseDuration == 240)
        #expect(p.totalRemaining == 1860)
        #expect(describe(p.upNext?.phase) == "rest 1/4")
    }

    @Test func aBoundaryBelongsToTheNextPhase() throws {
        let before = try progress(session(), at: 299.5)
        #expect(describe(before.phase) == "warmUp")
        #expect(before.phaseRemaining == 0.5)

        let on = try progress(session(), at: 300)
        #expect(describe(on.phase) == "work 1/4")
        #expect(on.phaseRemaining == 240)
        #expect(on.totalRemaining == 1980)
    }

    @Test func theLastPhaseHasNothingUpNext() throws {
        let p = try progress(session(), at: 2279.5)
        #expect(describe(p.phase) == "coolDown")
        #expect(p.phaseRemaining == 0.5)
        #expect(p.totalRemaining == 0.5)
        #expect(p.upNext == nil)
    }

    @Test func finishedExactlyAtTheTotal() {
        #expect(session().snapshot(at: t0 + 2280) == .finished(worked: 2280))
    }

    @Test func finishedFarPastTheTotal() {
        #expect(session().snapshot(at: t0 + 2280 + 86_400) == .finished(worked: 2280))
    }

    @Test func aClockBeforeTheStartReadsAsTheStart() {
        #expect(session().snapshot(at: t0 - 30) == session().snapshot(at: t0))
    }

    @Test func exposesItsDefinition() {
        #expect(session(.hiit2020).definition == .hiit2020)
    }
}

struct PauseResumeTests {
    @Test func timeIsFrozenAcrossALongPause() throws {
        var run = session()
        run.pause(at: t0 + 360)

        let frozen = try progress(run, at: 3000)
        #expect(describe(frozen.phase) == "work 1/4")
        #expect(frozen.phaseRemaining == 180)
        #expect(frozen.totalRemaining == 1920)
        #expect(frozen.isPaused)

        run.resume(at: t0 + 4000)
        #expect(run.snapshot(at: t0 + 4010) == session().snapshot(at: t0 + 370))
    }

    @Test func aSecondPauseChangesNothing() throws {
        var run = session()
        run.pause(at: t0 + 360)
        let once = run
        run.pause(at: t0 + 500)
        #expect(run == once)
        #expect(try progress(run, at: 500).phaseRemaining == 180)
    }

    @Test func aSecondResumeChangesNothing() {
        var run = session()
        run.pause(at: t0 + 360)
        run.resume(at: t0 + 400)
        run.resume(at: t0 + 450)
        #expect(run.snapshot(at: t0 + 460) == session().snapshot(at: t0 + 420))
    }

    @Test func resumeWhileRunningChangesNothing() {
        var run = session()
        run.resume(at: t0 + 100)
        #expect(run == session())
    }

    @Test func pauseAfterTheFinishStaysFinished() {
        var run = session()
        run.pause(at: t0 + 3000)
        #expect(run.snapshot(at: t0 + 3000) == .finished(worked: 2280))
        #expect(run.snapshot(at: t0 + 9000) == .finished(worked: 2280))
    }

    @Test func aPausedRunHasNoCueSchedule() {
        var run = session()
        #expect(run.cueSchedule != nil)
        run.pause(at: t0 + 10)
        #expect(run.cueSchedule == nil)
        run.resume(at: t0 + 20)
        #expect(run.cueSchedule != nil)
    }
}

struct SkipTests {
    @Test func landsOnTheStartOfTheNextPhase() throws {
        var run = session()
        let before = try progress(run, at: 100)
        #expect(before.totalRemaining == 2180)

        run.skip(before.segment, at: t0 + 100)

        let after = try progress(run, at: 100)
        #expect(describe(after.phase) == "work 1/4")
        #expect(after.phaseRemaining == 240)
        #expect(after.totalRemaining == 1980)
        #expect(!after.isPaused)
        #expect(try progress(run, at: 110).phaseRemaining == 230)
    }

    @Test func aStaleSegmentIsIgnoredAfterANaturalPhaseChange() throws {
        var run = session()
        let warmUp = try progress(run, at: 299).segment
        run.skip(warmUp, at: t0 + 301)
        #expect(run == session())
    }

    @Test func aDoubleTapSkipsOnce() throws {
        var run = session()
        let warmUp = try progress(run, at: 100).segment
        run.skip(warmUp, at: t0 + 100)
        let once = run
        run.skip(warmUp, at: t0 + 100.2)
        #expect(run == once)
    }

    @Test func skippingWhilePausedStaysPaused() throws {
        var run = session()
        run.pause(at: t0 + 100)
        run.skip(try progress(run, at: 150).segment, at: t0 + 150)

        let held = try progress(run, at: 900)
        #expect(describe(held.phase) == "work 1/4")
        #expect(held.phaseRemaining == 240)
        #expect(held.totalRemaining == 1980)
        #expect(held.isPaused)
        #expect(run.cueSchedule == nil)

        run.resume(at: t0 + 1000)
        #expect(try progress(run, at: 1010).phaseRemaining == 230)
    }

    @Test func skippingTheLastPhaseFinishes() throws {
        var run = session()
        let coolDown = try progress(run, at: 2000)
        #expect(describe(coolDown.phase) == "coolDown")
        run.skip(coolDown.segment, at: t0 + 2000)
        #expect(run.snapshot(at: t0 + 2000) == .finished(worked: 2000))
    }

    @Test func aFinishedRunReportsTheTimeThatWasNotSkipped() throws {
        var run = session()
        run.skip(try progress(run, at: 60).segment, at: t0 + 60)
        run.pause(at: t0 + 100)
        run.resume(at: t0 + 700)
        let work = try progress(run, at: 700)
        #expect(describe(work.phase) == "work 1/4")
        #expect(work.phaseRemaining == 200)
        run.skip(work.segment, at: t0 + 700)
        #expect(run.snapshot(at: t0 + 10_000) == .finished(worked: 2280 - 240 - 200))
    }

    @Test func upNextCarriesTheLengthOfTheNextPhase() throws {
        #expect(try progress(session(), at: 0).upNext?.duration == 240)
        #expect(try progress(session(), at: 300).upNext?.duration == 180)
    }

    @Test func skippingEveryPhaseVisitsThemInOrder() throws {
        var run = session(.audioCheck)
        var visited: [String] = []
        while case .active(let p) = run.snapshot(at: t0 + 5), visited.count < 10 {
            visited.append(describe(p.phase))
            run.skip(p.segment, at: t0 + 5)
        }
        #expect(visited == ["warmUp", "work 1/2", "rest 1/2", "work 2/2"])
    }
}

struct ClockTextTests {
    @Test(arguments: [
        (240, "4:00"),
        (0.01, "0:01"),
        (59.2, "1:00"),
        (3600, "1:00:00"),
        (0, "0:00"),
        (9, "0:09"),
        (2280, "38:00"),
        (3599.5, "1:00:00"),
        (3661, "1:01:01"),
        (86_400, "24:00:00"),
    ] as [(TimeInterval, String)])
    func remaining(_ interval: TimeInterval, reads text: String) {
        #expect(ClockText.remaining(interval) == text)
    }
}
