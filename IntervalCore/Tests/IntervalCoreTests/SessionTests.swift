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

    @Test func exposesItsWorkout() {
        #expect(session(.hiit2020).workout == .hiit2020)
        #expect(session(.dailyStretch).workout == .dailyStretch)
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

    @Test func theZeroDateFollowsPauseResumeAndSkip() throws {
        var run = session()
        #expect(run.zeroDate == t0)
        run.pause(at: t0 + 60)
        #expect(run.zeroDate == nil)
        run.resume(at: t0 + 100)
        #expect(run.zeroDate == t0 + 40)
        run.skip(try progress(run, at: 100).segment, at: t0 + 100.5)
        #expect(run.zeroDate == t0 + 100.5 - 300)
        #expect(try progress(run, at: 101.5).phaseRemaining == 239)
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

struct ElapsedTests {
    @Test func elapsedAndRemainingAddUpToTheTotal() throws {
        for (workout, total) in [(Workout.norwegian4x4, 2280.0), (.hiit2020, 840)] {
            for offset in [0, 100.25, 420, 644.5] {
                let p = try progress(session(workout), at: offset)
                #expect(p.elapsed == offset)
                #expect(p.elapsed + p.totalRemaining == total)
                #expect(p.totalDuration == total)
                #expect(p.phaseElapsed + p.phaseRemaining == p.phaseDuration)
            }
        }
    }

    @Test func phaseElapsedCountsFromTheStartOfThePhase() throws {
        let p = try progress(session(), at: 420)
        #expect(p.phaseElapsed == 120)
        #expect(p.phaseRemaining == 120)
        #expect(p.elapsed == 420)
    }

    @Test func elapsedIgnoresPausedTimeAndJumpsWithASkip() throws {
        var run = session()
        run.pause(at: t0 + 360)
        #expect(try progress(run, at: 3000).elapsed == 360)
        run.resume(at: t0 + 4000)
        #expect(try progress(run, at: 4010).elapsed == 370)

        run.skip(try progress(run, at: 4010).segment, at: t0 + 4010)
        let skipped = try progress(run, at: 4010)
        #expect(skipped.elapsed == 540)
        #expect(skipped.phaseElapsed == 0)
    }

    @Test func isPausedFollowsPauseAndResume() {
        var run = session()
        #expect(!run.isPaused)
        run.pause(at: t0 + 10)
        #expect(run.isPaused)
        run.resume(at: t0 + 20)
        #expect(!run.isPaused)
    }
}

struct WaitingTests {
    private func squatThenCobra() throws -> Workout {
        try routine(getReady: 10, [try stretch("Squat", try reps(5)), try stretch("Cobra", try hold(20))])
    }

    private func cobraThenPigeon() throws -> Workout {
        try routine(getReady: 10, [try stretch("Cobra", try hold(20)), try stretch("Pigeon", try hold(30))])
    }

    @Test func aRepStretchWaitsFromTheMomentItStarts() throws {
        let run = session(.dailyStretch)
        let gettingReady = try progress(run, at: 7.5)
        #expect(describe(gettingReady.phase) == "getReady Cat-Cow 1/10")
        #expect(!gettingReady.isWaiting)
        #expect(gettingReady.reps == nil)

        let reps = try progress(run, at: 8)
        #expect(describe(reps.phase) == "hold Cat-Cow 1/10")
        #expect(reps.isWaiting)
        #expect(reps.reps?.value == 10)
        #expect(reps.phaseElapsed == 0)
        #expect(reps.phaseRemaining == 0)
        #expect(reps.phaseDuration == 0)
        #expect(reps.elapsed == 8)
        #expect(reps.totalRemaining == 587)
        #expect(reps.totalDuration == 595)
        #expect(describe(reps.upNext?.phase) == "hold Child's Pose 2/10")
        #expect(!reps.isPaused)
    }

    @Test func aTimedHoldCountsDownAndThenWaits() throws {
        let run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        let counting = try progress(run, at: 44.5)
        #expect(!counting.isWaiting)
        #expect(counting.phaseRemaining == 0.5)

        let done = try progress(run, at: 45)
        #expect(describe(done.phase) == "hold Child's Pose 2/10")
        #expect(done.isWaiting)
        #expect(done.reps == nil)
        #expect(done.phaseElapsed == 45)
        #expect(done.phaseRemaining == 0)
        #expect(done.phaseDuration == 45)
        #expect(done.elapsed == 61)
        #expect(done.totalRemaining == 534)
        #expect(describe(done.upNext?.phase) == "hold Cobra 3/10")
    }

    @Test(arguments: [9.0, 60, 3600, 2_592_000])
    func timeStandsStillHoweverLongTheWait(_ late: TimeInterval) throws {
        let reps = session(.dailyStretch)
        #expect(reps.snapshot(at: t0 + 8 + late) == reps.snapshot(at: t0 + 8))

        let timed = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        #expect(timed.snapshot(at: t0 + 45 + late) == timed.snapshot(at: t0 + 45))
    }

    @Test func nextStartsTheNextGetReadyAtThePressAndItsHoldFollowsByItself() throws {
        var run = session(.dailyStretch)
        run.perform(.next, at: t0 + 100)

        let gettingReady = try progress(run, at: 100)
        #expect(describe(gettingReady.phase) == "getReady Child's Pose 2/10")
        #expect(!gettingReady.isWaiting)
        #expect(gettingReady.phaseRemaining == 8)
        #expect(gettingReady.elapsed == 8)
        #expect(try progress(run, at: 104).phaseRemaining == 4)

        let hold = try progress(run, at: 108)
        #expect(describe(hold.phase) == "hold Child's Pose 2/10")
        #expect(!hold.isWaiting)
        #expect(hold.phaseRemaining == 45)
        #expect(try progress(run, at: 153).isWaiting)
    }

    @Test func skippingTheSegmentTheRunWaitsInMovesOnOnce() throws {
        var run = session(.dailyStretch)
        let waiting = try progress(run, at: 30).segment
        run.skip(waiting, at: t0 + 30)
        #expect(describe(try progress(run, at: 30).phase) == "getReady Child's Pose 2/10")

        let once = run
        run.skip(waiting, at: t0 + 30.2)
        #expect(run == once)
    }

    @Test func nextDuringACountingHoldEndsItWithoutAWait() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.perform(.next, at: t0 + 20)

        let next = try progress(run, at: 20)
        #expect(describe(next.phase) == "getReady Cobra 3/10")
        #expect(next.phaseRemaining == 8)
        #expect(!next.isWaiting)
        #expect(describe(try progress(run, at: 28).phase) == "hold Cobra 3/10")
    }

    @Test func nextInAGapStartsTheHoldAndTheHoldStillWaits() throws {
        var run = try session(.dailyStretch, in: "getReady Child's Pose 2/10")
        run.perform(.next, at: t0 + 3)
        #expect(describe(try progress(run, at: 3).phase) == "hold Child's Pose 2/10")
        #expect(!(try progress(run, at: 47.5).isWaiting))
        let done = try progress(run, at: 5000)
        #expect(describe(done.phase) == "hold Child's Pose 2/10")
        #expect(done.isWaiting)
    }

    @Test func aStretchOnEachSideWaitsAfterTheLeftAndAfterTheRight() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        let left = try progress(run, at: 500)
        #expect(describe(left.phase) == "hold Pigeon left 5/10")
        #expect(left.isWaiting)

        run.perform(.next, at: t0 + 500)
        let switching = try progress(run, at: 502)
        #expect(describe(switching.phase) == "switchSides to Pigeon right 5/10")
        #expect(switching.phaseRemaining == 3)
        let right = try progress(run, at: 505)
        #expect(describe(right.phase) == "hold Pigeon right 5/10")
        #expect(right.phaseRemaining == 45)

        let rightDone = try progress(run, at: 9000)
        #expect(describe(rightDone.phase) == "hold Pigeon right 5/10")
        #expect(rightDone.isWaiting)

        run.perform(.next, at: t0 + 9000)
        #expect(describe(try progress(run, at: 9000).phase) == "getReady Butterfly 6/10")
    }

    @Test func theLastTimedHoldFinishesByItself() throws {
        let run = try session(.dailyStretch, in: "hold Passive Dead Hang 10/10")
        let last = try progress(run, at: 29.5)
        #expect(!last.isWaiting)
        #expect(last.phaseRemaining == 0.5)
        #expect(last.upNext == nil)
        guard case .finished = run.snapshot(at: t0 + 30) else {
            Issue.record("the last hold waited instead of finishing")
            return
        }
    }

    @Test func aRepStretchInLastPlaceFinishesOnNext() throws {
        var run = session(try routine(getReady: 10, [try stretch("Squat", try reps(5))]))
        let waiting = try progress(run, at: 5000)
        #expect(describe(waiting.phase) == "hold Squat 1/1")
        #expect(waiting.isWaiting)
        #expect(waiting.upNext == nil)
        #expect(waiting.totalRemaining == 0)

        run.perform(.next, at: t0 + 50)
        #expect(run.snapshot(at: t0 + 50) == .finished(worked: 50))
    }

    @Test func pausingAndResumingKeepsTheWait() throws {
        var run = session(.dailyStretch)
        run.pause(at: t0 + 20)
        let paused = try progress(run, at: 500)
        #expect(describe(paused.phase) == "hold Cat-Cow 1/10")
        #expect(paused.isPaused)
        #expect(paused.isWaiting)
        #expect(paused.elapsed == 8)
        #expect(run.cueSchedule == nil)
        #expect(run.haltDate == nil)

        run.resume(at: t0 + 600)
        let resumed = try progress(run, at: 700)
        #expect(describe(resumed.phase) == "hold Cat-Cow 1/10")
        #expect(!resumed.isPaused)
        #expect(resumed.isWaiting)
        #expect(try #require(run.cueSchedule).remaining(after: t0 + 600).isEmpty, "the tone that began the wait is not played again")

        run.perform(.next, at: t0 + 700)
        #expect(describe(try progress(run, at: 700).phase) == "getReady Child's Pose 2/10")
        #expect(try progress(run, at: 700).phaseRemaining == 8)
    }

    @Test func aTogglePausesAWaitAndTheNextOneResumesIt() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.perform(.togglePlayPause, at: t0 + 60)
        #expect(try progress(run, at: 70).isPaused)
        run.perform(.togglePlayPause, at: t0 + 80)
        let resumed = try progress(run, at: 90)
        #expect(!resumed.isPaused)
        #expect(resumed.isWaiting)
        #expect(describe(resumed.phase) == "hold Child's Pose 2/10")
    }

    @Test func nextWhilePausedInAWaitMovesOnAndStaysPaused() throws {
        var run = session(.dailyStretch)
        run.pause(at: t0 + 20)
        run.perform(.next, at: t0 + 30)
        let held = try progress(run, at: 900)
        #expect(describe(held.phase) == "getReady Child's Pose 2/10")
        #expect(held.phaseRemaining == 8)
        #expect(held.isPaused)
        #expect(!held.isWaiting)
    }

    @Test func restartingARepStretchGoesBackToItsGetReadyGapAndWaitsAgain() throws {
        var run = session(.dailyStretch)
        run.perform(.previous, at: t0 + 30)

        let gettingReady = try progress(run, at: 30)
        #expect(describe(gettingReady.phase) == "getReady Cat-Cow 1/10")
        #expect(gettingReady.elapsed == 0)
        #expect(gettingReady.phaseRemaining == 8)
        #expect(!gettingReady.isWaiting)

        let again = try progress(run, at: 38)
        #expect(describe(again.phase) == "hold Cat-Cow 1/10")
        #expect(again.isWaiting)
    }

    @Test func restartingAFinishedHoldRunsItAgainAndWaitsAgain() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.perform(.previous, at: t0 + 300)

        let gettingReady = try progress(run, at: 300)
        #expect(describe(gettingReady.phase) == "getReady Child's Pose 2/10")
        #expect(gettingReady.phaseRemaining == 8)

        let hold = try progress(run, at: 308)
        #expect(describe(hold.phase) == "hold Child's Pose 2/10")
        #expect(hold.phaseRemaining == 45)
        #expect(!hold.isWaiting)
        #expect(try progress(run, at: 353).isWaiting)
    }

    @Test func theHaltDateIsTheNextGateOrTheFinish() throws {
        var run = session(.dailyStretch)
        #expect(run.haltDate == t0 + 8)
        run.perform(.next, at: t0 + 100)
        #expect(run.haltDate == t0 + 100 + 8 + 45)
        #expect(run.zeroDate == t0 + 100 - 8)

        let last = try session(.dailyStretch, in: "hold Passive Dead Hang 10/10")
        #expect(last.haltDate == t0 + 30)
        #expect(session().haltDate == t0 + 2280)
    }

    @Test func timeInARepStretchCountsAsWorked() throws {
        var run = session(try squatThenCobra())
        run.perform(.next, at: t0 + 70)
        #expect(try progress(run, at: 99.5).totalRemaining == 0.5)
        #expect(run.snapshot(at: t0 + 100) == .finished(worked: 40 + 60))
    }

    @Test func aWaitAfterATimedHoldDoesNotCountAsWorked() throws {
        var run = session(try cobraThenPigeon())
        #expect(try progress(run, at: 500).isWaiting)
        run.perform(.next, at: t0 + 500)
        #expect(run.snapshot(at: t0 + 540) == .finished(worked: 70))
    }

    @Test func pausedTimeInARepStretchDoesNotCountAsWorked() throws {
        var run = session(try squatThenCobra())
        run.pause(at: t0 + 30)
        run.resume(at: t0 + 1000)
        run.perform(.next, at: t0 + 1010)
        #expect(run.snapshot(at: t0 + 1040) == .finished(worked: 40 + 20 + 10))
    }

    @Test func endingAHoldEarlyTakesOffTheRestOfIt() throws {
        var run = session(try cobraThenPigeon())
        run.perform(.next, at: t0 + 15)
        #expect(run.snapshot(at: t0 + 55) == .finished(worked: 70 - 15))
    }

    @Test func restartedTimeCountsAgainIncludingTheRepsAlreadyDone() throws {
        var run = session(try squatThenCobra())
        run.perform(.previous, at: t0 + 25)
        #expect(try progress(run, at: 35).isWaiting)
        run.perform(.next, at: t0 + 40)
        #expect(run.snapshot(at: t0 + 70) == .finished(worked: 40 + 10 + 15 + 5))
    }

    @Test func aRoutineDoneWithoutLingeringWorksItsTimedLength() throws {
        var run = session(.dailyStretch)
        for _ in 0..<13 {
            let halt = try #require(run.haltDate)
            run.perform(.next, at: halt)
        }
        #expect(run.snapshot(at: t0 + 595) == .finished(worked: 595))
        #expect(try progress(run, at: 594.5).totalRemaining == 0.5)
    }
}

