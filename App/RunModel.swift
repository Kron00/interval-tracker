import IntervalCore
import Observation
import UIKit

enum SettingsKey {
    static let keepScreenOn = "keepScreenOn"
    static let duckingStrategy = "duckingStrategy"
}

/// The only writer of the session. Audio and the idle timer are derived from it on every intent
/// and ten times a second, so nothing has to remember to notify anything.
@MainActor @Observable
final class RunModel {
    private(set) var session: Session?

    @ObservationIgnored private let player: CuePlayer
    @ObservationIgnored private var ticker: Timer?

    init(player: CuePlayer) { self.player = player }

    func start(_ timer: TimerDefinition, cues: CuePreferences) {
        change { $0 = Session(timer, cues: cues, startingAt: .now) }
    }
    func pause() { change { $0?.pause(at: .now) } }
    func resume() { change { $0?.resume(at: .now) } }
    func skip(_ segment: SegmentID) { change { $0?.skip(segment, at: .now) } }
    func end() { change { $0 = nil } }

    /// Renders a timer's voice phrases before Start is tapped, so the first announcement is ready.
    func prepare(_ timer: TimerDefinition, cues: CuePreferences) {
        let schedule = Session(timer, cues: cues, startingAt: .now).cueSchedule
        player.prepare(schedule?.vocabulary ?? [])
    }

    private func change(_ body: (inout Session?) -> Void) {
        body(&session)
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
        let defaults = UserDefaults.standard
        player.strategy = defaults.string(forKey: SettingsKey.duckingStrategy).flatMap(DuckingStrategy.init) ?? .toggleOption
        player.reconcile(session?.cueSchedule, at: now)

        let keepScreenOn = defaults.object(forKey: SettingsKey.keepScreenOn) as? Bool ?? true
        let isActive = if case .active = session?.snapshot(at: now) { true } else { false }
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isActive
    }
}
