import Foundation

/// A place in a run of things: round 2 of 4, stretch 4 of 10.
public struct Ordinal: Hashable, Sendable {
    /// 1-based.
    public let number: Int
    public let total: Int
    public var isLast: Bool { number == total }
}

/// One side of one stretch at its place in the routine.
public struct Pose: Hashable, Sendable {
    public let stretch: Stretch
    /// nil for a stretch done once.
    public let side: Side?
    public let position: Ordinal
}

public enum Phase: Hashable, Sendable {
    case warmUp
    case work(Ordinal)
    /// The rest that follows work round `number`.
    case rest(Ordinal)
    case coolDown
    /// The wait before a timed hold. It has no length, names the stretch, and ends on Start.
    case ready(Pose)
    /// The count-in between Start and the hold.
    case getReady(Pose)
    /// A timed hold, or a stretch counted in reps. Reps have no length and end on Next.
    case hold(Pose)

    public var title: String {
        switch self {
        case .warmUp: "Warm-up"
        case .work: "Work"
        case .rest: "Rest"
        case .coolDown: "Cool-down"
        case .ready(let pose), .getReady(let pose), .hold(let pose): pose.stretch.name
        }
    }

    /// What to call this phase when it comes after `current`. The other side of the stretch in
    /// progress is named by its side alone, so "up next" does not read as the same stretch again.
    public func title(following current: Phase) -> String {
        guard case .hold(let next) = self, let side = next.side, current.stretchID == next.stretch.id else { return title }
        return side.label
    }

    private var stretchID: Stretch.ID? {
        switch self {
        case .ready(let pose), .getReady(let pose), .hold(let pose): pose.stretch.id
        case .warmUp, .work, .rest, .coolDown: nil
        }
    }

    public var caption: String? {
        switch self {
        case .warmUp, .coolDown:
            nil
        case .work(let round), .rest(let round):
            "Round \(round.number) of \(round.total)"
        case .ready(let pose), .hold(let pose):
            caption(pose.side?.label, "Stretch \(pose.position.number) of \(pose.position.total)")
        case .getReady(let pose):
            caption("Get ready", pose.side?.label)
        }
    }

    public var tone: Tone {
        switch self {
        case .warmUp, .ready, .getReady: .prepare
        case .work: .effort
        case .rest: .recover
        case .hold: .stretch
        case .coolDown: .cool
        }
    }

    public var howTo: URL? {
        switch self {
        case .warmUp, .work, .rest, .coolDown: nil
        case .ready(let pose), .getReady(let pose), .hold(let pose): pose.stretch.howTo
        }
    }

    var announcement: Utterance? {
        switch self {
        case .warmUp: Utterance("Warm up")
        case .work(let round):
            round.isLast && round.total > 1 ? Utterance("Last round") : Utterance("Round " + spelledOut[round.number])
        case .rest: Utterance("Rest")
        case .coolDown: Utterance("Cool down")
        case .ready(let pose): pose.spokenName
        case .getReady: nil
        // The wait before a timed hold has already named it. Reps have no wait before them.
        case .hold(let pose): reps == nil ? nil : pose.spokenName
        }
    }

    /// The rep count of a stretch counted in reps. Such a hold is not timed.
    public var reps: Count? {
        if case .hold(let pose) = self, case .reps(let count) = pose.stretch.amount { count } else { nil }
    }

    /// The length of the hold that Start begins, for a clock to show while the run waits for Start.
    /// nil for every other phase.
    public var pendingHold: TimeInterval? {
        if case .ready(let pose) = self, case .hold(let span) = pose.stretch.amount { span.interval } else { nil }
    }

    /// What ending this phase by hand is called. A timed hold begins on Start and a stretch is left
    /// with Next. An interval is cut short with Skip.
    public var advanceTitle: String {
        switch self {
        case .warmUp, .work, .rest, .coolDown: "Skip"
        case .ready: "Start"
        case .getReady, .hold: "Next"
        }
    }

    var isCountIn: Bool {
        if case .getReady = self { true } else { false }
    }

    /// The wait and the count-in lead into a hold and belong to its stretch. "Up next" looks past them.
    var isLeadIn: Bool {
        switch self {
        case .ready, .getReady: true
        case .warmUp, .work, .rest, .coolDown, .hold: false
        }
    }

    private func caption(_ parts: String?...) -> String {
        parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// The colour family of a phase.
public enum Tone: Hashable, Sendable, CaseIterable {
    case prepare, effort, recover, stretch, cool
}

extension Side {
    var label: String {
        switch self {
        case .left: "Left side"
        case .right: "Right side"
        }
    }
}

extension Pose {
    var spokenName: Utterance {
        Utterance(side.map { "\(stretch.name), \($0.label.lowercased())" } ?? stretch.name)
    }
}

/// "zero"..."ninety-nine". Spelling a number sets up a rule-based formatter, which is too slow to do
/// for every round each time a schedule is built.
private let spelledOut: [String] = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .spellOut
    formatter.locale = Locale(identifier: "en_US")
    return (0...99).map { formatter.string(from: $0 as NSNumber) ?? String($0) }
}()

public struct PhaseSpan: Hashable, Sendable {
    public let phase: Phase
    /// 0 for a stretch counted in reps.
    public let duration: TimeInterval
}

public struct SegmentID: Hashable, Sendable {
    let index: Int

