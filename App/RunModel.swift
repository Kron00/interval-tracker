import IntervalCore
import Observation
import UIKit

enum SettingsKey {
    static let keepScreenOn = "keepScreenOn"
    static let duckingStrategy = "duckingStrategy"
    static let headphoneControls = "headphoneControls"
}

@MainActor @Observable
final class RunModel {
    private(set) var session: Session?
    /// The session as it was before the last skip or restart, kept for a few seconds so a mis-press can be taken back.
    private(set) var undo: Session?

    @ObservationIgnored private var undoExpires = Date.distantPast
    /// The schedule changes only when the session does, so it is built once per change and not on every tick.
    @ObservationIgnored private var schedule: CueSchedule?
    /// The paused session an interruption left behind. Only that exact session resumes when the interruption ends.
    @ObservationIgnored private var interrupted: Session?
    @ObservationIgnored private let player: CuePlayer
    @ObservationIgnored private let remote: HeadphoneRemote
    @ObservationIgnored private var ticker: Timer?

    init(player: CuePlayer, remote: HeadphoneRemote) {
        self.player = player
        self.remote = remote
        remote.onCommand = { [weak self] in self?.handle($0) }
        player.onInterrupted = { [weak self] in self?.interruptionBegan() }
        player.onInterruptionEnded = { [weak self] in self?.interruptionEnded() }
    }

    func start(_ workout: Workout, cues: CuePreferences) {
        change { $0 = Session(workout, cues: cues, startingAt: .now) }
    }
    func pause() { change { $0?.pause(at: .now) } }
    func resume() { change { $0?.resume(at: .now) } }
    func skip(_ segment: SegmentID) { jump { $0?.skip(segment, at: .now) } }
    func restart(_ segment: SegmentID) { jump { $0?.restart(segment, at: .now) } }

    /// A how-to video plays in another app and can run for minutes. The run goes back to the start of
    /// the stretch's lead-in and waits there, so Resume gives the whole get-ready time and says the name again.
    func pauseForHowTo(_ segment: SegmentID) {
        change {
            $0?.restart(segment, at: .now)
            $0?.pause(at: .now)
        }
    }

    /// Restores the session the skip or restart changed, so the run is where it would be had the button never been pressed.
    func undoLast() {
        guard let undo else { return }
        change { $0 = undo }
    }
    func end() { change { $0 = nil } }

    func handle(_ command: RunCommand) {
        switch command {
        case .next, .previous: jump { $0?.perform(command, at: .now) }
        case .play, .pause, .togglePlayPause: change { $0?.perform(command, at: .now) }
        }
    }

    func prepare(_ workout: Workout, cues: CuePreferences) {
        player.prepare(Session(workout, cues: cues, startingAt: .now).vocabulary)
    }

    private static let undoWindow: TimeInterval = 6

    private func jump(_ body: (inout Session?) -> Void) {
        let before = session
        change(body)
        if session != before {
            undo = before
            undoExpires = Date.now.addingTimeInterval(Self.undoWindow)
        }
    }

    private func change(_ body: (inout Session?) -> Void) {
        undo = nil
        body(&session)
        schedule = session?.cueSchedule
        if session == nil {
            ticker?.invalidate()
            ticker = nil
        } else if ticker == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
        reconcile()
    }

    private func interruptionBegan() {
        guard let session, !session.isPaused else { return }
        pause()
        interrupted = self.session
    }

    private func interruptionEnded() {
        guard session != nil, session == interrupted else { return }
        resume()
    }

    private func reconcile() {
        let now = Date.now
        if undo != nil, now >= undoExpires { undo = nil }
        let defaults = UserDefaults.standard
        let headphoneControls = defaults.bool(forKey: SettingsKey.headphoneControls)
        let strategy = defaults.string(forKey: SettingsKey.duckingStrategy).flatMap(DuckingStrategy.init) ?? .toggleOption
        player.sharing = headphoneControls ? .exclusive : .mixing(strategy)
        player.reconcile(CueDemand(for: session, playing: schedule, at: now), at: now)
        remote.reconcile(headphoneControls ? session : nil, at: now)

        let keepScreenOn = defaults.object(forKey: SettingsKey.keepScreenOn) as? Bool ?? true
        let isActive = if case .active = session?.snapshot(at: now) { true } else { false }
        let stayAwake = keepScreenOn && isActive
        if UIApplication.shared.isIdleTimerDisabled != stayAwake {
            UIApplication.shared.isIdleTimerDisabled = stayAwake
        }
    }
}
