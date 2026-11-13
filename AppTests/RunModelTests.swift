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
        run.handle(.next)

        let waiting = try progress(run)
        XCTAssertEqual(waiting.phase.title, "Cat-Cow")
        XCTAssertEqual(waiting.phase.caption, "Stretch 1 of 10")
        XCTAssertEqual(waiting.reps?.value, 10)
        XCTAssertTrue(waiting.isWaiting)

        run.handle(.next)
        let next = try progress(run)
        XCTAssertEqual(next.phase.title, "Child's Pose")
        XCTAssertEqual(next.phase.caption, "Get ready")
        XCTAssertFalse(next.isWaiting)
        XCTAssertNotNil(run.undo, "moving on from a wait can be taken back")

        run.undoLast()
        let back = try progress(run)
        XCTAssertEqual(back.phase.title, "Cat-Cow")
        XCTAssertTrue(back.isWaiting)
        XCTAssertNil(run.undo)
    }

    func testASinglePressEndsAWaitAndUndoBringsTheWaitBack() throws {
        for press in [RunCommand.togglePlayPause, .play, .pause] {
            let run = makeRun()
            defer { run.end() }
            run.start(.dailyStretch, cues: CuePreferences())
            run.handle(.next)
            XCTAssertTrue(try progress(run).isWaiting)

            run.handle(press)
            let next = try progress(run)
            XCTAssertEqual(next.phase.title, "Child's Pose", "\(press)")
            XCTAssertEqual(next.phase.caption, "Get ready", "\(press)")
            XCTAssertFalse(next.isPaused, "\(press)")
            XCTAssertFalse(next.isWaiting, "\(press)")
            XCTAssertNotNil(run.undo, "a press that moved on can be taken back like Next: \(press)")

            run.undoLast()
            let back = try progress(run)
            XCTAssertEqual(back.phase.title, "Cat-Cow", "\(press)")
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
        XCTAssertEqual(try progress(run).phase.caption, "Stretch 1 of 10")
        XCTAssertNil(run.undo, "a resume is not something to undo")
    }

    func testPreviousRestartsAHoldFromTheGapBeforeIt() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.dailyStretch, cues: CuePreferences())
        run.handle(.next)
        XCTAssertEqual(try progress(run).phase.caption, "Stretch 1 of 10")

        run.handle(.previous)

        let restarted = try progress(run)
        XCTAssertEqual(restarted.phase.title, "Cat-Cow")
        XCTAssertEqual(restarted.phase.caption, "Get ready")
        XCTAssertNotNil(run.undo)

        run.undoLast()
        XCTAssertEqual(try progress(run).phase.caption, "Stretch 1 of 10")
    }

    func testTogglePausesAndResumes() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.dailyStretch, cues: CuePreferences())

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

        remote.reconcile(session, at: start + 2)
        var card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Cat-Cow")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Get ready")
        XCTAssertEqual(card[MPMediaItemPropertyAlbumTitle] as? String, "Daily Stretch")
        XCTAssertEqual(card[MPMediaItemPropertyPlaybackDuration] as? Double, 8)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)

        session.perform(.next, at: start + 2)
        session.perform(.next, at: start + 3)
        session.perform(.next, at: start + 4)
        session.pause(at: start + 14)
        remote.reconcile(session, at: start + 14)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Child's Pose")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Stretch 2 of 10")
        XCTAssertEqual(card[MPMediaItemPropertyPlaybackDuration] as? Double, 45)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)

        remote.reconcile(nil, at: start + 14)
        XCTAssertNil(center.nowPlayingInfo)
    }

    func testTheLockScreenSaysTheRunIsWaitingForNext() throws {
        let remote = HeadphoneRemote(log: AudioLog())
        let center = MPNowPlayingInfoCenter.default()
        let start = Date.now
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        defer { remote.reconcile(nil, at: start) }

        remote.reconcile(session, at: start + 7)
        XCTAssertEqual(try XCTUnwrap(center.nowPlayingInfo)[MPMediaItemPropertyArtist] as? String, "Get ready")

        remote.reconcile(session, at: start + 8)
        var card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Cat-Cow")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "10 reps · Waiting for Next")
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)

        session.perform(.next, at: start + 60)
        remote.reconcile(session, at: start + 70)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Stretch 2 of 10")
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)

        remote.reconcile(session, at: start + 113)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyTitle] as? String, "Child's Pose")
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Done · Waiting for Next", "a hold that ran out rewrites the card with no change to the session")
        XCTAssertEqual(card[MPMediaItemPropertyPlaybackDuration] as? Double, 45)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
    }

    func testAWaitIsStandbyOnceItsToneHasSounded() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        func demand(at offset: TimeInterval) -> CueDemand {
            CueDemand(for: session, playing: session.cueSchedule, at: start + offset)
        }
        let schedule = try XCTUnwrap(session.cueSchedule)

        XCTAssertEqual(demand(at: 3), .playing(schedule), "getting ready, with the countdown still to come")
        XCTAssertEqual(demand(at: 8.2), .playing(schedule), "the wait has begun, but the tone that began it is still sounding")
        XCTAssertEqual(demand(at: 9), .standby)
        XCTAssertEqual(demand(at: 3600), .standby)

        session.perform(.next, at: start + 100)
        let next = try XCTUnwrap(session.cueSchedule)
        XCTAssertEqual(demand(at: 100), .playing(next))
        XCTAssertEqual(demand(at: 130), .playing(next), "a hold that is counting has its countdown still to come")
        XCTAssertEqual(demand(at: 153.2), .playing(next), "the tone at zero is sounding")
        XCTAssertEqual(demand(at: 154), .standby)

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
        return RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log))
    }

    private func progress(_ run: RunModel) throws -> RunProgress {
        guard case .active(let progress)? = run.session?.snapshot(at: .now) else { throw NotActive() }
        return progress
    }

    private struct NotActive: Error {}
}
