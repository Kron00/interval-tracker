import IntervalCore
import MediaPlayer

/// Publishes the run to the lock screen and receives its buttons. AirPods presses arrive as the same
/// commands, but only while the app's audio does not mix with other apps.
@MainActor
final class HeadphoneRemote {
    var onCommand: (RunCommand) -> Void = { _ in }

    private let log: AudioLog
    private var targets: [(command: MPRemoteCommand, target: Any)] = []
    private var published: Card?

    init(log: AudioLog) { self.log = log }

    /// `nil` means headphone controls are off or nothing is running.
    func reconcile(_ session: Session?, at now: Date) {
        guard let session, case .active(let progress) = session.snapshot(at: now) else {
            detach()
            return
        }
        attach()
        // The system advances the elapsed time itself from the rate, so the card is rewritten only
        // when the run changes, a new phase starts, or a wait begins.
        let card = Card(session: session, segment: progress.segment, isWaiting: progress.isWaiting)
        guard card != published else { return }
        published = card

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: progress.phase.title,
            MPMediaItemPropertyAlbumTitle: session.workout.name,
            MPMediaItemPropertyPlaybackDuration: progress.phaseDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress.phaseElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: progress.isPaused || progress.isWaiting ? 0.0 : 1.0,
        ]
        info[MPMediaItemPropertyArtist] = progress.isWaiting
            ? [progress.awaited, "Waiting for \(progress.phase.advanceTitle)"].compactMap { $0 }.joined(separator: " · ")
            : progress.phase.caption
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func attach() {
        guard targets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, RunCommand)] = [
            (center.playCommand, .play),
            (center.pauseCommand, .pause),
            (center.togglePlayPauseCommand, .togglePlayPause),
            (center.nextTrackCommand, .next),
            (center.previousTrackCommand, .previous),
        ]
        for (remote, command) in commands {
            // The system does not promise which thread calls this.
            let handler: @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
                Task { @MainActor in self?.received(command) }
                return .success
            }
            targets.append((remote, remote.addTarget(handler: handler)))
        }
        log.note("remote: listening")
    }

    private func detach() {
        guard !targets.isEmpty else { return }
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        published = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        log.note("remote: stopped listening")
    }

    private func received(_ command: RunCommand) {
        log.note("remote: \(command)")
        onCommand(command)
    }

    private struct Card: Equatable {
        let session: Session
        let segment: SegmentID
        let isWaiting: Bool
    }
}