struct UpNextTests {
    @Test(arguments: [
        ("getReady Cat-Cow 1/10", "hold Cat-Cow 1/10", 0.0),
        ("hold Cat-Cow 1/10", "hold Child's Pose 2/10", 45),
        ("getReady Pigeon left 5/10", "hold Pigeon left 5/10", 45),
        ("hold Pigeon left 5/10", "hold Pigeon right 5/10", 45),
        ("switchSides to Pigeon right 5/10", "hold Pigeon right 5/10", 45),
        ("hold Pigeon right 5/10", "hold Butterfly 6/10", 45),
        ("getReady Passive Dead Hang 10/10", "hold Passive Dead Hang 10/10", 30),
    ])
    func upNextLooksPastTheGaps(from phase: String, to next: String, duration: TimeInterval) throws {
        let upNext = try progress(try session(.dailyStretch, in: phase), at: 2).upNext
        #expect(describe(upNext?.phase) == next)
        #expect(upNext?.duration == duration)
    }

    @Test func upNextCarriesTheRepCountOfAStretchCountedInReps() throws {
        let upNext = try #require(try progress(session(.dailyStretch), at: 2).upNext)
        #expect(upNext.phase.reps?.value == 10)
        #expect(upNext.duration == 0)
    }

    @Test func upNextReadsAsTheStretchAndItsSide() throws {
        let upNext = try #require(try progress(try session(.dailyStretch, in: "hold Pigeon left 5/10"), at: 20).upNext)
        #expect(upNext.phase.title == "Pigeon")
        #expect(upNext.phase.caption == "Right side · Stretch 5 of 10")
    }

