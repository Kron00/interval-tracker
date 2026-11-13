import IntervalCore
import MediaPlayer
import XCTest
@testable import IntervalTracker

@MainActor
final class RunModelTests: XCTestCase {
    func testNextSkipsThePhaseInProgress() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.norwegian4x4, cues: CuePreferences())
        XCTAssertEqual(try progress(run).phase.title, "Warm-up")

        run.handle(.next)

        XCTAssertEqual(try progress(run).phase.title, "Work")
        XCTAssertNotNil(run.undo, "a skip from the headphones can be taken back like a skip on the screen")
    }

    func testNextEndsAWaitAndUndoBringsTheWaitBack() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.dailyStretch, cues: CuePreferences())

        let waiting = try progress(run)
        XCTAssertEqual(waiting.phase.title, "Cat-Cow")
        XCTAssertEqual(waiting.phase.caption, "Stretch 1 of 10")
        XCTAssertEqual(waiting.reps?.value, 10)
        XCTAssertTrue(waiting.isWaiting)

        run.handle(.next)
        let next = try progress(run)
        XCTAssertEqual(next.phase.title, "Child's Pose")
        XCTAssertEqual(next.phase.pendingHold, 45)
        XCTAssertTrue(next.isWaiting, "a timed stretch waits for Start")
        XCTAssertNotNil(run.undo, "moving on from a wait can be taken back")

        run.undoLast()
        let back = try progress(run)
        XCTAssertEqual(back.phase.title, "Cat-Cow")
        XCTAssertTrue(back.isWaiting)
        XCTAssertNil(run.undo)
    }

    func testASinglePressWhileWaitingToStartBeginsTheCountInAndUndoBringsTheWaitBack() throws {
        for press in [RunCommand.togglePlayPause, .play, .pause] {
            let run = makeRun()
            defer { run.end() }
            run.start(.dailyStretch, cues: CuePreferences())

            run.handle(press)
            let waiting = try progress(run)
            XCTAssertEqual(waiting.phase.title, "Child's Pose", "a press on a rep stretch is Next: \(press)")
            XCTAssertEqual(waiting.phase.advanceTitle, "Start", "\(press)")
            XCTAssertTrue(waiting.isWaiting, "\(press)")

            run.handle(press)
            let countIn = try progress(run)
            XCTAssertEqual(countIn.phase.title, "Child's Pose", "\(press)")
            XCTAssertEqual(countIn.phase.caption, "Get ready", "\(press)")
            XCTAssertFalse(countIn.isPaused, "\(press)")
            XCTAssertFalse(countIn.isWaiting, "\(press)")
            XCTAssertNotNil(run.undo, "a press that started the stretch can be taken back like Start: \(press)")

            run.undoLast()
            let back = try progress(run)
            XCTAssertEqual(back.phase.title, "Child's Pose", "\(press)")
            XCTAssertEqual(back.phase.pendingHold, 45, "\(press)")
            XCTAssertTrue(back.isWaiting, "\(press)")
            XCTAssertFalse(back.isPaused, "\(press)")
        }
    }

    func testAnInterruptionPausesAWaitAndResumeReturnsToIt() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.dailyStretch, cues: CuePreferences())
        run.handle(.next)

        run.pause()
        XCTAssertTrue(try progress(run).isPaused)
        XCTAssertTrue(try progress(run).isWaiting)
        run.handle(.togglePlayPause)
        XCTAssertFalse(try progress(run).isPaused, "a press on a paused wait resumes it")
        XCTAssertTrue(try progress(run).isWaiting)
        XCTAssertEqual(try progress(run).phase.pendingHold, 45)
        XCTAssertNil(run.undo, "a resume is not something to undo")
    }

    func testPreviousDoesNothingWhileTheRunWaitsAndOffersNoUndo() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.dailyStretch, cues: CuePreferences())
        run.handle(.next)
        let waiting = run.session

        run.handle(.previous)

        XCTAssertEqual(run.session, waiting)
        XCTAssertNil(run.undo, "nothing happened, so there is nothing to take back")
    }

    func testPreviousRestartsACountInAndUndoTakesItBack() throws {
        let run = makeRun()
        defer { run.end() }
        let cobra = try XCTUnwrap(Stretch(name: "Cobra", amount: .hold(try XCTUnwrap(Span(seconds: 30))), sides: .once, howTo: nil))
        let routine = try XCTUnwrap(Routine(countIn: Span(seconds: 30), stretches: [cobra]))
        run.start(Workout(name: "Test", plan: .routine(routine)), cues: CuePreferences())
        run.handle(.next)
        Thread.sleep(forTimeInterval: 1.2)
        let before = try progress(run)
        XCTAssertEqual(before.phase.caption, "Get ready")
        XCTAssertLessThan(before.phaseRemaining, 29)

        run.handle(.previous)

        XCTAssertGreaterThan(try progress(run).phaseRemaining, 29, "the count-in starts again")
        XCTAssertNotNil(run.undo)

        run.undoLast()
        XCTAssertLessThan(try progress(run).phaseRemaining, 29)
    }

    func testTogglePausesAndResumesARunThatIsCounting() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.norwegian4x4, cues: CuePreferences())

        run.handle(.togglePlayPause)
        XCTAssertTrue(try progress(run).isPaused)
        XCTAssertNil(run.undo, "a pause is not something to undo")

        run.handle(.togglePlayPause)
        XCTAssertFalse(try progress(run).isPaused)

        run.handle(.pause)
        run.handle(.pause)
        XCTAssertTrue(try progress(run).isPaused)
        run.handle(.play)
        XCTAssertFalse(try progress(run).isPaused)
        XCTAssertEqual(try progress(run).phase.title, "Warm-up")
    }

    func testCommandsDoNothingWithNoSession() {
        let run = makeRun()
        for command in [RunCommand.play, .pause, .togglePlayPause, .next, .previous] {
            run.handle(command)
            XCTAssertNil(run.session, "\(command)")
            XCTAssertNil(run.undo, "\(command)")
        }
    }

    func testTheLockScreenShowsThePhaseInProgress() throws {
        let remote = HeadphoneRemote(log: AudioLog())
        let center = MPNowPlayingInfoCenter.default()
        let start = Date.now
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        defer { remote.reconcile(nil, at: start) }

        session.perform(.next, at: start + 2)
        session.perform(.next, at: start + 4)
        remote.reconcile(session, at: start + 5)
        var card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Child's Pose")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Get ready")
        XCTAssertEqual(card[MPMediaItemPropertyAlbumTitle] as? String, "Daily Stretch")
        XCTAssertEqual(card[MPMediaItemPropertyPlaybackDuration] as? Double, 3)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)

        session.pause(at: start + 17)
        remote.reconcile(session, at: start + 17)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Child's Pose")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Stretch 2 of 10")
        XCTAssertEqual(card[MPMediaItemPropertyPlaybackDuration] as? Double, 45)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)

        remote.reconcile(nil, at: start + 17)
        XCTAssertNil(center.nowPlayingInfo)
    }

    func testTheLockScreenSaysWhatTheRunWaitsFor() throws {
        let remote = HeadphoneRemote(log: AudioLog())
        let center = MPNowPlayingInfoCenter.default()
        let start = Date.now
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        defer { remote.reconcile(nil, at: start) }

        remote.reconcile(session, at: start + 1)
        var card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Cat-Cow")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "10 reps · Waiting for Next")
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)

        session.perform(.next, at: start + 60)
        remote.reconcile(session, at: start + 61)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Child's Pose")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "0:45 · Waiting for Start")
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)

        session.perform(.next, at: start + 70)
        remote.reconcile(session, at: start + 80)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Stretch 2 of 10")
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)

        remote.reconcile(session, at: start + 118)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Cobra", "a hold that ran out rewrites the card with no change to the session")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "0:30 · Waiting for Start")
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
    }

    func testAWaitIsStandbyOnceItsToneAndItsNameHaveSounded() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        func demand(at offset: TimeInterval) -> CueDemand {
            CueDemand(for: session, playing: session.cueSchedule, at: start + offset)
        }
        let schedule = try XCTUnwrap(session.cueSchedule)

        XCTAssertEqual(demand(at: 1), .playing(schedule), "the wait has begun, but its tone and the name are still sounding")
        XCTAssertEqual(demand(at: 3), .standby)
        XCTAssertEqual(demand(at: 3600), .standby)

        session.perform(.next, at: start + 100)
        let waitingToStart = try XCTUnwrap(session.cueSchedule)
        XCTAssertEqual(demand(at: 100.5), .playing(waitingToStart))
        XCTAssertEqual(demand(at: 103), .standby, "nothing sounds until Start")

        session.perform(.next, at: start + 110)
        let hold = try XCTUnwrap(session.cueSchedule)
        XCTAssertEqual(demand(at: 111), .playing(hold), "the count-in is ticking")
        XCTAssertEqual(demand(at: 130), .playing(hold), "a hold that is counting has its countdown still to come")
        XCTAssertEqual(demand(at: 159), .playing(hold), "the hold ran out at 158, and the next name is being spoken")
        XCTAssertEqual(demand(at: 161), .standby)

        session.pause(at: start + 200)
        XCTAssertEqual(demand(at: 200), .standby)
        XCTAssertEqual(CueDemand(for: nil, playing: nil, at: start), .none)
    }

    func testAnIntervalTimerIsNeverOnStandbyWhileItRuns() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = Session(.audioCheck, cues: CuePreferences(), startingAt: start)
        let schedule = try XCTUnwrap(session.cueSchedule)
        for offset in [0.0, 15, 35, 59, 60, 61, 600] {
            XCTAssertEqual(CueDemand(for: session, playing: schedule, at: start + offset), .playing(schedule), "\(offset)")
        }
    }

    private func makeRun() -> RunModel {
        let log = AudioLog()
        return RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log),
                        liveActivity: LiveActivityController(display: RecordingDisplay(), log: log))
    }

    private func progress(_ run: RunModel) throws -> RunProgress {
        guard case .active(let progress)? = run.session?.snapshot(at: .now) else { throw NotActive() }
        return progress
    }

    private struct NotActive: Error {}
}
