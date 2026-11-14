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
    }

    func testNextEndsAWaitAndPreviousBringsTheWaitBack() throws {
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

        run.handle(.previous)
        let back = try progress(run)
        XCTAssertEqual(back.phase.title, "Cat-Cow")
        XCTAssertTrue(back.isWaiting)
    }

    func testASinglePressWhileWaitingToStartBeginsTheCountIn() throws {
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
    }

    func testPreviousGoesBackToThePhaseBefore() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.norwegian4x4, cues: CuePreferences())
        run.handle(.next)
        run.handle(.next)
        XCTAssertEqual(try progress(run).phase.title, "Rest")

        run.handle(.previous)
        let work = try progress(run)
        XCTAssertEqual(work.phase.title, "Work")
        XCTAssertEqual(work.phase.caption, "Round 1 of 4")
        XCTAssertGreaterThan(work.phaseRemaining, 239, "the round starts from the top")

        run.back(work.segment)
        XCTAssertEqual(try progress(run).phase.title, "Warm-up", "the back button on the screen does the same")
    }

    func testTogglePausesAndResumesARunThatIsCounting() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.norwegian4x4, cues: CuePreferences())

        run.handle(.togglePlayPause)
        XCTAssertTrue(try progress(run).isPaused)

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
        }
    }

    func testTheLockScreenShowsThePhaseInProgress() throws {
        let remote = HeadphoneRemote(log: AudioLog())
        let center = MPNowPlayingInfoCenter.default()
        let start = Date.now
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        defer { remote.reconcile(nil, at: start) }

        session.perform(.next, at: start + 2)
        session.perform(.play, at: start + 4)
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

        session.perform(.play, at: start + 70)
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

    /// With voice off a wait has no name to say and nothing else to play, so it is on standby from
    /// the start. Headphone controls hold the audio on standby, and only on standby.
    func testWithVoiceOffAWaitIsStandbyAtOnce() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var session = Session(.dailyStretch, cues: CuePreferences(voice: false), startingAt: start)
        XCTAssertEqual(CueDemand(for: session, playing: session.cueSchedule, at: start + 0.1), .standby,
                       "Cat-Cow is counted in reps and waits for Next from the start")

        session.perform(.next, at: start + 100)
        XCTAssertEqual(CueDemand(for: session, playing: session.cueSchedule, at: start + 100.1), .standby,
                       "Next lands on the wait for Child's Pose, and with voice off nothing announces it")

        session.perform(.play, at: start + 110)
        XCTAssertEqual(CueDemand(for: session, playing: session.cueSchedule, at: start + 110.5),
                       .playing(try XCTUnwrap(session.cueSchedule)), "Start begins the count-in, which ticks")
    }

    func testAWaitIsStandbyOnceItsNameHasSounded() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        func demand(at offset: TimeInterval) -> CueDemand {
            CueDemand(for: session, playing: session.cueSchedule, at: start + offset)
        }
        let schedule = try XCTUnwrap(session.cueSchedule)

        XCTAssertEqual(demand(at: 1), .playing(schedule), "the wait has begun, but its name is still sounding")
        XCTAssertEqual(demand(at: 3), .standby)
        XCTAssertEqual(demand(at: 3600), .standby)

        session.perform(.next, at: start + 100)
        let waitingToStart = try XCTUnwrap(session.cueSchedule)
        XCTAssertEqual(demand(at: 100.5), .playing(waitingToStart), "Next landed quietly, and the wait is named a second later")
        XCTAssertEqual(demand(at: 103), .playing(waitingToStart), "the name runs from 101.5 to 103")
        XCTAssertEqual(demand(at: 103.3), .standby, "nothing sounds until Start")

        session.perform(.play, at: start + 110)
        let hold = try XCTUnwrap(session.cueSchedule)
        XCTAssertEqual(demand(at: 111), .playing(hold), "the count-in is ticking")
        XCTAssertEqual(demand(at: 130), .playing(hold), "a hold that is counting has its countdown still to come")
        XCTAssertEqual(demand(at: 159), .playing(hold), "the hold ran out at 158, and the next name is being spoken")
        XCTAssertEqual(demand(at: 161), .standby)

        session.pause(at: start + 200)
        XCTAssertEqual(demand(at: 200), .standby)
        XCTAssertEqual(CueDemand(for: nil, playing: nil, at: start), .none)
    }

    func testAWaitReachedBySkipStretchKeepsItsAudioUntilItHasBeenNamed() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var session = Session(.dailyStretch, cues: CuePreferences(), startingAt: start)
        session.perform(.play, at: start + 10)
        session.forward(try progress(session, at: start + 20).segment, at: start + 20)
        XCTAssertEqual(try progress(session, at: start + 20).phase.title, "Cobra")
        let landed = try XCTUnwrap(session.cueSchedule)
        func demand(at offset: TimeInterval) -> CueDemand {
            CueDemand(for: session, playing: landed, at: start + offset)
        }

        XCTAssertEqual(demand(at: 20), .playing(landed), "the music dips at the tap")
        XCTAssertEqual(demand(at: 21.4), .playing(landed), "the name is still to come")
        XCTAssertEqual(demand(at: 22.9), .playing(landed), "the name is being spoken")
        XCTAssertEqual(demand(at: 23.3), .standby)
    }

    /// The player queues what remains of the schedule it is given, and starts both of its nodes again
    /// when the schedule changes. So what a skip queued is gone once going back hands it a new schedule.
    func testGoingBackBeforeTheLandingIsAnnouncedLeavesNothingOfItToPlay() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.norwegian4x4, cues: CuePreferences(headsUp: .off))
        Thread.sleep(forTimeInterval: 2.5)
        let tap = Date.now
        run.skip(try progress(run).segment)
        let skipped = try XCTUnwrap(run.session?.cueSchedule)
        XCTAssertEqual(CueDemand(for: run.session, playing: skipped, at: .now), .playing(skipped))
        let landing = try XCTUnwrap(skipped.remaining(after: .now).windows.first?.sounds.first)
        XCTAssertEqual(landing.sound, .voice(Utterance("Round one")), "a landing has no tone")
        XCTAssertEqual(landing.at.timeIntervalSince(tap), 1.5, accuracy: 0.2, "the name comes half a second after the one-second settle")

        let backTap = Date.now
        run.back(try progress(run).segment)
        let back = try XCTUnwrap(run.session?.cueSchedule)
        XCTAssertNotEqual(back, skipped, "a new schedule, so the player queues again")
        XCTAssertEqual(try progress(run).phase.title, "Warm-up")
        let first = try XCTUnwrap(back.remaining(after: .now).windows.first)
        XCTAssertEqual(first.sounds.map(\.sound), [.voice(Utterance("Warm up"))], "only the place it went back to is named")
        XCTAssertEqual(first.sounds[0].at.timeIntervalSince(backTap), 1.5, accuracy: 0.2)
    }

    func testSkipStretchAndBackStepThroughTheWaits() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.dailyStretch, cues: CuePreferences())
        run.handle(.play)
        XCTAssertEqual(try progress(run).phase.title, "Child's Pose")

        run.forward(try progress(run).segment)
        XCTAssertEqual(try progress(run).phase.title, "Cobra")
        XCTAssertTrue(try progress(run).isWaiting, "Child's Pose was skipped, not started")

        run.forward(try progress(run).segment)
        XCTAssertEqual(try progress(run).phase.title, "Hip Flexor Couch Stretch")
        run.back(try progress(run).segment)
        XCTAssertEqual(try progress(run).phase.title, "Cobra", "back goes one stretch at a time")
        XCTAssertTrue(try progress(run).isWaiting)
    }

    func testADoublePressInAWaitSkipsTheStretch() throws {
        let run = makeRun()
        defer { run.end() }
        run.start(.dailyStretch, cues: CuePreferences())
        run.handle(.play)
        run.handle(.next)
        XCTAssertEqual(try progress(run).phase.title, "Cobra")
        XCTAssertTrue(try progress(run).isWaiting)
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
                        liveActivity: LiveActivityController(display: RecordingDisplay(), log: log), heartRate: .scripted())
    }

    private func progress(_ session: Session, at date: Date) throws -> RunProgress {
        guard case .active(let progress) = session.snapshot(at: date) else { throw NotActive() }
        return progress
    }

    private func progress(_ run: RunModel) throws -> RunProgress {
        guard case .active(let progress)? = run.session?.snapshot(at: .now) else { throw NotActive() }
        return progress
    }

    private struct NotActive: Error {}
}
