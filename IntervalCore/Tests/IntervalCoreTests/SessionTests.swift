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
    /// Squat waits for Next at 0. Cobra waits for Start at 0, counts in until 3 and holds until 23.
    private func squatThenCobra() throws -> Workout {
        try routine([try stretch("Squat", try reps(5)), try stretch("Cobra", try hold(20))])
    }

    /// Cobra counts in until 3 and holds until 23. Pigeon counts in until 26 and holds until 56.
    private func cobraThenPigeon() throws -> Workout {
        try routine([try stretch("Cobra", try hold(20)), try stretch("Pigeon", try hold(30))])
    }

    @Test func aRepStretchWaitsFromTheMomentTheRunStarts() throws {
        let reps = try progress(session(.dailyStretch), at: 0)
        #expect(describe(reps.phase) == "hold Cat-Cow 1/10")
        #expect(reps.isWaiting)
        #expect(reps.reps?.value == 10)
        #expect(reps.phaseElapsed == 0)
        #expect(reps.phaseRemaining == 0)
        #expect(reps.phaseDuration == 0)
        #expect(reps.elapsed == 0)
        #expect(reps.totalRemaining == 501)
        #expect(reps.totalDuration == 501)
        #expect(describe(reps.upNext?.phase) == "hold Child's Pose 2/10")
        #expect(!reps.isPaused)
    }

    @Test func aTimedStretchWaitsForStartAndShowsTheLengthOfItsHold() throws {
        let waiting = try progress(try session(.dailyStretch, in: "ready Child's Pose 2/10"), at: 0)
        #expect(waiting.isWaiting)
        #expect(waiting.reps == nil)
        #expect(waiting.phase.title == "Child's Pose")
        #expect(waiting.phase.caption == "Stretch 2 of 10")
        #expect(waiting.phase.pendingHold == 45)
        #expect(waiting.phase.advanceTitle == "Start")
        #expect(waiting.phaseRemaining == 0)
        #expect(waiting.phaseDuration == 0)
        #expect(waiting.elapsed == 0)
        #expect(waiting.totalRemaining == 501)
        #expect(describe(waiting.upNext?.phase) == "hold Cobra 3/10")
    }

    @Test(arguments: [1.0, 60, 3600, 2_592_000])
    func timeStandsStillHoweverLongTheWait(_ late: TimeInterval) throws {
        let waits = [
            "hold Cat-Cow 1/10", "ready Child's Pose 2/10", "ready Pigeon right 5/10", "ready Passive Dead Hang 10/10",
        ]
        for phase in waits {
            let run = try session(.dailyStretch, in: phase)
            #expect(try progress(run, at: late).isWaiting, "\(phase)")
            #expect(run.snapshot(at: t0 + late) == run.snapshot(at: t0), "\(phase)")
        }
    }

    @Test func startBeginsTheCountInAtThePressAndTheHoldFollowsByItself() throws {
        var run = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        run.perform(.play, at: t0 + 100)

        let countIn = try progress(run, at: 100)
        #expect(describe(countIn.phase) == "getReady Child's Pose 2/10")
        #expect(!countIn.isWaiting)
        #expect(countIn.phaseRemaining == 3)
        #expect(countIn.phaseDuration == 3)
        #expect(countIn.elapsed == 0)
        #expect(try progress(run, at: 102).phaseRemaining == 1)

        let hold = try progress(run, at: 103)
        #expect(describe(hold.phase) == "hold Child's Pose 2/10")
        #expect(!hold.isWaiting)
        #expect(hold.phaseRemaining == 45)
        #expect(try progress(run, at: 147.5).phaseRemaining == 0.5)
    }

    @Test func withNoCountInStartGoesStraightIntoTheHold() throws {
        var run = session(try routine(countIn: nil, [try stretch("Cobra", try hold(20)), try stretch("Pigeon", try hold(30))]))
        #expect(describe(try progress(run, at: 50).phase) == "ready Cobra 1/2")
        run.perform(.play, at: t0 + 50)

        let hold = try progress(run, at: 50)
        #expect(describe(hold.phase) == "hold Cobra 1/2")
        #expect(hold.phaseRemaining == 20)
        #expect(describe(try progress(run, at: 70).phase) == "ready Pigeon 2/2")
    }

    @Test func aHoldEndsByItselfAndTheRunWaitsAtTheNextStretch() throws {
        let run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        #expect(try progress(run, at: 44.5).phaseRemaining == 0.5)

        let next = try progress(run, at: 45)
        #expect(describe(next.phase) == "ready Cobra 3/10")
        #expect(next.isWaiting)
        #expect(next.phase.pendingHold == 30)
        #expect(next.elapsed == 48)
        #expect(next.totalRemaining == 453)
        #expect(run.snapshot(at: t0 + 9000) == .active(next))
    }

    @Test func skippingTheSegmentTheRunWaitsInMovesOnOnce() throws {
        var run = session(.dailyStretch)
        let waiting = try progress(run, at: 30).segment
        run.skip(waiting, at: t0 + 30)
        #expect(describe(try progress(run, at: 30).phase) == "ready Child's Pose 2/10")

        let once = run
        run.skip(waiting, at: t0 + 30.2)
        #expect(run == once)
    }

    @Test func nextDuringAHoldEndsItAndTheRunWaitsAtTheNextStretch() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.perform(.next, at: t0 + 20)

        let next = try progress(run, at: 20)
        #expect(describe(next.phase) == "ready Cobra 3/10")
        #expect(next.isWaiting)
        #expect(next.elapsed == 48)
        #expect(run.snapshot(at: t0 + 5000) == .active(next))
    }

    @Test func nextDuringACountInLeavesTheStretchAndTheRunWaitsAtTheNextOne() throws {
        var run = try session(.dailyStretch, in: "getReady Child's Pose 2/10")
        run.perform(.next, at: t0 + 1)

        let next = try progress(run, at: 1)
        #expect(describe(next.phase) == "ready Cobra 3/10")
        #expect(next.isWaiting)
        #expect(next.elapsed == 48)
    }

    @Test func eachSideOfAStretchWaitsForItsOwnStart() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        let right = try progress(run, at: 500)
        #expect(describe(right.phase) == "ready Pigeon right 5/10")
        #expect(right.isWaiting)
        #expect(right.phase.caption == "Right side · Stretch 5 of 10")
        #expect(right.phase.pendingHold == 45)

        run.perform(.play, at: t0 + 500)
        #expect(describe(try progress(run, at: 502).phase) == "getReady Pigeon right 5/10")
        let hold = try progress(run, at: 503)
        #expect(describe(hold.phase) == "hold Pigeon right 5/10")
        #expect(hold.phaseRemaining == 45)
        #expect(describe(try progress(run, at: 548).phase) == "ready Butterfly 6/10")
    }

    @Test func theLastTimedHoldFinishesTheWorkoutByItself() throws {
        var run = session(try cobraThenPigeon())
        run.perform(.play, at: t0)
        #expect(describe(try progress(run, at: 100).phase) == "ready Pigeon 2/2")
        run.perform(.play, at: t0 + 100)

        let last = try progress(run, at: 132.5)
        #expect(describe(last.phase) == "hold Pigeon 2/2")
        #expect(last.phaseRemaining == 0.5)
        #expect(last.upNext == nil)
        #expect(run.haltDate == t0 + 133)
        #expect(run.snapshot(at: t0 + 133) == .finished(worked: 56), "the 77 s spent waiting for Start is not work")
        #expect(run.snapshot(at: t0 + 90_000) == .finished(worked: 56))
        #expect(cues(try #require(run.cueSchedule)).suffix(2) == [
            Cue(133_000, .finish), Cue(134_000, voice("Workout complete")),
        ])
    }

    @Test func theRightSideInLastPlaceFinishesTheWorkoutByItself() throws {
        var run = session(try routine([try stretch("Pigeon", try hold(20), .each)]))
        run.perform(.play, at: t0)
        #expect(describe(try progress(run, at: 500).phase) == "ready Pigeon right 1/1")
        run.perform(.play, at: t0 + 500)

        #expect(try progress(run, at: 522.5).phaseRemaining == 0.5)
        #expect(run.snapshot(at: t0 + 523) == .finished(worked: 46))
    }

    @Test func aRepStretchInLastPlaceFinishesOnNext() throws {
        var run = session(try routine([try stretch("Squat", try reps(5))]))
        let waiting = try progress(run, at: 5000)
        #expect(describe(waiting.phase) == "hold Squat 1/1")
        #expect(waiting.isWaiting)
        #expect(waiting.upNext == nil)
        #expect(waiting.totalRemaining == 0)

        run.perform(.next, at: t0 + 50)
        #expect(run.snapshot(at: t0 + 50) == .finished(worked: 50))
    }

    @Test func aRepStretchAfterATimedHoldWaitsForNextAndFinishesOnIt() throws {
        var run = session(try routine([try stretch("Cobra", try hold(20)), try stretch("Squat", try reps(5))]))
        run.perform(.play, at: t0)

        let reps = try progress(run, at: 23)
        #expect(describe(reps.phase) == "hold Squat 2/2")
        #expect(reps.isWaiting)
        #expect(reps.reps?.value == 5)
        #expect(run.snapshot(at: t0 + 9000) == .active(reps))

        run.perform(.next, at: t0 + 60)
        #expect(run.snapshot(at: t0 + 60) == .finished(worked: 23 + 37))
    }

    @Test func pausingAndResumingKeepsTheWait() throws {
        var run = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        run.pause(at: t0 + 20)
        let paused = try progress(run, at: 500)
        #expect(describe(paused.phase) == "ready Child's Pose 2/10")
        #expect(paused.isPaused)
        #expect(paused.isWaiting)
        #expect(paused.elapsed == 0)
        #expect(run.cueSchedule == nil)
        #expect(run.haltDate == nil)

        run.resume(at: t0 + 600)
        let resumed = try progress(run, at: 700)
        #expect(describe(resumed.phase) == "ready Child's Pose 2/10")
        #expect(!resumed.isPaused)
        #expect(resumed.isWaiting)
        #expect(try #require(run.cueSchedule).remaining(after: t0 + 600).isEmpty, "the tone and the name that began the wait are not played again")

        run.perform(.play, at: t0 + 700)
        #expect(describe(try progress(run, at: 700).phase) == "getReady Child's Pose 2/10")
        #expect(try progress(run, at: 700).phaseRemaining == 3)
    }

    @Test(arguments: [RunCommand.play, .pause, .togglePlayPause])
    func aSinglePressDoesWhatTheWhiteButtonDoesWhileTheRunWaits(_ press: RunCommand) throws {
        let waits = [
            session(.dailyStretch),
            try session(.dailyStretch, in: "ready Child's Pose 2/10"),
            try session(.dailyStretch, in: "ready Pigeon right 5/10"),
            try session(.dailyStretch, in: "ready Passive Dead Hang 10/10"),
        ]
        for waiting in waits {
            try #require(try progress(waiting, at: 60).isWaiting)
            var pressed = waiting
            pressed.perform(press, at: t0 + 60)
            var moved = waiting
            moved.skip(try progress(waiting, at: 60).segment, at: t0 + 60)
            #expect(pressed == moved)
            #expect(pressed != waiting)
        }

        var start = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        start.perform(press, at: t0 + 60)
        let countIn = try progress(start, at: 60)
        #expect(describe(countIn.phase) == "getReady Child's Pose 2/10")
        #expect(countIn.phaseRemaining == 3)
        #expect(!countIn.isPaused)
        #expect(!countIn.isWaiting)

        var last = session(try routine([try stretch("Squat", try reps(5))]))
        last.perform(press, at: t0 + 60)
        #expect(last.snapshot(at: t0 + 60) == .finished(worked: 60))
    }

    @Test(arguments: [("getReady Child's Pose 2/10", 2.0), ("hold Child's Pose 2/10", 44)])
    func aSinglePressPausesAndResumesARoutineThatIsCounting(_ phase: String, remaining: TimeInterval) throws {
        let counting = try session(.dailyStretch, in: phase)

        var played = counting
        played.perform(.play, at: t0 + 1)
        #expect(played == counting)

        for (press, release) in [(RunCommand.pause, RunCommand.play), (.togglePlayPause, .togglePlayPause)] {
            var run = counting
            run.perform(press, at: t0 + 1)
            let held = try progress(run, at: 500)
            #expect(describe(held.phase) == phase)
            #expect(held.phaseRemaining == remaining)
            #expect(held.isPaused)
            #expect(!held.isWaiting)

            run.perform(release, at: t0 + 600)
            let resumed = try progress(run, at: 600.5)
            #expect(describe(resumed.phase) == phase)
            #expect(resumed.phaseRemaining == remaining - 0.5)
            #expect(!resumed.isPaused)
        }
    }

    @Test(arguments: [RunCommand.play, .togglePlayPause])
    func aPressOnAPausedWaitResumesItAndTheNextPressesMoveOn(_ press: RunCommand) throws {
        var run = session(.dailyStretch)
        run.pause(at: t0 + 20)
        let paused = run
        run.perform(.pause, at: t0 + 25)
        #expect(run == paused)

        run.perform(press, at: t0 + 30)
        let resumed = try progress(run, at: 40)
        #expect(describe(resumed.phase) == "hold Cat-Cow 1/10")
        #expect(!resumed.isPaused)
        #expect(resumed.isWaiting)

        run.perform(press, at: t0 + 50)
        let waitingToStart = try progress(run, at: 55)
        #expect(describe(waitingToStart.phase) == "ready Child's Pose 2/10")
        #expect(!waitingToStart.isPaused)
        #expect(waitingToStart.isWaiting)

        run.perform(press, at: t0 + 60)
        #expect(describe(try progress(run, at: 60).phase) == "getReady Child's Pose 2/10")
    }

    @Test func nextOnAPausedRunKeepsItPausedThroughTheWait() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.pause(at: t0 + 3)
        run.perform(.next, at: t0 + 5)
        let waiting = try progress(run, at: 900)
        #expect(describe(waiting.phase) == "ready Cobra 3/10")
        #expect(waiting.isPaused)
        #expect(waiting.isWaiting)

        run.perform(.next, at: t0 + 30)
        let skipped = try progress(run, at: 900)
        #expect(describe(skipped.phase) == "ready Hip Flexor Couch Stretch left 4/10", "Cobra is skipped, not started")
        #expect(skipped.isPaused)
        #expect(skipped.isWaiting)
    }

    @Test func skipStretchFromAWaitForStartLandsOnTheNextWaitWithoutTheCountInOrTheHold() throws {
        var run = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        let worked = run.worked(at: t0 + 10)
        run.forward(try progress(run, at: 10).segment, at: t0 + 10)

        let next = try progress(run, at: 10)
        #expect(describe(next.phase) == "ready Cobra 3/10")
        #expect(next.isWaiting)
        #expect(!next.isPaused)
        #expect(next.elapsed == 48, "the 3 s count-in and the 45 s hold are behind the run")
        #expect(run.snapshot(at: t0 + 9000) == .active(next))
        #expect(run.worked(at: t0 + 9000) == worked, "neither the count-in nor the hold was worked")
    }

    @Test func skipStretchFromOneSideLandsOnTheOtherSide() throws {
        var run = try session(.dailyStretch, in: "ready Pigeon left 5/10")
        run.forward(try progress(run, at: 1).segment, at: t0 + 1)
        #expect(describe(try progress(run, at: 1).phase) == "ready Pigeon right 5/10")
    }

    @Test func skipStretchInARunOfWaitsMovesOneStretchAtATime() throws {
        var run = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        for (offset, expected) in [(1.0, "ready Cobra 3/10"), (1.3, "ready Hip Flexor Couch Stretch left 4/10"),
                                   (1.6, "ready Hip Flexor Couch Stretch right 4/10")] {
            run.forward(try progress(run, at: offset).segment, at: t0 + offset)
            #expect(describe(try progress(run, at: offset).phase) == expected)
        }
    }

    @Test func skipStretchOnTheLastStretchFinishes() throws {
        var run = try session(.dailyStretch, in: "ready Passive Dead Hang 10/10")
        run.forward(try progress(run, at: 5).segment, at: t0 + 5)
        #expect(run.snapshot(at: t0 + 5) == .finished(worked: 501 - 33), "Passive Dead Hang's 3 s count-in and 30 s hold were skipped")
    }

    @Test(arguments: ["hold Cat-Cow 1/10", "getReady Child's Pose 2/10", "hold Child's Pose 2/10"])
    func skipStretchAnywhereButAWaitForStartIsASkip(_ phase: String) throws {
        let start = try session(.dailyStretch, in: phase)
        let segment = try progress(start, at: 1).segment
        var forward = start
        forward.forward(segment, at: t0 + 1)
        var skip = start
        skip.skip(segment, at: t0 + 1)
        #expect(forward == skip)
        #expect(forward != start)
    }

    @Test func nextInAWaitForStartLeavesTheStretchAndASinglePressStillStartsIt() throws {
        let waiting = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        var next = waiting
        next.perform(.next, at: t0 + 1)
        #expect(describe(try progress(next, at: 1).phase) == "ready Cobra 3/10")

        var press = waiting
        press.perform(.play, at: t0 + 1)
        #expect(describe(try progress(press, at: 1).phase) == "getReady Child's Pose 2/10")
    }

    @Test func theForwardButtonIsSkipStretchInAWait() throws {
        #expect(try progress(session(.dailyStretch), at: 0).forwardTitle == "Skip stretch")
        let waiting = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        #expect(try progress(waiting, at: 0).forwardTitle == "Skip stretch")
        var paused = waiting
        paused.pause(at: t0 + 1)
        #expect(try progress(paused, at: 1).forwardTitle == "Skip stretch")
        #expect(try progress(try session(.dailyStretch, in: "getReady Child's Pose 2/10"), at: 0).forwardTitle == "Next")
        #expect(try progress(try session(.dailyStretch, in: "hold Child's Pose 2/10"), at: 0).forwardTitle == "Next")
        #expect(try progress(session(), at: 0).forwardTitle == "Skip")
    }

    @Test(arguments: ["hold Cat-Cow 1/10", "ready Child's Pose 2/10", "ready Pigeon right 5/10"])
    func restartDoesNothingWhileTheRunWaits(_ phase: String) throws {
        let waiting = try session(.dailyStretch, in: phase)
        var run = waiting
        run.perform(.previous, at: t0 + 30)
        #expect(run == waiting)
        run.restart(try progress(run, at: 40).segment, at: t0 + 40)
        #expect(run == waiting)

        run.pause(at: t0 + 50)
        let paused = run
        run.perform(.previous, at: t0 + 60)
        #expect(run == paused)
    }

    @Test func theHaltDateIsTheNextGateOrTheFinish() throws {
        var run = session(.dailyStretch)
        #expect(run.haltDate == t0)
        run.perform(.next, at: t0 + 100)
        #expect(run.haltDate == t0 + 100, "the wait for Start begins at the press")
        run.perform(.play, at: t0 + 110)
        #expect(run.haltDate == t0 + 110 + 3 + 45)
        #expect(run.zeroDate == t0 + 110)

        var last = try session(.dailyStretch, in: "ready Passive Dead Hang 10/10")
        last.perform(.play, at: t0 + 75)
        #expect(last.haltDate == t0 + 75 + 3 + 30)
        #expect(session().haltDate == t0 + 2280)
    }

    @Test func timeInARepStretchCountsAsWorkedAndTheWaitForStartDoesNot() throws {
        var run = session(try squatThenCobra())
        run.perform(.next, at: t0 + 70)
        run.perform(.play, at: t0 + 80)
        #expect(try progress(run, at: 102.5).totalRemaining == 0.5)
        #expect(run.snapshot(at: t0 + 103) == .finished(worked: 23 + 70))
    }

    @Test func pausedTimeInARepStretchDoesNotCountAsWorked() throws {
        var run = session(try squatThenCobra())
        run.pause(at: t0 + 30)
        run.resume(at: t0 + 1000)
        run.perform(.next, at: t0 + 1010)
        run.perform(.play, at: t0 + 1040)
        #expect(run.snapshot(at: t0 + 1063) == .finished(worked: 23 + 30 + 10))
    }

    @Test func endingAHoldEarlyTakesOffTheRestOfIt() throws {
        var run = session(try cobraThenPigeon())
        run.perform(.play, at: t0)
        run.perform(.next, at: t0 + 15)
        run.perform(.play, at: t0 + 20)
        run.perform(.next, at: t0 + 43)
        #expect(run.snapshot(at: t0 + 43) == .finished(worked: 56 - 8 - 10), "8 s of Cobra and 10 s of Pigeon were left")
    }

    @Test func leavingAStretchInItsCountInTakesOffTheRestOfTheCountInAndTheWholeHold() throws {
        var run = session(try cobraThenPigeon())
        run.perform(.play, at: t0)
        run.perform(.next, at: t0 + 1)
        run.perform(.play, at: t0 + 10)
        #expect(run.snapshot(at: t0 + 43) == .finished(worked: 56 - 2 - 20))
    }

    @Test func restartedTimeCountsAgain() throws {
        var run = session(try cobraThenPigeon())
        run.perform(.play, at: t0)
        run.perform(.previous, at: t0 + 15)
        #expect(describe(try progress(run, at: 38).phase) == "ready Pigeon 2/2")
        run.perform(.play, at: t0 + 40)
        #expect(run.snapshot(at: t0 + 73) == .finished(worked: 56 + 15))
    }

    @Test func aRoutineDoneWithoutLingeringWorksItsTimedLength() throws {
        var run = session(.dailyStretch)
        for _ in 0..<13 {
            let halt = try #require(run.haltDate)
            run.perform(.play, at: halt)
        }
        #expect(try progress(run, at: 500.5).totalRemaining == 0.5)
        #expect(run.snapshot(at: t0 + 501) == .finished(worked: 501))
    }
}

