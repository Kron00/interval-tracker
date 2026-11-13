import AVFoundation
import IntervalCore

enum DuckingStrategy: String, CaseIterable, Sendable {
    case toggleOption
    case cycleSession
    case wholeRun
}

enum Sharing: Equatable {
    case mixing(DuckingStrategy)
    /// Other audio stops. iOS sends headphone presses only to an app whose audio does not mix.
    case exclusive
}

enum CueDemand: Equatable {
    case none
    /// The run is on but has nothing to play. It is paused, or it waits for Next.
    case standby
    case playing(CueSchedule)

    /// `schedule` is the session's own. It is passed in so that it is built once per change of the
    /// session and not on every tick.
    init(for session: Session?, playing schedule: CueSchedule?, at now: Date) {
        guard let session else {
            self = .none
            return
        }
        guard let schedule else {
            self = .standby
            return
        }
        // A wait begins on a tone, so it has something to play until that tone has sounded.
        if let end = schedule.end, end <= now, case .active(let progress) = session.snapshot(at: now), progress.isWaiting {
            self = .standby
        } else {
            self = .playing(schedule)
        }
    }
}

@MainActor
final class CuePlayer {
    var sharing = Sharing.mixing(.toggleOption) {
        didSet {
            // A session cannot change between mixing and exclusive while it is live.
            if (sharing == .exclusive) != (oldValue == .exclusive) { teardown() }
        }
    }
    /// Called in exclusive mode when a call or another app takes the audio.
    var onInterrupted: () -> Void = {}
    /// Called in exclusive mode when that interruption is over and the system says playback may carry on.
    var onInterruptionEnded: () -> Void = {}

    /// An exclusive run on standby holds the audio this long so a press can reach it on a locked phone.
    /// After that the audio is released, and iOS may suspend the app.
    static let standbyLimit: TimeInterval = 15 * 60

    private let bank: SoundBank
    private let log: AudioLog

    private var graph: Graph?
    private var scheduled: CueSchedule?
    private var applied: Mix?
    private var hold = Hold.none
    private var voiceStale = false
    private var sessionActive = false
    private var retryAfter = Date.distantPast
    private var lastFailure: String?

    init(bank: SoundBank, log: AudioLog) {
        self.bank = bank
        self.log = log
        for disturbance in Disturbance.allCases {
            _ = NotificationCenter.default.addObserver(forName: disturbance.notification, object: nil, queue: .main) { [weak self] note in
                let interruption = Interruption(note)
                Task { @MainActor in self?.disturbed(by: disturbance, interruption) }
            }
        }
    }

    func reconcile(_ demand: CueDemand, at now: Date) {
        switch demand {
        case .playing(let schedule):
            hold = .none
            if let end = schedule.end, end > now { play(schedule, at: now) } else { rest() }
        case .standby where sharing == .exclusive:
            switch hold {
            case .yielded:
                rest()
            case .none:
                hold = .standby(since: now)
                standBy(at: now)
            case .standby(let since):
                if now.timeIntervalSince(since) < Self.standbyLimit { standBy(at: now) } else { rest() }
            }
        case .standby, .none:
            hold = .none
            rest()
        }
    }

    func prepare(_ vocabulary: [Sound]) {
        Task {
            if await bank.prepare(vocabulary) { voiceStale = true }
        }
    }

    private func play(_ schedule: CueSchedule, at now: Date) {
        guard now >= retryAfter else { return }
        let want = mix(for: schedule, at: now)

        // Nine ticks in ten change nothing. Comparing a schedule with the copy stored from it is a
        // pointer check, so this path allocates nothing.
        if graph?.engine.isRunning == true, applied == want, scheduled == schedule, !voiceStale {
            return
        }
        let todo = schedule.remaining(after: now)

        do {
            if graph?.engine.isRunning != true {
                try bringUp(want)
            }
            if applied != want {
                try apply(want)
            }
            guard let graph else { return }

            if scheduled != schedule {
                queue(todo, on: graph, voiceOnly: false)
                scheduled = schedule
                voiceStale = false
                prepare(todo.vocabulary)
            } else if voiceStale, !Self.voiceIsSounding(in: schedule, at: now) {
                queue(todo, on: graph, voiceOnly: true)
                voiceStale = false
            }
            succeeded()
        } catch {
            failed(error, at: now)
        }
    }

