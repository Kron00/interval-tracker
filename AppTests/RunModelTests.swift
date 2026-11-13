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
        session.pause(at: start + 12)
        remote.reconcile(session, at: start + 12)
        card = try XCTUnwrap(center.nowPlayingInfo)
        XCTAssertEqual(card[MPMediaItemPropertyArtist] as? String, "Stretch 1 of 10")
        XCTAssertEqual(card[MPMediaItemPropertyPlaybackDuration] as? Double, 50)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(card[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)

        remote.reconcile(nil, at: start + 12)
        XCTAssertNil(center.nowPlayingInfo)
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
