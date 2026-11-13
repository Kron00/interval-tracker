import Foundation

/// What a headphone press or a lock-screen button asks of a run.
public enum RunCommand: Hashable, Sendable {
    case play, pause, togglePlayPause
    /// Ends the segment in progress, or the wait at its end.
    case next
    /// Restarts the segment in progress.
    case previous
}

public struct Session: Equatable, Sendable {
    /// Both cases count the time the run has been running, and that time may be past the gate the
    /// run waits at. What a snapshot reports stops at the gate.
    private enum Clock: Equatable, Sendable {
        case running(zeroAt: Date)
        case paused(ran: TimeInterval)
    }

    public let workout: Workout
    private let timeline: Timeline
    private let cues: CuePreferences
    private var clock: Clock
    /// How many gates are behind the run. Whether it waits at the next one follows from the clock.
    private var released = 0
    private var skipped: TimeInterval = 0
    private var repeated: TimeInterval = 0
    /// Time spent in stretches counted in reps. They have no length of their own.
    private var inReps: TimeInterval = 0

    public init(_ workout: Workout, cues: CuePreferences, startingAt now: Date) {
        self.workout = workout
        self.timeline = Timeline(workout.plan)
        self.cues = cues
        self.clock = .running(zeroAt: now)
    }

    public mutating func pause(at now: Date) {
        clock = .paused(ran: ran(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let ran) = clock else { return }
        clock = .running(zeroAt: now - ran)
    }

    /// Ends `segment` now and starts the next one. This is also what releases a gate, during its
    /// hold or while the run waits at its end. No-op unless `segment` is the one in progress at `now`.
    public mutating func skip(_ segment: SegmentID, at now: Date) {
        let elapsed = elapsed(at: now)
        guard let current = timeline.place(at: elapsed, released: released).segment, current.id == segment else { return }
        leave(current, at: now)
        skipped += current.end - elapsed
        if current.isGate { released += 1 }
        move(to: current.end, at: now)
    }

    /// Goes back to the start of `segment`, or from a hold to the start of the gap that leads into it,
    /// so the stretch is named again and there is time to get back into position.
    /// No-op unless `segment` is the one in progress at `now`.
    public mutating func restart(_ segment: SegmentID, at now: Date) {
        let elapsed = elapsed(at: now)
        guard let current = timeline.place(at: elapsed, released: released).segment, current.id == segment else { return }
        let target = timeline.restartPoint(for: current.id)
        leave(current, at: now)
        repeated += elapsed - target.start
        move(to: target.start, at: now)
    }

    /// Does nothing once the run has finished.
    public mutating func perform(_ command: RunCommand, at now: Date) {
        guard let current = timeline.place(at: elapsed(at: now), released: released).segment else { return }
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
        let place = timeline.place(at: elapsed, released: released)
        guard let current = place.segment else {
            return .finished(worked: timeline.total - skipped + repeated + inReps)
        }
        return .active(RunProgress(
            segment: current.id, phase: current.phase,
            phaseElapsed: elapsed - current.start, phaseRemaining: current.end - elapsed, phaseDuration: current.duration,
            elapsed: elapsed, totalRemaining: timeline.total - elapsed, totalDuration: timeline.total,
            upNext: timeline.upNext(after: current.id)?.span, isPaused: isPaused, isWaiting: place.isWaiting))
    }

    /// The instant elapsed time was zero, or nil while paused. Every figure a snapshot reports changes
    /// on a whole second after it, so a screen that redraws on those seconds is never stale.
    public var zeroDate: Date? {
        switch clock {
        case .running(let zeroAt): zeroAt
        case .paused: nil
        }
    }

    /// The instant the run next stops by itself, at a gate or at the finish. nil while paused.
    /// No figure a snapshot reports changes after it, so a screen has nothing to redraw from then on.
    public var haltDate: Date? {
        zeroDate.map { $0 + timeline.limit(after: released) }
    }

    /// Every cue up to the next gate, or up to the finish, at its wall-clock time. nil while paused.
    public var cueSchedule: CueSchedule? {
        zeroDate.map { CueSchedule(timeline, cues, zeroAt: $0, released: released) }
    }

    /// Every distinct sound of the whole run in order of first use, whatever gates lie ahead.
    public var vocabulary: [Sound] {
        CueSchedule.vocabulary(of: timeline, cues)
    }

    public var isPaused: Bool {
        if case .paused = clock { true } else { false }
    }

    private func ran(at now: Date) -> TimeInterval {
        switch clock {
        case .running(let zeroAt): max(now.timeIntervalSince(zeroAt), 0)
        case .paused(let ran): ran
        }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        min(ran(at: now), timeline.limit(after: released))
    }

    /// Reps are done at their own pace, so the time spent on them is known only when they are left.
    /// Time spent waiting after a timed hold is not work and is dropped.
    private mutating func leave(_ segment: Segment, at now: Date) {
        guard segment.phase.reps != nil else { return }
        inReps += ran(at: now) - segment.end
    }

    private mutating func move(to elapsed: TimeInterval, at now: Date) {
        switch clock {
        case .running: clock = .running(zeroAt: now - elapsed)
        case .paused: clock = .paused(ran: elapsed)
        }
    }
}

public enum Snapshot: Equatable, Sendable {
    case active(RunProgress)
    /// `worked` is the workout's timed length, minus what was skipped, plus what was restarted and
    /// done again, plus the time spent in stretches counted in reps. Paused time never counts, and
    /// neither does a wait after a timed hold.
    case finished(worked: TimeInterval)
}

public struct RunProgress: Equatable, Sendable {
    public let segment: SegmentID
    public let phase: Phase
    public let phaseElapsed: TimeInterval
    /// 0 while waiting.
    public let phaseRemaining: TimeInterval
    /// 0 for a stretch counted in reps.
    public let phaseDuration: TimeInterval
    public let elapsed: TimeInterval
    public let totalRemaining: TimeInterval
    public let totalDuration: TimeInterval
    /// The next phase that is not a gap, so a hold shows the stretch after it and not "get ready".
    public let upNext: PhaseSpan?
    public let isPaused: Bool
    /// The phase is over, or has no length, and the run stays in it until `RunCommand.next` or a skip.
    public let isWaiting: Bool

    /// The rep count of a stretch counted in reps, nil for every other phase.
    public var reps: Count? { phase.reps }
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