    /// Keeps the session, the engine and the silent bed, with no cue queued. The app stays awake and
    /// stays the Now Playing app, so a press on a locked phone still reaches it.
    private func standBy(at now: Date) {
        guard now >= retryAfter else { return }
        if graph?.engine.isRunning == true, applied == .exclusive, scheduled == nil { return }

        do {
            if graph?.engine.isRunning != true {
                try bringUp(.exclusive)
            } else if applied != .exclusive {
                try apply(.exclusive)
            }
            if scheduled != nil, let graph {
                graph.beeper.stop()
                graph.speaker.stop()
                scheduled = nil
                voiceStale = false
                log.note("standby, cues stopped")
            }
            succeeded()
        } catch {
            failed(error, at: now)
        }
    }

    private func rest() {
        teardown()
        if log.cuesAreSilent { log.cuesAreSilent = false }
    }

    private func succeeded() {
        lastFailure = nil
        if log.cuesAreSilent { log.cuesAreSilent = false }
    }

    private func failed(_ error: any Error, at now: Date) {
        let line = "audio failed: \(error.localizedDescription)"
        if line != lastFailure { log.note(line) }
        lastFailure = line
        log.cuesAreSilent = true
        retryAfter = now.addingTimeInterval(1)
    }

    private func mix(for schedule: CueSchedule, at now: Date) -> Mix {
        switch sharing {
        case .exclusive: .exclusive
        case .mixing(let strategy): .mixing(ducked: strategy == .wholeRun || schedule.isDucked(at: now))
        }
    }

    private func bringUp(_ mix: Mix) throws {
        graph = nil
        scheduled = nil
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: mix.options)
        try session.setActive(true)
        sessionActive = true
        applied = mix

        let fresh = try Graph(format: bank.format)
        try fresh.engine.start()
        fresh.bed.scheduleBuffer(bank.silence, at: nil, options: .loops, completionHandler: nil)
        fresh.bed.play()
        graph = fresh
        log.note("audio up, \(describe(mix))")
    }

    private func apply(_ mix: Mix) throws {
        let session = AVAudioSession.sharedInstance()
        if mix == .mixing(ducked: false), sharing == .mixing(.cycleSession) {
            graph?.engine.stop()
            graph = nil
            scheduled = nil
            applied = nil
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } else {
            try session.setCategory(.playback, mode: .default, options: mix.options)
            try session.setActive(true)
            applied = mix
        }
        log.note("audio set to \(describe(mix))")
    }

    private func describe(_ mix: Mix) -> String {
        switch (mix, sharing) {
        case (.mixing(let ducked), .mixing(let strategy)): "\(ducked ? "ducked" : "not ducked"), \(strategy.rawValue)"
        default: "exclusive"
        }
    }

    private func teardown() {
        guard sessionActive || graph != nil else { return }
        graph?.engine.stop()
        graph = nil
        scheduled = nil
        applied = nil
        voiceStale = false
        sessionActive = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            log.note("audio down, music released")
        } catch {
            try? session.setCategory(.playback, mode: .default, options: Mix.mixing(ducked: false).options)
            log.note("release failed, duck option removed instead: \(error.localizedDescription)")
        }
    }

    /// Queueing late voices restarts the speaker node, which would cut a phrase in mid-word. Waiting
    /// for the music to come back up was too long a wait: back-to-back short phases never un-duck.
    static func voiceIsSounding(in schedule: CueSchedule, at now: Date) -> Bool {
        schedule.windows.contains { window in
            window.start <= now && now < window.end && window.sounds.contains { timed in
                guard case .voice = timed.sound else { return false }
                return timed.at <= now && now < timed.at.addingTimeInterval(timed.sound.slot)
            }
        }
    }

    private func queue(_ todo: CueSchedule, on graph: Graph, voiceOnly: Bool) {
        graph.speaker.stop()
        graph.speaker.play()
        if !voiceOnly {
            graph.beeper.stop()
            graph.beeper.play()
        }

        let now = Date.now
        let hostNow = mach_absolute_time()
        var count = 0
        for timed in todo.windows.flatMap(\.sounds) {
            let isVoice = if case .voice = timed.sound { true } else { false }
            guard isVoice || !voiceOnly, let buffer = bank[timed.sound] else { continue }
            // A cue that is due now still needs a moment to reach the render thread, or its start is clipped.
            let delay = max(0.03, timed.at.timeIntervalSince(now))
            let when = AVAudioTime(hostTime: hostNow + UInt64(delay * Self.hostTicksPerSecond))
            (isVoice ? graph.speaker : graph.beeper).scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
            count += 1
        }
        log.note("queued \(count) \(voiceOnly ? "voice cues" : "cues")")
    }

    private func disturbed(by disturbance: Disturbance, _ interruption: Interruption?) {
        if sharing == .exclusive, let interruption {
            yield(to: interruption)
            return
        }
        let running = graph?.engine.isRunning == true
        // Our own duck toggle posts a route change. Resetting then would cut the cue that is sounding.
        guard disturbance.alwaysResets || !running else { return }
        guard graph != nil || scheduled != nil else { return }
        log.note("\(disturbance.rawValue), engine \(running ? "running" : "stopped"), rebuilding")
        if disturbance == .mediaServicesReset { graph = nil }
        scheduled = nil
        applied = nil
    }

    /// Mixing rebuilds its audio after an interruption. Exclusive must not, because starting again
    /// would stop the call, or the music the user just started in another app.
    private func yield(to interruption: Interruption) {
        switch interruption {
        case .began:
            guard sessionActive else { return }
            log.note("interrupted, audio given up until resumed")
            hold = .yielded
            onInterrupted()
        case .ended(let shouldResume):
            guard hold == .yielded else { return }
            log.note("interruption ended, \(shouldResume ? "resuming" : "waiting for resume")")
            guard shouldResume else { return }
            hold = .none
            onInterruptionEnded()
        }
    }

    private static let hostTicksPerSecond: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)
    }()
}