    @Test func theOtherSideOfTheSameStretchIsNamedByItsSide() throws {
        let leftHold = try progress(try session(.dailyStretch, in: "hold Pigeon left 5/10"), at: 20)
        let rightHold = try #require(leftHold.upNext).phase
        #expect(rightHold.title(following: leftHold.phase) == "Right side")

        let lastSide = try progress(try session(.dailyStretch, in: "hold Pigeon right 5/10"), at: 20)
        #expect(lastSide.phase.caption == "Right side · Stretch 5 of 10")
        #expect(try #require(lastSide.upNext).phase.title(following: lastSide.phase) == "Butterfly")

        let intervals = try progress(session(), at: 0)
        #expect(try #require(intervals.upNext).phase.title(following: intervals.phase) == "Work")
    }

    @Test func nothingIsUpNextInTheLastHold() throws {
        let p = try progress(try session(.dailyStretch, in: "hold Passive Dead Hang 10/10"), at: 5)
        #expect(describe(p.phase) == "hold Passive Dead Hang 10/10")
        #expect(p.upNext == nil)
    }
}

struct RestartTests {
    @Test func aHoldGoesBackToItsGetReadyGap() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        let hold = try progress(run, at: 20)
        #expect(describe(hold.phase) == "hold Pigeon left 5/10")
        #expect(hold.phaseRemaining == 25)

