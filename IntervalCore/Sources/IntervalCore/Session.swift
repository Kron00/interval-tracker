import Foundation

/// What a headphone press or a lock-screen button asks of a run.
public enum RunCommand: Hashable, Sendable {
    /// A single press arrives as one of these. Each means Start or Next while the run waits and is not paused.
    case play, pause, togglePlayPause
    /// What the forward button does: `Session.forward`.
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
    /// Where the last skip by hand landed, in elapsed time. The cue schedule announces that place a
    /// moment after the skip. A run that got there by time passing has the same date, so the date
    /// cannot tell the two apart.
    private var landing: TimeInterval?

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

    /// Ends `segment` now and starts what follows. This is also what releases the gate a run waits
    /// at: Start in a wait for Start, Next in a stretch counted in reps. From a count-in it ends the
    /// stretch, hold included. No-op unless `segment` is the one in progress at `now`.
    public mutating func skip(_ segment: SegmentID, at now: Date) {
        leave(segment, keepingTheStretch: true, at: now)
    }

    /// What the forward button and a double press do. In a wait for Start it leaves the stretch,
    /// count-in and hold included, and lands on what follows. Anywhere else it is `skip`.
    public mutating func forward(_ segment: SegmentID, at now: Date) {
        leave(segment, keepingTheStretch: false, at: now)
    }

    /// Goes back to the start of `segment`, or from a hold to the start of its count-in.
    /// No-op unless `segment` is counting at `now`. A wait has nothing to restart.
    public mutating func restart(_ segment: SegmentID, at now: Date) {
        let elapsed = elapsed(at: now)
        guard case .inside(let current) = timeline.place(at: elapsed, released: released), current.id == segment else { return }
        let target = timeline.restartPoint(for: current.id)
        repeated += elapsed - target.start
        landing = nil
        move(to: target.start, at: now)
    }

    /// Does nothing once the run has finished.
    public mutating func perform(_ command: RunCommand, at now: Date) {
        let place = timeline.place(at: elapsed(at: now), released: released)
        guard let current = place.segment else { return }
        // A wait has nothing to pause, so the press that pauses a countdown moves a waiting run on.
        let waits = place.isWaiting && !isPaused
        switch command {
        case .play where waits, .pause where waits, .togglePlayPause where waits: skip(current.id, at: now)
        case .play: resume(at: now)
        case .pause: pause(at: now)
        case .togglePlayPause: if isPaused { resume(at: now) } else { pause(at: now) }
        case .next: forward(current.id, at: now)
        case .previous: restart(current.id, at: now)
        }
    }

    public func snapshot(at now: Date) -> Snapshot {
        let elapsed = elapsed(at: now)
        let place = timeline.place(at: elapsed, released: released)
        guard let current = place.segment else {
            return .finished(worked: worked(at: now))
        }
        return .active(RunProgress(
            segment: current.id, phase: current.phase,
            phaseElapsed: elapsed - current.start, phaseRemaining: current.end - elapsed, phaseDuration: current.duration,
            elapsed: elapsed, totalRemaining: timeline.total - elapsed, totalDuration: timeline.total,
            upNext: timeline.upNext(after: current.id)?.span, isPaused: isPaused, isWaiting: place.isWaiting,
            isHeadsUp: timeline.headsUp(in: current, cues.headsUp).map { elapsed >= $0 } ?? false))
    }

    /// The time worked up to `now`: the elapsed time, minus what was skipped, plus what was restarted
    /// and done again, plus the time spent in stretches counted in reps, the one in progress included.
    public func worked(at now: Date) -> TimeInterval {
        let elapsed = elapsed(at: now)
        var worked = elapsed - skipped + repeated + inReps
        if case .waiting(let gate) = timeline.place(at: elapsed, released: released), gate.phase.reps != nil {
            worked += ran(at: now) - gate.end
        }
        return worked
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

    /// The instant the phase in progress at `now` runs out by itself. nil when no clock is counting,
    /// which is while the run is paused or waiting, and once it has finished. It is the same date for
    /// the whole phase, so a countdown drawn from it needs no update until the phase changes.
    public func phaseEnd(at now: Date) -> Date? {
        guard let zeroDate, case .inside(let current) = timeline.place(at: elapsed(at: now), released: released) else { return nil }
        return zeroDate + current.end
    }

    /// Every cue up to the next gate, or up to the finish, at its wall-clock time. nil while paused.
    public var cueSchedule: CueSchedule? {
        zeroDate.map { CueSchedule(timeline, cues, zeroAt: $0, released: released, landing: landing) }
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

    /// Start keeps the stretch and begins its count-in, which sounds at once. Every other way of
    /// leaving a segment by hand lands quietly.
    private mutating func leave(_ segment: SegmentID, keepingTheStretch: Bool, at now: Date) {
        let elapsed = elapsed(at: now)
        guard let current = timeline.place(at: elapsed, released: released).segment, current.id == segment else { return }
        let starts = keepingTheStretch && current.phase.isWaitForStart
        let target = starts ? current.end : timeline.skipPoint(for: current.id)
        // Reps are done at their own pace, so the time spent on them is known only when they are left.
        // Time spent waiting for Start is not work and is dropped.
        if current.phase.reps != nil { inReps += ran(at: now) - current.end }
        skipped += target - elapsed
        if current.isGate { released += 1 }
        landing = starts ? nil : target
        move(to: target, at: now)
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
    /// neither does a wait for Start.
    case finished(worked: TimeInterval)
}

public struct RunProgress: Equatable, Sendable {
    public let segment: SegmentID
    public let phase: Phase
    public let phaseElapsed: TimeInterval
    /// 0 while waiting.
    public let phaseRemaining: TimeInterval
    /// 0 while waiting.
    public let phaseDuration: TimeInterval
    public let elapsed: TimeInterval
    public let totalRemaining: TimeInterval
    public let totalDuration: TimeInterval
    /// What follows this phase, or this stretch from its wait or its count-in: the next hold or
    /// interval phase, never a wait or a count-in.
    public let upNext: PhaseSpan?
    public let isPaused: Bool
    /// The phase has no length, and the run stays in it until `RunCommand.next` or a skip.
    public let isWaiting: Bool
    /// Work begins when this phase ends, and it is time to say so. True from the heads-up instant to
    /// the end of the phase, and never in a phase that gets no heads-up.
    public let isHeadsUp: Bool

    /// The line under the title.
    public var caption: String? { isHeadsUp ? "Get ready" : phase.caption }

    /// What the forward button is called. In a wait it leaves the stretch.
    public var forwardTitle: String { isWaiting ? "Skip stretch" : phase.advanceTitle }

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