private enum Mix: Equatable {
    case mixing(ducked: Bool)
    case exclusive

    var options: AVAudioSession.CategoryOptions {
        switch self {
        case .mixing(ducked: true): [.mixWithOthers, .duckOthers]
        case .mixing(ducked: false): [.mixWithOthers]
        case .exclusive: []
        }
    }
}

private enum Hold: Equatable {
    case none
    case standby(since: Date)
    /// Interrupted. Audio stays down until the run plays again.
    case yielded
}

private enum Interruption: Sendable {
    case began
    case ended(shouldResume: Bool)

    init?(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            self = .began
        case .ended:
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            self = .ended(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
}

private enum Disturbance: String, CaseIterable {
    case interruption
    case routeChange = "route change"
    case mediaServicesReset = "media services reset"
    case engineConfigurationChange = "engine configuration change"

    var notification: Notification.Name {
        switch self {
        case .interruption: AVAudioSession.interruptionNotification
        case .routeChange: AVAudioSession.routeChangeNotification
        case .mediaServicesReset: AVAudioSession.mediaServicesWereResetNotification
        case .engineConfigurationChange: .AVAudioEngineConfigurationChange
        }
    }

    var alwaysResets: Bool {
        switch self {
        case .interruption, .mediaServicesReset: true
        case .routeChange, .engineConfigurationChange: false
        }
    }
}

private struct Graph {
    let engine = AVAudioEngine()
    let beeper = AVAudioPlayerNode()
    let speaker = AVAudioPlayerNode()
    /// Loops silence so the output always has a playing node, which is what holds the background audio mode.
    let bed = AVAudioPlayerNode()

    init(format: AVAudioFormat) throws {
        // Connecting to an output with no channels raises an Objective-C exception, which Swift cannot catch.
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        guard hardware.channelCount > 0, hardware.sampleRate > 0 else { throw NoAudioOutput() }
        for node in [beeper, speaker, bed] {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }
}

private struct NoAudioOutput: LocalizedError {
    var errorDescription: String? { "no audio output available" }
}