struct UpNextTests {
    @Test(arguments: [
        ("hold Cat-Cow 1/10", "hold Child's Pose 2/10", 45.0),
        ("ready Child's Pose 2/10", "hold Cobra 3/10", 30),
        ("getReady Child's Pose 2/10", "hold Cobra 3/10", 30),
        ("hold Child's Pose 2/10", "hold Cobra 3/10", 30),
        ("ready Pigeon left 5/10", "hold Pigeon right 5/10", 45),
        ("getReady Pigeon left 5/10", "hold Pigeon right 5/10", 45),
        ("hold Pigeon left 5/10", "hold Pigeon right 5/10", 45),
        ("ready Pigeon right 5/10", "hold Butterfly 6/10", 45),
        ("hold Pigeon right 5/10", "hold Butterfly 6/10", 45),
    ])
    func upNextNamesWhatFollowsTheHoldOfThisStretch(from phase: String, to next: String, duration: TimeInterval) throws {
        let upNext = try progress(try session(.dailyStretch, in: phase), at: 1).upNext
        #expect(describe(upNext?.phase) == next)
        #expect(upNext?.duration == duration)
    }

    @Test func upNextCarriesTheRepCountOfAStretchCountedInReps() throws {
        let workout = try routine([try stretch("Cobra", try hold(20)), try stretch("Squat", try reps(5))])
        let upNext = try #require(try progress(session(workout), at: 2).upNext)
        #expect(upNext.phase.reps?.value == 5)
        #expect(upNext.duration == 0)
    }

