import Foundation

public struct Session: Equatable, Sendable {
    private enum Clock: Equatable, Sendable {
        case running(zeroAt: Date)
        case paused(elapsed: TimeInterval)
    }

    public let definition: TimerDefinition
    private let timeline: Timeline
    private let cues: CuePreferences
    private var clock: Clock
    private var skipped: TimeInterval = 0

    public init(_ definition: TimerDefinition, cues: CuePreferences, startingAt now: Date) {
        self.definition = definition
        self.timeline = Timeline(definition)
        self.cues = cues
        self.clock = .running(zeroAt: now)
    }

    public mutating func pause(at now: Date) {
        clock = .paused(elapsed: elapsed(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let elapsed) = clock else { return }
        clock = .running(zeroAt: now - elapsed)
    }

    /// Ends `segment` now. No-op unless `segment` is the one in progress at `now`.
    public mutating func skip(_ segment: SegmentID, at now: Date) {
        let elapsed = elapsed(at: now)
        guard let current = timeline.segment(at: elapsed), current.id == segment else { return }
        skipped += current.end - elapsed
        switch clock {
        case .running: clock = .running(zeroAt: now - current.end)
        case .paused: clock = .paused(elapsed: current.end)
        }
    }

    public func snapshot(at now: Date) -> Snapshot {
        let elapsed = elapsed(at: now)
        guard let current = timeline.segment(at: elapsed) else {
            return .finished(worked: timeline.total - skipped)
        }
        return .active(RunProgress(
            segment: current.id, phase: current.phase,
            phaseRemaining: current.end - elapsed, phaseDuration: current.duration,
            totalRemaining: timeline.total - elapsed, totalDuration: timeline.total,
            upNext: timeline.segment(after: current.id).map { Upcoming(phase: $0.phase, duration: $0.duration) },
            isPaused: isPaused))
    }

    /// Every cue of this run at its wall-clock time. nil while paused.
    public var cueSchedule: CueSchedule? {
        switch clock {
        case .running(let zeroAt): CueSchedule(timeline, cues, zeroAt: zeroAt)
        case .paused: nil
        }
    }

    private var isPaused: Bool {
        if case .paused = clock { true } else { false }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        switch clock {
        case .running(let zeroAt): min(max(now.timeIntervalSince(zeroAt), 0), timeline.total)
        case .paused(let elapsed): elapsed
        }
    }
}

public enum Snapshot: Equatable, Sendable {
    case active(RunProgress)
    /// `worked` is the timer's length minus whatever was skipped. Paused time never counts.
    case finished(worked: TimeInterval)
}

public struct RunProgress: Equatable, Sendable {
    public let segment: SegmentID
    public let phase: Phase
    public let phaseRemaining: TimeInterval
    public let phaseDuration: TimeInterval
    public let totalRemaining: TimeInterval
    public let totalDuration: TimeInterval
    public let upNext: Upcoming?
    public let isPaused: Bool
}

public struct Upcoming: Equatable, Sendable {
    public let phase: Phase
    public let duration: TimeInterval
}

public enum ClockText {
    /// Rounds UP to whole seconds: a fresh 4:00 phase reads "4:00" and an active phase never reads "0:00".
    /// "m:ss" below one hour, "h:mm:ss" from one hour.
    public static func remaining(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.up))
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