        run.restart(hold.segment, at: t0 + 20)

        let after = try progress(run, at: 20)
        #expect(describe(after.phase) == "getReady Pigeon left 5/10")
        #expect(after.phaseElapsed == 0)
        #expect(after.phaseRemaining == 8)
        #expect(after.elapsed == 202)
        #expect(after.totalRemaining == 393)
        #expect(!after.isPaused)
        #expect(run.zeroDate == t0 + 20 - 202)

        let back = try progress(run, at: 28)
        #expect(describe(back.phase) == "hold Pigeon left 5/10")
        #expect(back.phaseRemaining == 45)
    }

    @Test func theSecondSideGoesBackToSwitchSides() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon right 5/10")
        run.restart(try progress(run, at: 10).segment, at: t0 + 10)

        let after = try progress(run, at: 10)
        #expect(describe(after.phase) == "switchSides to Pigeon right 5/10")
        #expect(after.phaseRemaining == 5)
        #expect(after.elapsed == 255)
    }

    @Test(arguments: [("getReady Pigeon left 5/10", 202.0), ("switchSides to Pigeon right 5/10", 255)])
    func aGapGoesBackToItsOwnStart(_ phase: String, start: TimeInterval) throws {
        var run = try session(.dailyStretch, in: phase)
        run.restart(try progress(run, at: 2).segment, at: t0 + 2)
        let after = try progress(run, at: 2)
        #expect(describe(after.phase) == phase)
        #expect(after.elapsed == start)
        #expect(after.phaseElapsed == 0)
    }

    @Test(arguments: [(100.0, "warmUp", 0.0), (420, "work 1/4", 300), (600, "rest 1/4", 540), (2000, "coolDown", 1980)])
    func anIntervalPhaseGoesBackToItsOwnStart(at offset: TimeInterval, phase: String, start: TimeInterval) throws {
        var run = session()
        run.restart(try progress(run, at: offset).segment, at: t0 + offset)
        let after = try progress(run, at: offset)
        #expect(describe(after.phase) == phase)
        #expect(after.elapsed == start)
        #expect(after.phaseElapsed == 0)
    }

    @Test func aSecondRestartOfTheSameSegmentChangesNothing() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        let hold = try progress(run, at: 20).segment
        run.restart(hold, at: t0 + 20)
        let once = run
        run.restart(hold, at: t0 + 20.2)
        #expect(run == once)
    }

    @Test func aStaleSegmentIsIgnoredAfterANaturalPhaseChange() throws {
        let fresh = try session(.dailyStretch, in: "getReady Pigeon left 5/10")
        var run = fresh
        let getReady = try progress(run, at: 7).segment
        run.restart(getReady, at: t0 + 9)
        #expect(run == fresh)
    }

    @Test func restartingWhilePausedStaysPaused() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        run.pause(at: t0 + 20)
        run.restart(try progress(run, at: 40).segment, at: t0 + 40)

        let held = try progress(run, at: 900)
        #expect(describe(held.phase) == "getReady Pigeon left 5/10")
        #expect(held.phaseRemaining == 8)
        #expect(held.isPaused)
        #expect(run.cueSchedule == nil)

        run.resume(at: t0 + 1000)
        #expect(try progress(run, at: 1004).phaseRemaining == 4)
    }

    @Test func theStretchIsNamedAgainAtOnce() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        let now = t0 + 20
        run.restart(try progress(run, at: 20).segment, at: now)

        let todo = try #require(run.cueSchedule).remaining(after: now)
        let first = try #require(todo.windows.first)
        #expect(bounds(first) == [20_000, 22_200])
        #expect(cues(first) == [Cue(20_000, .phaseChange), Cue(20_500, voice("Pigeon, left side"))])
    }

    @Test func aFinishedIntervalRunCountsRestartedTimeAgain() throws {
        var run = session(.audioCheck)
        run.restart(try progress(run, at: 45).segment, at: t0 + 45)
        #expect(try progress(run, at: 64.5).totalRemaining == 0.5)
        #expect(run.snapshot(at: t0 + 65) == .finished(worked: 60 + 5))
    }

    @Test func restartingAFinishedRunDoesNothing() throws {
        var run = session(.audioCheck)
        let last = try progress(run, at: 55).segment
        run.restart(last, at: t0 + 60)
        #expect(run == session(.audioCheck))
        #expect(run.snapshot(at: t0 + 60) == .finished(worked: 60))
    }
}

