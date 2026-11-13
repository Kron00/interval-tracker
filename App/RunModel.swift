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
    /// Receives every run once, when it is over. The history listens here.
    @ObservationIgnored var onRunOver: ((WorkoutRecord) -> Void)?
    /// When the run in progress started. nil once the run has been reported, so that finishing and
    /// then leaving the finish screen reports it once.
    @ObservationIgnored private var unreportedStart: Date?
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
        report()
        change { $0 = Session(workout, cues: cues, startingAt: .now) }
        unreportedStart = .now
    }
    func pause() { change { $0?.pause(at: .now) } }
    func resume() { change { $0?.resume(at: .now) } }
    func skip(_ segment: SegmentID) { jump { $0?.skip(segment, at: .now) } }
    func restart(_ segment: SegmentID) { jump { $0?.restart(segment, at: .now) } }

    /// Restores the session the skip or restart changed, so the run is where it would be had the button never been pressed.
    func undoLast() {
        guard let undo else { return }
        change { $0 = undo }
    }
    func end() {
        report()
        change { $0 = nil }
    }

    /// `Session.perform` decides what a press means, and a single press means Start or Next while the
    /// run waits. So Undo goes by what the press did. A press that moved the run and left it paused or
    /// running as before can be taken back. A pause or a resume cannot.
    func handle(_ command: RunCommand) {
        let before = session
        change { $0?.perform(command, at: .now) }
        if session != before, session?.isPaused == before?.isPaused { offerUndo(of: before) }
    }

    func prepare(_ workout: Workout, cues: CuePreferences) {
        player.prepare(Session(workout, cues: cues, startingAt: .now).vocabulary)
    }

    /// Six seconds, unless a UI test passes `-undoWindow <seconds>`. On a slow CI machine the test
    /// runner can take ten seconds to hand control back after a tap, and the chip was gone by then.
    private static let undoWindow: TimeInterval = {
        let requested = UserDefaults.standard.double(forKey: "undoWindow")
        return requested > 0 ? requested : 6
    }()

    private func jump(_ body: (inout Session?) -> Void) {
        let before = session
        change(body)
        if session != before { offerUndo(of: before) }
    }

    private func offerUndo(of before: Session?) {
        undo = before
        undoExpires = Date.now.addingTimeInterval(Self.undoWindow)
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
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
        reconcile()
    }

    /// A workout that a skip finished can be brought back with Undo, so it is not over until Undo
    /// is gone. Only a tick checks. `change` clears `undo` before a skip offers it again, and a check
    /// in between would report a run that Undo can still bring back.
    private func tick() {
        reconcile()
        if unreportedStart != nil, undo == nil, case .finished? = session?.snapshot(at: .now) { report() }
    }

    private func report() {
        guard let session, let start = unreportedStart else { return }
        unreportedStart = nil
        onRunOver?(WorkoutRecord(session, startedAt: start, endedAt: .now))
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