    /// The segment's place in its workout as a plain number, for a value that leaves the app. A
    /// Live Activity button hands it back, and it then says which wait the button was drawn for.
    public var position: Int { index }
}

struct Segment: Equatable, Sendable {
    let id: SegmentID
    let phase: Phase
    let start: TimeInterval
    let duration: TimeInterval
    /// A gate holds the run at its end until someone releases it. Time does not pass a gate by itself.
    /// Every gate has no length, so the run waits from the moment it reaches one.
    let isGate: Bool
    var end: TimeInterval { start + duration }
    var span: PhaseSpan { PhaseSpan(phase: phase, duration: duration) }
}

/// Where a run stands on its timeline.
enum Place: Equatable, Sendable {
    case inside(Segment)
    /// Stopped at a gate.
    case waiting(Segment)
    case finished

    var segment: Segment? {
        switch self {
        case .inside(let segment), .waiting(let segment): segment
        case .finished: nil
        }
    }

    var isWaiting: Bool {
        if case .waiting = self { true } else { false }
    }
}

struct Timeline: Equatable, Sendable {
    let segments: [Segment]
    /// The gates in order. A run passes them one at a time, so a count says which ones are behind it.
    let gates: [Segment]
    var total: TimeInterval { segments[segments.count - 1].end }

    init(_ plan: Plan) {
        var segments: [Segment] = []
        func append(_ phase: Phase, _ duration: TimeInterval?, isGate: Bool = false) {
            guard let duration else { return }
            segments.append(Segment(id: SegmentID(index: segments.count), phase: phase,
                                    start: segments.last?.end ?? 0, duration: duration, isGate: isGate))
        }

        switch plan {
        case .intervals(let intervals):
            let total = intervals.rounds.value
            append(.warmUp, intervals.warmUp?.interval)
            for number in 1...total {
                let round = Ordinal(number: number, total: total)
                append(.work(round), intervals.work.interval)
                if number < total || intervals.restAfterLastRound {
                    append(.rest(round), intervals.rest?.interval)
                }
            }
            append(.coolDown, intervals.coolDown?.interval)
        case .routine(let routine):
            for (index, stretch) in routine.stretches.enumerated() {
                let position = Ordinal(number: index + 1, total: routine.stretches.count)
                for side in stretch.sides.inOrder {
                    let pose = Pose(stretch: stretch, side: side, position: position)
                    switch stretch.amount {
                    case .hold(let span):
                        append(.ready(pose), 0, isGate: true)
                        append(.getReady(pose), routine.countIn?.interval)
                        append(.hold(pose), span.interval)
                    case .reps:
                        append(.hold(pose), 0, isGate: true)
                    }
                }
            }
        }
        self.segments = segments
        gates = segments.filter(\.isGate)
    }

    /// The first gate a run has still to pass once `released` gates are behind it.
    func gate(after released: Int) -> Segment? {
        released < gates.count ? gates[released] : nil
    }

    /// As far as a run gets by itself with `released` gates behind it.
    func limit(after released: Int) -> TimeInterval {
        gate(after: released)?.end ?? total
    }

    /// `elapsed` is never past `limit(after: released)`.
    func place(at elapsed: TimeInterval, released: Int) -> Place {
        if let gate = gate(after: released), elapsed >= gate.end { return .waiting(gate) }
        guard elapsed < total else { return .finished }
        // The last segment that starts at or before `elapsed`. A gate of no length shares its start
        // with the segment after it, and that gate is behind the run by now.
        var low = 0
        var high = segments.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if segments[middle].start <= elapsed { low = middle } else { high = middle - 1 }
        }
        return .inside(segments[low])
    }

    /// The segments a run plays without help once `released` gates are behind it: from the one after
    /// the last gate it passed, through the next gate or the end.
    func leg(after released: Int) -> ArraySlice<Segment> {
        let first = released > 0 ? gates[released - 1].id.index + 1 : 0
        let end = gate(after: released).map { $0.id.index + 1 } ?? segments.count
        return segments[first..<end]
    }

    /// The instant in `segment` from which the run says that work is coming, or nil when the segment
    /// gets no heads-up. A warm-up or a rest gets one when work follows it and it is long enough that
    /// the heads-up does not come right at its start. A stretch routine has no such phase.
    func headsUp(in segment: Segment, _ headsUp: HeadsUp) -> TimeInterval? {
        guard let lead = headsUp.lead, segment.duration >= lead + CueTiming.headsUpMargin,
              segment.id.index + 1 < segments.count, case .work = segments[segment.id.index + 1].phase else { return nil }
        switch segment.phase {
        case .warmUp, .rest: return segment.end - lead
        case .work, .coolDown, .ready, .getReady, .hold: return nil
        }
    }

    /// What follows the segment, or from a wait or a count-in what follows the hold it leads into.
    func upNext(after id: SegmentID) -> Segment? {
        guard let phase = segments[id.index...].firstIndex(where: { !$0.phase.isLeadIn }) else { return nil }
        return segments[(phase + 1)...].first { !$0.phase.isLeadIn }
    }

    /// A hold restarts from its count-in, so there is time to get back into position.
    func restartPoint(for id: SegmentID) -> Segment {
        guard id.index > 0, segments[id.index - 1].phase.isCountIn else { return segments[id.index] }
        return segments[id.index - 1]
    }

    /// Where a skip of the segment lands. Next in a count-in leaves the stretch, so it lands past the hold.
    func skipPoint(for id: SegmentID) -> TimeInterval {
        segments[id.index].phase.isCountIn ? segments[id.index + 1].end : segments[id.index].end
    }
}
