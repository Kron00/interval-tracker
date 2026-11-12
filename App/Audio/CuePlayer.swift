import AVFoundation
import IntervalCore

enum DuckingStrategy: String, CaseIterable, Sendable {
    case toggleOption
    case cycleSession
    case wholeRun
}

@MainActor
final class CuePlayer {
    var strategy: DuckingStrategy = .toggleOption

    private let bank: SoundBank
    private let log: AudioLog

    private var graph: Graph?
    private var scheduled: CueSchedule?
    private var appliedDuck: Bool?
    private var voiceStale = false
    private var sessionActive = false
    private var retryAfter = Date.distantPast
    private var lastFailure: String?

    init(bank: SoundBank, log: AudioLog) {
        self.bank = bank
        self.log = log
        for disturbance in Disturbance.allCases {
            _ = NotificationCenter.default.addObserver(forName: disturbance.notification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.disturbed(by: disturbance) }
            }
        }
    }

    func reconcile(_ schedule: CueSchedule?, at now: Date) {
        guard let schedule, case let todo = schedule.remaining(after: now), !todo.isEmpty else {
            teardown()
            if log.cuesAreSilent { log.cuesAreSilent = false }
            return
        }
        guard now >= retryAfter else { return }
        let wantDuck = strategy == .wholeRun || todo.isDucked(at: now)

        do {
            if graph?.engine.isRunning != true {
                try bringUp(ducked: wantDuck)
            }
            if appliedDuck != wantDuck {
                try setDucked(wantDuck)
            }
            guard let graph else { return }

            if scheduled != schedule {
                queue(todo, on: graph, voiceOnly: false)
                scheduled = schedule
                voiceStale = false
                prepare(todo.vocabulary)
            } else if voiceStale, !todo.isDucked(at: now) {
                queue(todo, on: graph, voiceOnly: true)
                voiceStale = false
            }
            lastFailure = nil
            if log.cuesAreSilent { log.cuesAreSilent = false }
        } catch {
            let line = "audio failed: \(error.localizedDescription)"
            if line != lastFailure { log.note(line) }
            lastFailure = line
            log.cuesAreSilent = true
            retryAfter = now.addingTimeInterval(1)
        }
    }

    func prepare(_ vocabulary: Set<Sound>) {
        Task {
            if await bank.prepare(vocabulary) { voiceStale = true }
        }
    }

    private func bringUp(ducked: Bool) throws {
        graph = nil
        scheduled = nil
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: Self.options(ducked: ducked))
        try session.setActive(true)
        sessionActive = true
        appliedDuck = ducked

        let fresh = try Graph(format: bank.format)
        try fresh.engine.start()
        fresh.bed.scheduleBuffer(bank.silence, at: nil, options: .loops, completionHandler: nil)
        fresh.bed.play()
        graph = fresh
        log.note("audio up, \(ducked ? "ducked" : "not ducked"), \(strategy.rawValue)")
    }

    private func setDucked(_ ducked: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if strategy == .cycleSession, !ducked {
            graph?.engine.stop()
            graph = nil
            scheduled = nil
            appliedDuck = nil
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } else {
            try session.setCategory(.playback, mode: .default, options: Self.options(ducked: ducked))
            try session.setActive(true)
            appliedDuck = ducked
        }
        log.note("duck \(ducked ? "on" : "off") via \(strategy.rawValue)")
    }

    private func teardown() {
        guard sessionActive || graph != nil else { return }
        graph?.engine.stop()
        graph = nil
        scheduled = nil
        appliedDuck = nil
        voiceStale = false
        sessionActive = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            log.note("audio down, music released")
        } catch {
            try? session.setCategory(.playback, mode: .default, options: Self.options(ducked: false))
            log.note("release failed, duck option removed instead: \(error.localizedDescription)")
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

    private func disturbed(by disturbance: Disturbance) {
        let running = graph?.engine.isRunning == true
        // Our own duck toggle posts a route change. Resetting then would cut the cue that is sounding.
        guard disturbance.alwaysResets || !running else { return }
        guard graph != nil || scheduled != nil else { return }
        log.note("\(disturbance.rawValue), engine \(running ? "running" : "stopped"), rebuilding")
        if disturbance == .mediaServicesReset { graph = nil }
        scheduled = nil
        appliedDuck = nil
    }

    private static func options(ducked: Bool) -> AVAudioSession.CategoryOptions {
        ducked ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
    }

    private static let hostTicksPerSecond: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)
    }()
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