struct CommandTests {
    @Test func pausePauses() throws {
        var run = session()
        run.perform(.pause, at: t0 + 100)
        #expect(run.isPaused)
        let held = try progress(run, at: 500)
        #expect(held.isPaused)
        #expect(held.phaseRemaining == 200)

        let once = run
        run.perform(.pause, at: t0 + 200)
        #expect(run == once)
    }

    @Test func playResumes() throws {
        var run = session()
        run.perform(.pause, at: t0 + 100)
        run.perform(.play, at: t0 + 400)
        let p = try progress(run, at: 410)
        #expect(!p.isPaused)
        #expect(p.phaseRemaining == 190)
    }

    @Test func playWhileRunningChangesNothing() {
        var run = session()
        run.perform(.play, at: t0 + 100)
        #expect(run == session())
    }

    @Test func togglePausesThenResumes() throws {
        var run = session()
        run.perform(.togglePlayPause, at: t0 + 100)
        #expect(try progress(run, at: 300).isPaused)
        #expect(try progress(run, at: 300).phaseRemaining == 200)

        run.perform(.togglePlayPause, at: t0 + 400)
        let p = try progress(run, at: 410)
        #expect(!p.isPaused)
        #expect(p.phaseRemaining == 190)
    }

    @Test func nextSkipsThePhaseInProgress() throws {
        var run = session()
        run.perform(.next, at: t0 + 100)
        let p = try progress(run, at: 100)
        #expect(describe(p.phase) == "work 1/4")
        #expect(p.phaseRemaining == 240)
        #expect(p.totalRemaining == 1980)
    }

