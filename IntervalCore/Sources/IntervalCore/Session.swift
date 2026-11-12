import Foundation

/// What a headphone press or a lock-screen button asks of a run.
public enum RunCommand: Hashable, Sendable {
    case play, pause, togglePlayPause
    /// Skips the segment in progress.
    case next
    /// Restarts the segment in progress.
    case previous
}

public struct Session: Equatable, Sendable {
    private enum Clock: Equatable, Sendable {
        case running(zeroAt: Date)
        case paused(elapsed: TimeInterval)
    }

    public let workout: Workout
    private let timeline: Timeline
    private let cues: CuePreferences
    private var clock: Clock
    private var skipped: TimeInterval = 0
    private var repeated: TimeInterval = 0

    public init(_ workout: Workout, cues: CuePreferences, startingAt now: Date) {
        self.workout = workout
        self.timeline = Timeline(workout.plan)
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
        move(to: current.end, at: now)
    }

    /// Goes back to the start of `segment`, or from a hold to the start of the gap that leads into it,
    /// so the stretch is named again and there is time to get back into position.
    /// No-op unless `segment` is the one in progress at `now`.
    public mutating func restart(_ segment: SegmentID, at now: Date) {
        let elapsed = elapsed(at: now)
        guard let current = timeline.segment(at: elapsed), current.id == segment else { return }
        let target = timeline.restartPoint(for: current.id)
        repeated += elapsed - target.start
        move(to: target.start, at: now)
    }

    /// Does nothing once the run has finished.
    public mutating func perform(_ command: RunCommand, at now: Date) {
        guard let current = timeline.segment(at: elapsed(at: now)) else { return }
        switch command {
        case .play: resume(at: now)
        case .pause: pause(at: now)
        case .togglePlayPause: if isPaused { resume(at: now) } else { pause(at: now) }
        case .next: skip(current.id, at: now)
        case .previous: restart(current.id, at: now)
        }
    }

    public func snapshot(at now: Date) -> Snapshot {
        let elapsed = elapsed(at: now)
        guard let current = timeline.segment(at: elapsed) else {
            return .finished(worked: timeline.total - skipped + repeated)
        }
        let phaseElapsed = elapsed - current.start
        return .active(RunProgress(
            segment: current.id, phase: current.phase, rep: current.phase.pulse?.rep(at: phaseElapsed),
            phaseElapsed: phaseElapsed, phaseRemaining: current.end - elapsed, phaseDuration: current.duration,
            elapsed: elapsed, totalRemaining: timeline.total - elapsed, totalDuration: timeline.total,
            upNext: timeline.upNext(after: current.id)?.span, isPaused: isPaused))
    }

    /// The instant elapsed time was zero, or nil while paused. Every figure a snapshot reports changes
    /// on a whole second after it, so a screen that redraws on those seconds is never stale.
    public var zeroDate: Date? {
        switch clock {
        case .running(let zeroAt): zeroAt
        case .paused: nil
        }
    }

    /// Every cue of this run at its wall-clock time. nil while paused.
    public var cueSchedule: CueSchedule? {
        switch clock {
        case .running(let zeroAt): CueSchedule(timeline, cues, zeroAt: zeroAt)
        case .paused: nil
        }
    }

    public var isPaused: Bool {
        if case .paused = clock { true } else { false }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        switch clock {
        case .running(let zeroAt): min(max(now.timeIntervalSince(zeroAt), 0), timeline.total)
        case .paused(let elapsed): elapsed
        }
    }

    private mutating func move(to elapsed: TimeInterval, at now: Date) {
        switch clock {
        case .running: clock = .running(zeroAt: now - elapsed)
        case .paused: clock = .paused(elapsed: elapsed)
        }
    }
}

public enum Snapshot: Equatable, Sendable {
    case active(RunProgress)
    /// `worked` is the workout's length, minus what was skipped, plus what was restarted and done again.
    /// Paused time never counts.
    case finished(worked: TimeInterval)
}

public struct RunProgress: Equatable, Sendable {
    public let segment: SegmentID
    public let phase: Phase
    /// The rep in progress during a hold that counts reps.
    public let rep: Ordinal?
    public let phaseElapsed: TimeInterval
    public let phaseRemaining: TimeInterval
    public let phaseDuration: TimeInterval
    public let elapsed: TimeInterval
    public let totalRemaining: TimeInterval
    public let totalDuration: TimeInterval
    /// The next phase that is not a gap, so a hold shows the stretch after it and not "get ready".
    public let upNext: PhaseSpan?
    public let isPaused: Bool
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
