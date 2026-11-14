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
    /// The schedule changes only when the session does, so it is built once per change and not on every tick.
    @ObservationIgnored private var schedule: CueSchedule?
    /// The paused session an interruption left behind. Only that exact session resumes when the interruption ends.
    @ObservationIgnored private var interrupted: Session?
    /// Receives every run once, when it is over. The history listens here.
    @ObservationIgnored var onRunOver: ((WorkoutRecord) -> Void)?
    /// When the run in progress started. nil once the run has been reported, so that finishing and
    /// then leaving the finish screen reports it once.
    @ObservationIgnored private var unreportedStart: Date?
    /// A number that every change to the run replaces. The button on the Live Activity carries the
    /// one its card was drawn with. A place in the workout would not do: the back button comes back
    /// to the same place, and so does the next workout. It starts at random, so that a card left by an
    /// earlier launch does not match either.
    @ObservationIgnored private var revision = Int.random(in: 0..<1_000_000_000)
    @ObservationIgnored private let player: CuePlayer
    @ObservationIgnored private let remote: HeadphoneRemote
    @ObservationIgnored private let liveActivity: LiveActivityController
    @ObservationIgnored let heartRate: HeartRateMonitor
    /// The heart rates of the run that has not been reported, taken while it ran and was not paused.
    @ObservationIgnored private var samples: [HeartRateSummary.Sample] = []
    @ObservationIgnored private var ticker: Timer?

    var liveActivityProblem: String? { liveActivity.problem }

    init(player: CuePlayer, remote: HeadphoneRemote, liveActivity: LiveActivityController, heartRate: HeartRateMonitor) {
        self.player = player
        self.remote = remote
        self.liveActivity = liveActivity
        self.heartRate = heartRate
        heartRate.onReading = { [weak self] in self?.keep($0) }
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
    func skip(_ segment: SegmentID) { change { $0?.skip(segment, at: .now) } }
    func forward(_ segment: SegmentID) { change { $0?.forward(segment, at: .now) } }
    func back(_ segment: SegmentID) { change { $0?.back(segment, at: .now) } }
    func end() {
        report()
        change { $0 = nil }
    }

    /// `Session.perform` decides what a press means, and a single press means Start or Next while the
    /// run waits.
    func handle(_ command: RunCommand) {
        change { $0?.perform(command, at: .now) }
    }

    /// A tap on Start or Next in the Live Activity. The card it came from can be out of date: the
    /// tap can come twice, after the run went back to the same wait, or after another workout has
    /// started. So it counts only while nothing has changed the run since that card was drawn, and
    /// then it is a headphone press. iOS may suspend the app once the intent returns, so this returns only when the card
    /// shows the change.
    func advance(fromWait revision: Int) async {
        guard revision == self.revision, case .active(let progress)? = session?.snapshot(at: .now),
              progress.isWaiting, !progress.isPaused else { return }
        handle(.play)
        await liveActivity.settle()
    }

    func prepare(_ workout: Workout, cues: CuePreferences) {
        player.prepare(Session(workout, cues: cues, startingAt: .now).vocabulary)
    }

    private func change(_ body: (inout Session?) -> Void) {
        revision &+= 1
        body(&session)
        schedule = session?.cueSchedule
        heartRate.need(.run, session != nil)
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

    private func tick() {
        reconcile()
        if unreportedStart != nil, case .finished? = session?.snapshot(at: .now) { report() }
    }

    private func report() {
        guard let session, let start = unreportedStart else { return }
        unreportedStart = nil
        let summary = HeartRateSummary(samples, maxHeartRate: heartRate.maxHeartRate)
        samples = []
        onRunOver?(WorkoutRecord(session, startedAt: start, endedAt: .now, heartRate: summary))
    }

    private func keep(_ reading: HeartRateReading) {
        guard unreportedStart != nil, let session, case .active(let progress) = session.snapshot(at: reading.date),
              !progress.isPaused else { return }
        samples.append(HeartRateSummary.Sample(reading, second: session.worked(at: reading.date)))
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
        let defaults = UserDefaults.standard
        let headphoneControls = defaults.bool(forKey: SettingsKey.headphoneControls)
        let strategy = defaults.string(forKey: SettingsKey.duckingStrategy).flatMap(DuckingStrategy.init) ?? .toggleOption
        player.sharing = headphoneControls ? .exclusive : .mixing(strategy)
        player.reconcile(CueDemand(for: session, playing: schedule, at: now), at: now)
        remote.reconcile(headphoneControls ? session : nil, at: now)
        let isActive = if case .active = session?.snapshot(at: now) { true } else { false }
        // A finished card has ended. A heart rate on it would start a new activity with each change.
        liveActivity.reconcile(session, at: now, revision: revision,
                               heartRate: isActive ? heartRate.display(at: now).map(RunActivityAttributes.HeartRate.init) : nil)

        let keepScreenOn = defaults.object(forKey: SettingsKey.keepScreenOn) as? Bool ?? true
        let stayAwake = keepScreenOn && isActive
        if UIApplication.shared.isIdleTimerDisabled != stayAwake {
            UIApplication.shared.isIdleTimerDisabled = stayAwake
        }
    }
}