    @Test func upNextReadsAsTheStretchAndItsSide() throws {
        let upNext = try #require(try progress(try session(.dailyStretch, in: "hold Pigeon left 5/10"), at: 20).upNext)
        #expect(upNext.phase.title == "Pigeon")
        #expect(upNext.phase.caption == "Right side · Stretch 5 of 10")
    }

    @Test func theOtherSideOfTheSameStretchIsNamedByItsSide() throws {
        for phase in ["ready Pigeon left 5/10", "getReady Pigeon left 5/10", "hold Pigeon left 5/10"] {
            let left = try progress(try session(.dailyStretch, in: phase), at: 1)
            #expect(try #require(left.upNext).phase.title(following: left.phase) == "Right side", "\(phase)")
        }

        let lastSide = try progress(try session(.dailyStretch, in: "hold Pigeon right 5/10"), at: 20)
        #expect(lastSide.phase.caption == "Right side · Stretch 5 of 10")
        #expect(try #require(lastSide.upNext).phase.title(following: lastSide.phase) == "Butterfly")

        let intervals = try progress(session(), at: 0)
        #expect(try #require(intervals.upNext).phase.title(following: intervals.phase) == "Work")
    }

    @Test(arguments: ["ready Passive Dead Hang 10/10", "getReady Passive Dead Hang 10/10", "hold Passive Dead Hang 10/10"])
    func nothingIsUpNextInTheLastStretch(_ phase: String) throws {
        let p = try progress(try session(.dailyStretch, in: phase), at: 1)
        #expect(describe(p.phase) == phase)
        #expect(p.upNext == nil)
    }
}

