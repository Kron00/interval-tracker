import IntervalCore
import Observation
import UIKit

enum SettingsKey {
    static let keepScreenOn = "keepScreenOn"
    static let duckingStrategy = "duckingStrategy"
}

@MainActor @Observable
final class RunModel {
    private(set) var session: Session?
    /// The session as it was before the last skip, kept for a few seconds so a mis-tap can be taken back.
    private(set) var beforeSkip: Session?

    @ObservationIgnored private var undoExpires = Date.distantPast
    /// The schedule changes only when the session does, so it is built once per change and not on every tick.
    @ObservationIgnored private var schedule: CueSchedule?
    @ObservationIgnored private let player: CuePlayer
    @ObservationIgnored private var ticker: Timer?

    init(player: CuePlayer) { self.player = player }

    func start(_ timer: TimerDefinition, cues: CuePreferences) {
        change { $0 = Session(timer, cues: cues, startingAt: .now) }
    }
    func pause() { change { $0?.pause(at: .now) } }
    func resume() { change { $0?.resume(at: .now) } }
    func skip(_ segment: SegmentID) {
        let before = session
        change { $0?.skip(segment, at: .now) }
        if session != before {
            beforeSkip = before
            undoExpires = Date.now.addingTimeInterval(Self.undoWindow)
        }
    }

    /// Restores the anchor the skip moved, so the run is where it would be had Skip never been tapped.
    func undoSkip() {
        guard let beforeSkip else { return }
        change { $0 = beforeSkip }
    }
    func end() { change { $0 = nil } }

    func prepare(_ timer: TimerDefinition, cues: CuePreferences) {
        let schedule = Session(timer, cues: cues, startingAt: .now).cueSchedule
        player.prepare(schedule?.vocabulary ?? [])
    }

    private static let undoWindow: TimeInterval = 6

    private func change(_ body: (inout Session?) -> Void) {
        beforeSkip = nil
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

    private func reconcile() {
        let now = Date.now
        if beforeSkip != nil, now >= undoExpires { beforeSkip = nil }
        let defaults = UserDefaults.standard
        player.strategy = defaults.string(forKey: SettingsKey.duckingStrategy).flatMap(DuckingStrategy.init) ?? .toggleOption
        player.reconcile(schedule, at: now)

        let keepScreenOn = defaults.object(forKey: SettingsKey.keepScreenOn) as? Bool ?? true
        let isActive = if case .active = session?.snapshot(at: now) { true } else { false }
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isActive
    }
}
