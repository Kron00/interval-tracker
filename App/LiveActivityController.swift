import ActivityKit
import Foundation
import IntervalCore
import Observation

extension RunActivityAttributes: ActivityAttributes {}

extension RunActivityAttributes.ContentState {
    /// What the Live Activity shows for `session` at `now`. The value is the same for every `now`
    /// inside one phase, so comparing it with the last one tells whether anything has to be sent.
    /// `revision` is what the button of a waiting run hands back with its tap.
    init(_ session: Session, at now: Date, revision: Int = 0) {
        let snapshot = session.snapshot(at: now)
        switch snapshot {
        case .finished(let worked):
            self.init(title: "Workout complete", caption: nil, upNext: nil, tone: RunTone(snapshot),
                      clock: .finished(ClockText.remaining(worked)), isHeadsUp: false)
        case .active(let progress):
            let clock: RunActivityAttributes.Clock
            if let end = session.phaseEnd(at: now) {
                clock = .counting(from: end - progress.phaseDuration, to: end)
            } else {
                let face = progress.awaited ?? ClockText.remaining(progress.phaseRemaining)
                clock = progress.isPaused
                    ? .paused(face)
                    : .waiting(face, for: progress.phase.pendingHold == nil ? .next : .start, wait: revision)
            }
            self.init(title: progress.phase.title, caption: progress.phase.caption, upNext: progress.upNextText,
                      tone: RunTone(snapshot), clock: clock, isHeadsUp: progress.isHeadsUp)
        }
    }
}

struct RunActivityCard: Equatable {
    let name: String
    let state: RunActivityAttributes.ContentState

    /// Whether the heart rate is all that changed, and it stayed in its zone.
    func differsOnlyInBeats(from other: RunActivityCard) -> Bool {
        var unchanged = state
        unchanged.heartRate = other.state.heartRate
        return name == other.name && unchanged == other.state
            && (state.heartRate == nil) == (other.state.heartRate == nil) && state.heartRate?.zone == other.state.heartRate?.zone
    }
}

/// Where a card goes. ActivityKit in the app, a recorder in the tests.
@MainActor
protocol RunActivityDisplay: AnyObject {
    /// False while the user has Live Activities turned off for the app.
    var isAllowed: Bool { get }
    /// `alerting` lights the lock screen and expands the Dynamic Island.
    func show(_ card: RunActivityCard, alerting: Bool) async throws
    func clear() async
}

/// Shows the run on the lock screen and in the Dynamic Island. It is level-triggered like
/// `CuePlayer`: `reconcile` is told what the run is now, and sends something only when what the
/// Live Activity shows would change. The system ticks the countdown, so that is once per phase or
/// state, never once a second.
@MainActor @Observable
final class LiveActivityController {
    /// Why no Live Activity shows, in one line. nil while nothing is wrong.
    var problem: String? {
        display.isAllowed ? refusal : "Live Activities are turned off for Intervals in the Settings app."
    }

    static let heartRateInterval: TimeInterval = 5

    private var refusal: String?
    @ObservationIgnored private let display: any RunActivityDisplay
    @ObservationIgnored private let log: AudioLog
    @ObservationIgnored private var wanted: RunActivityCard?
    @ObservationIgnored private var wantedAt = Date.distantPast
    @ObservationIgnored private var shown: RunActivityCard?
    /// The one task that talks to the display. Updates are async, and a second task could overtake the first.
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var lastNote: String?
    /// The end of the phase whose heads-up last alerted. A skip and its Undo come back into the
    /// same heads-up after the voice has spoken, and the card must not alert a second time.
    @ObservationIgnored private var alertedPhaseEnd: Date?

    init(display: any RunActivityDisplay, log: AudioLog) {
        self.display = display
        self.log = log
        // A crash or a force quit leaves the run's activity on the lock screen, counting down to zero.
        worker = Task {
            await display.clear()
            await catchUp()
        }
    }

    convenience init(log: AudioLog) {
        self.init(display: SystemActivityDisplay(), log: log)
    }

    /// `heartRate` changes every second, and iOS limits how often a Live Activity may be updated. So
    /// a change of the heart rate alone waits until `heartRateInterval` after the last card, and a
    /// change of zone does not wait.
    func reconcile(_ session: Session?, at now: Date, revision: Int = 0, heartRate: RunActivityAttributes.HeartRate? = nil) {
        let card = session.map { session in
            var state = RunActivityAttributes.ContentState(session, at: now, revision: revision)
            state.heartRate = heartRate
            return RunActivityCard(name: session.workout.name, state: state)
        }
        guard card != wanted else { return }
        if let card, let wanted, card.differsOnlyInBeats(from: wanted), now < wantedAt + Self.heartRateInterval { return }
        wanted = card
        wantedAt = now
        if worker == nil {
            worker = Task { await catchUp() }
        }
    }

    /// Returns once the display shows the newest card.
    func settle() async {
        while let worker { await worker.value }
    }

    /// Shows the newest card each time round, so a change that arrives during an update is neither
    /// lost nor shown out of order, and one that was replaced in the meantime is skipped.
    private func catchUp() async {
        while shown != wanted {
            let next = wanted
            await show(next)
            shown = next
        }
        worker = nil
    }

    private func show(_ card: RunActivityCard?) async {
        guard let card else {
            await display.clear()
            return
        }
        guard display.isAllowed else {
            note("live activity: turned off in Settings")
            return
        }
        var alerting = false
        if card.state.isHeadsUp, case .counting(_, let end) = card.state.clock {
            alerting = shown?.state.isHeadsUp != true && end != alertedPhaseEnd
            // A resume inside the heads-up moves the end of the phase. It is still the heads-up
            // that alerted, so the new end is the one to remember.
            alertedPhaseEnd = end
        }
        do {
            try await display.show(card, alerting: alerting)
            refusal = nil
            lastNote = nil
        } catch {
            refusal = "The Live Activity could not start: \(error.localizedDescription)"
            note("live activity failed: \(error.localizedDescription)")
        }
    }

    private func note(_ line: String) {
        if line != lastNote { log.note(line) }
        lastNote = line
    }
}

@MainActor
private final class SystemActivityDisplay: RunActivityDisplay {
    private var activity: Activity<RunActivityAttributes>?
    /// A finished workout's activity is ended and left on the lock screen for a while. It takes no more updates.
    private var hasEnded = false

    private static let lingerAfterFinish: TimeInterval = 120
    /// The alert lights the screen while the voice says "Get ready". The system's alert sound would
    /// play over the voice, and an alert cannot be given no sound, so it is given a silent one.
    private static let silence = AlertConfiguration.AlertSound.named("HeadsUpSilence.wav")

    var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func show(_ card: RunActivityCard, alerting: Bool) async throws {
        if let activity, hasEnded || activity.attributes.workoutName != card.name {
            await clear()
        }
        let content = ActivityContent(state: card.state, staleDate: nil)
        if let activity {
            let alert = alerting
                ? AlertConfiguration(title: "Get ready", body: "Up next: \(card.state.upNext ?? "Work")", sound: Self.silence) : nil
            await activity.update(content, alertConfiguration: alert)
        } else {
            activity = try Activity.request(
                attributes: RunActivityAttributes(workoutName: card.name), content: content, pushType: nil)
        }
        if case .finished = card.state.clock, let activity {
            await activity.end(content, dismissalPolicy: .after(.now + Self.lingerAfterFinish))
            hasEnded = true
        }
    }

    /// Ends every activity of this app, not only the one it holds, so one left by an earlier launch goes too.
    func clear() async {
        for activity in Activity<RunActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        hasEnded = false
    }
}
