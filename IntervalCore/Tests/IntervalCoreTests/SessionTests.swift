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
        for (workout, total) in [(Workout.norwegian4x4, 2280.0), (.dailyStretch, 645)] {
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

struct RepTests {
    @Test(arguments: [(8.0, 1), (12.99, 1), (13.0, 2), (17.5, 2), (53.0, 10), (57.9, 10)])
    func theRepInProgress(at offset: TimeInterval, is number: Int) throws {
        let p = try progress(session(.dailyStretch), at: offset)
        #expect(describe(p.phase) == "hold Cat-Cow 1/10")
        #expect(p.rep?.number == number)
        #expect(p.rep?.total == 10)
    }

    @Test func theLastRepIsMarkedLast() throws {
        #expect(try progress(session(.dailyStretch), at: 52.9).rep?.isLast == false)
        #expect(try progress(session(.dailyStretch), at: 53).rep?.isLast == true)
    }

    @Test(arguments: [4.0, 60, 70, 280, 307])
    func onlyARepHoldCountsReps(at offset: TimeInterval) throws {
        #expect(try progress(session(.dailyStretch), at: offset).rep == nil)
    }

    @Test func repsAreCountedOnEachSide() throws {
        let run = session(try routine(getReady: 5, switchSides: 3, [
            try stretch("Leg Swings", try reps(6, every: 2), .each),
        ]))
        #expect(try progress(run, at: 16.5).rep?.number == 6)
        #expect(try progress(run, at: 18).rep == nil)
        #expect(try progress(run, at: 20).rep?.number == 1)
        #expect(try progress(run, at: 22).rep?.number == 2)
    }
}

struct UpNextTests {
    @Test(arguments: [
        (4.0, "hold Cat-Cow 1/10", 50.0),
        (20, "hold Child's Pose 2/10", 45),
        (255, "hold Pigeon left 5/10", 45),
        (280, "hold Pigeon right 5/10", 45),
        (307, "hold Pigeon right 5/10", 45),
        (320, "hold Butterfly 6/10", 45),
        (610, "hold Passive Dead Hang 10/10", 30),
    ])
    func upNextLooksPastTheGaps(at offset: TimeInterval, phase: String, duration: TimeInterval) throws {
        let upNext = try progress(session(.dailyStretch), at: offset).upNext
        #expect(describe(upNext?.phase) == phase)
        #expect(upNext?.duration == duration)
    }

    @Test func upNextReadsAsTheStretchAndItsSide() throws {
        let upNext = try #require(try progress(session(.dailyStretch), at: 280).upNext)
        #expect(upNext.phase.title == "Pigeon")
        #expect(upNext.phase.caption == "Right side · Stretch 5 of 10")
    }

    @Test func nothingIsUpNextInTheLastHold() throws {
        let p = try progress(session(.dailyStretch), at: 620)
        #expect(describe(p.phase) == "hold Passive Dead Hang 10/10")
        #expect(p.upNext == nil)
    }
}

struct RestartTests {
    @Test func aHoldGoesBackToItsGetReadyGap() throws {
        var run = session(.dailyStretch)
        let hold = try progress(run, at: 280)
        #expect(describe(hold.phase) == "hold Pigeon left 5/10")

        run.restart(hold.segment, at: t0 + 280)

        let after = try progress(run, at: 280)
        #expect(describe(after.phase) == "getReady Pigeon left 5/10")
        #expect(after.phaseElapsed == 0)
        #expect(after.phaseRemaining == 8)
        #expect(after.elapsed == 252)
        #expect(after.totalRemaining == 393)
        #expect(!after.isPaused)
        #expect(run.zeroDate == t0 + 28)

        let back = try progress(run, at: 288)
        #expect(describe(back.phase) == "hold Pigeon left 5/10")
        #expect(back.phaseRemaining == 45)
    }

    @Test func theSecondSideGoesBackToSwitchSides() throws {
        var run = session(.dailyStretch)
        let hold = try progress(run, at: 320)
        #expect(describe(hold.phase) == "hold Pigeon right 5/10")

        run.restart(hold.segment, at: t0 + 320)

        let after = try progress(run, at: 320)
        #expect(describe(after.phase) == "switchSides to Pigeon right 5/10")
        #expect(after.phaseRemaining == 5)
        #expect(after.elapsed == 305)
    }

    @Test func theFirstHoldGoesBackToTheVeryStart() throws {
        var run = session(.dailyStretch)
        run.restart(try progress(run, at: 20).segment, at: t0 + 20)
        let after = try progress(run, at: 20)
        #expect(describe(after.phase) == "getReady Cat-Cow 1/10")
        #expect(after.elapsed == 0)
    }

    @Test(arguments: [(255.0, "getReady Pigeon left 5/10", 252.0), (307, "switchSides to Pigeon right 5/10", 305)])
    func aGapGoesBackToItsOwnStart(at offset: TimeInterval, phase: String, start: TimeInterval) throws {
        var run = session(.dailyStretch)
        run.restart(try progress(run, at: offset).segment, at: t0 + offset)
        let after = try progress(run, at: offset)
        #expect(describe(after.phase) == phase)
        #expect(after.elapsed == start)
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
        var run = session(.dailyStretch)
        let hold = try progress(run, at: 280).segment
        run.restart(hold, at: t0 + 280)
        let once = run
        run.restart(hold, at: t0 + 280.2)
        #expect(run == once)
    }

    @Test func aStaleSegmentIsIgnoredAfterANaturalPhaseChange() throws {
        var run = session(.dailyStretch)
        let getReady = try progress(run, at: 259).segment
        run.restart(getReady, at: t0 + 261)
        #expect(run == session(.dailyStretch))
    }

    @Test func restartingWhilePausedStaysPaused() throws {
        var run = session(.dailyStretch)
        run.pause(at: t0 + 280)
        run.restart(try progress(run, at: 300).segment, at: t0 + 300)

        let held = try progress(run, at: 900)
        #expect(describe(held.phase) == "getReady Pigeon left 5/10")
        #expect(held.phaseRemaining == 8)
        #expect(held.isPaused)
        #expect(run.cueSchedule == nil)

        run.resume(at: t0 + 1000)
        #expect(try progress(run, at: 1004).phaseRemaining == 4)
    }

    @Test func theStretchIsNamedAgainAtOnce() throws {
        var run = session(.dailyStretch)
        let now = t0 + 280
        run.restart(try progress(run, at: 280).segment, at: now)

        let todo = try #require(run.cueSchedule).remaining(after: now)
        let first = try #require(todo.windows.first)
        #expect(bounds(first) == [280_000, 282_200])
        #expect(cues(first) == [Cue(280_000, .phaseChange), Cue(280_500, voice("Pigeon, left side"))])
    }

    @Test func aFinishedRunCountsRestartedTimeAgain() throws {
        var run = session(.dailyStretch)
        run.restart(try progress(run, at: 280).segment, at: t0 + 280)
        #expect(try progress(run, at: 672.5).totalRemaining == 0.5)
        #expect(run.snapshot(at: t0 + 673) == .finished(worked: 645 + 28))
    }

    @Test func aFinishedRunAddsRestartsAndTakesOffSkips() throws {
        var run = session(.dailyStretch)
        run.restart(try progress(run, at: 280).segment, at: t0 + 280)
        let hold = try progress(run, at: 300)
        #expect(describe(hold.phase) == "hold Pigeon left 5/10")
        #expect(hold.phaseRemaining == 33)
        run.skip(hold.segment, at: t0 + 300)
        #expect(run.snapshot(at: t0 + 10_000) == .finished(worked: 645 + 28 - 33))
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
        var run = session(.dailyStretch)
        run.perform(.next, at: t0 + 255)
        let p = try progress(run, at: 255)
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
        var run = session(.dailyStretch)
        run.perform(.previous, at: t0 + 280)
        let p = try progress(run, at: 280)
        #expect(describe(p.phase) == "getReady Pigeon left 5/10")
        #expect(p.elapsed == 252)
    }

    @Test func previousRestartsAnIntervalPhase() throws {
        var run = session()
        run.perform(.previous, at: t0 + 420)
        let p = try progress(run, at: 420)
        #expect(describe(p.phase) == "work 1/4")
        #expect(p.phaseRemaining == 240)
    }

    @Test func aPressDeliveredTwiceAtTheSameInstantRestartsOnce() {
        var run = session(.dailyStretch)
        run.perform(.previous, at: t0 + 280)
        let once = run
        run.perform(.previous, at: t0 + 280)
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