    @Test func nextInAGapStartsTheHold() throws {
        var run = try session(.dailyStretch, in: "getReady Pigeon left 5/10")
        run.perform(.next, at: t0 + 3)
        let p = try progress(run, at: 3)
        #expect(describe(p.phase) == "hold Pigeon left 5/10")
        #expect(p.phaseRemaining == 45)
    }

    @Test func nextWhilePausedStaysPaused() throws {
        var run = session()
        run.perform(.pause, at: t0 + 100)
        run.perform(.next, at: t0 + 150)
        let p = try progress(run, at: 900)
        #expect(describe(p.phase) == "work 1/4")
        #expect(p.phaseRemaining == 240)
        #expect(p.isPaused)
    }

    @Test func nextOnTheLastPhaseFinishes() {
        var run = session(.audioCheck)
        run.perform(.next, at: t0 + 55)
        #expect(run.snapshot(at: t0 + 55) == .finished(worked: 55))
    }

    @Test func previousRestartsTheStretchFromItsGetReadyGap() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        run.perform(.previous, at: t0 + 20)
        let p = try progress(run, at: 20)
        #expect(describe(p.phase) == "getReady Pigeon left 5/10")
        #expect(p.elapsed == 202)
    }

    @Test func previousRestartsAnIntervalPhase() throws {
        var run = session()
        run.perform(.previous, at: t0 + 420)
        let p = try progress(run, at: 420)
        #expect(describe(p.phase) == "work 1/4")
        #expect(p.phaseRemaining == 240)
    }

    @Test func aPressDeliveredTwiceAtTheSameInstantRestartsOnce() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        run.perform(.previous, at: t0 + 20)
        let once = run
        run.perform(.previous, at: t0 + 20)
        #expect(run == once)
    }

    @Test(arguments: [RunCommand.play, .pause, .togglePlayPause, .next, .previous])
    func aFinishedRunIgnoresEveryCommand(_ command: RunCommand) {
        var run = session(.audioCheck)
        run.perform(command, at: t0 + 60)
        #expect(run == session(.audioCheck))
        run.perform(command, at: t0 + 5000)
        #expect(run == session(.audioCheck))
        #expect(run.snapshot(at: t0 + 5000) == .finished(worked: 60))
    }

    @Test(arguments: [RunCommand.play, .pause, .togglePlayPause, .next, .previous])
    func aRunFinishedBySkippingIgnoresEveryCommand(_ command: RunCommand) throws {
        var run = session(.audioCheck)
        run.pause(at: t0 + 55)
        run.skip(try progress(run, at: 55).segment, at: t0 + 56)
        let finished = run
        run.perform(command, at: t0 + 57)
        #expect(run == finished)
        #expect(run.snapshot(at: t0 + 57) == .finished(worked: 55))
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