struct RestartTests {
    @Test func aHoldGoesBackToItsCountIn() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        let hold = try progress(run, at: 20)
        #expect(describe(hold.phase) == "hold Pigeon left 5/10")
        #expect(hold.phaseRemaining == 25)

        run.restart(hold.segment, at: t0 + 20)

        let after = try progress(run, at: 20)
        #expect(describe(after.phase) == "getReady Pigeon left 5/10")
        #expect(after.phaseElapsed == 0)
        #expect(after.phaseRemaining == 3)
        #expect(after.elapsed == 177)
        #expect(after.totalRemaining == 324)
        #expect(!after.isPaused)
        #expect(!after.isWaiting)
        #expect(run.zeroDate == t0 + 20 - 177)

        let back = try progress(run, at: 23)
        #expect(describe(back.phase) == "hold Pigeon left 5/10")
        #expect(back.phaseRemaining == 45)
    }

    @Test func theSecondSideGoesBackToItsOwnCountIn() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon right 5/10")
        run.restart(try progress(run, at: 10).segment, at: t0 + 10)

        let after = try progress(run, at: 10)
        #expect(describe(after.phase) == "getReady Pigeon right 5/10")
        #expect(after.phaseRemaining == 3)
        #expect(after.elapsed == 225)
    }

    @Test(arguments: [("getReady Pigeon left 5/10", 177.0), ("getReady Pigeon right 5/10", 225)])
    func aCountInGoesBackToItsOwnStart(_ phase: String, start: TimeInterval) throws {
        var run = try session(.dailyStretch, in: phase)
        run.restart(try progress(run, at: 2).segment, at: t0 + 2)
        let after = try progress(run, at: 2)
        #expect(describe(after.phase) == phase)
        #expect(after.elapsed == start)
        #expect(after.phaseElapsed == 0)
    }

    @Test func withNoCountInAHoldGoesBackToItsOwnStart() throws {
        var run = session(try routine(countIn: nil, [try stretch("Cobra", try hold(20))]))
        run.perform(.play, at: t0)
        run.restart(try progress(run, at: 5).segment, at: t0 + 5)
        let after = try progress(run, at: 5)
        #expect(describe(after.phase) == "hold Cobra 1/1")
        #expect(after.phaseRemaining == 20)
        #expect(!after.isWaiting)
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
        let countIn = try progress(run, at: 2).segment
        run.restart(countIn, at: t0 + 4)
        #expect(run == fresh)
    }

    @Test func restartingWhilePausedStaysPaused() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        run.pause(at: t0 + 20)
        run.restart(try progress(run, at: 40).segment, at: t0 + 40)

        let held = try progress(run, at: 900)
        #expect(describe(held.phase) == "getReady Pigeon left 5/10")
        #expect(held.phaseRemaining == 3)
        #expect(held.isPaused)
        #expect(run.cueSchedule == nil)

        run.resume(at: t0 + 1000)
        #expect(try progress(run, at: 1002).phaseRemaining == 1)
    }

    @Test func theCountInTicksAgainAtOnceAndTheNameIsNotSpokenAgain() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        let now = t0 + 20
        run.restart(try progress(run, at: 20).segment, at: now)

        let todo = try #require(run.cueSchedule).remaining(after: now)
        let first = try #require(todo.windows.first)
        #expect(bounds(first) == [20_000, 22_320])
        #expect(cues(first) == [Cue(20_000, .tick), Cue(21_000, .tick), Cue(22_000, .tick)], "the hold begins with no tone")
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

    @Test func nextInACountInLeavesTheStretch() throws {
        var run = try session(.dailyStretch, in: "getReady Pigeon left 5/10")
        run.perform(.next, at: t0 + 1)
        let p = try progress(run, at: 1)
        #expect(describe(p.phase) == "ready Pigeon right 5/10")
        #expect(p.isWaiting)
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

    @Test func previousRestartsTheStretchFromItsCountIn() throws {
        var run = try session(.dailyStretch, in: "hold Pigeon left 5/10")
        run.perform(.previous, at: t0 + 20)
        let p = try progress(run, at: 20)
        #expect(describe(p.phase) == "getReady Pigeon left 5/10")
        #expect(p.elapsed == 177)
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

    @Test(arguments: [RunCommand.pause, .togglePlayPause])
    func aPressNeverMovesAnIntervalTimerOn(_ press: RunCommand) throws {
        for offset in [0.0, 299.5, 300, 540, 2279.5] {
            var run = session()
            let before = try progress(run, at: offset)
            #expect(!before.isWaiting)

            run.perform(.play, at: t0 + offset)
            #expect(run == session())

            run.perform(press, at: t0 + offset)
            let held = try progress(run, at: offset + 5000)
            #expect(held.isPaused, "\(offset)")
            #expect(held.segment == before.segment, "\(offset)")
            #expect(held.phaseRemaining == before.phaseRemaining, "\(offset)")
        }
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

struct PhaseEndTests {
    @Test func itIsOneDateForTheWholePhase() {
        let run = session()
        #expect(run.phaseEnd(at: t0) == t0 + 300)
        #expect(run.phaseEnd(at: t0 + 123.456) == t0 + 300)
        #expect(run.phaseEnd(at: t0 + 299.999) == t0 + 300)
        #expect(run.phaseEnd(at: t0 + 300) == t0 + 540, "work has begun")
    }

    @Test func itMovesWithAPauseAndASkip() throws {
        var run = session()
        run.pause(at: t0 + 100)
        #expect(run.phaseEnd(at: t0 + 500) == nil, "a paused clock is not counting")
        run.resume(at: t0 + 1000)
        #expect(run.phaseEnd(at: t0 + 1000) == t0 + 1200)

        run.skip(try progress(run, at: 1000).segment, at: t0 + 1000)
        #expect(run.phaseEnd(at: t0 + 1000) == t0 + 1240, "four minutes of work from the skip")
    }

    /// Daily Stretch opens on reps. Child's Pose follows: a wait for Start, a 3-second count-in, a 45-second hold.
    @Test func aRoutineHasOneOnlyBetweenStartAndTheEndOfTheHold() {
        var run = session(.dailyStretch)
        #expect(run.phaseEnd(at: t0 + 8) == nil, "the reps wait for Next")
        run.perform(.next, at: t0 + 8)
        #expect(run.phaseEnd(at: t0 + 60) == nil, "the hold waits for Start")
        run.perform(.play, at: t0 + 60)
        #expect(run.phaseEnd(at: t0 + 60) == t0 + 63, "the count-in")
        #expect(run.phaseEnd(at: t0 + 62.9) == t0 + 63)
        #expect(run.phaseEnd(at: t0 + 63) == t0 + 108, "the hold")
        #expect(run.phaseEnd(at: t0 + 108) == nil, "the next stretch waits for Start")
    }

    @Test func aFinishedRunHasNone() {
        #expect(session().phaseEnd(at: t0 + 2280) == nil)
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
