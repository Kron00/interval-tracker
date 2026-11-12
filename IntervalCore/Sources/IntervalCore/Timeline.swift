import Foundation

/// A place in a run of things: round 2 of 4, stretch 4 of 10, rep 3 of 10.
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
    /// The gap before a stretch. It announces the stretch, so the hold itself starts without a voice.
    case getReady(Pose)
    case hold(Pose)
    /// The gap between the two sides. Its pose is the side that comes next.
    case switchSides(to: Pose)

    public var title: String {
        switch self {
        case .warmUp: "Warm-up"
        case .work: "Work"
        case .rest: "Rest"
        case .coolDown: "Cool-down"
        case .getReady(let pose), .hold(let pose), .switchSides(let pose): pose.stretch.name
        }
    }

    public var caption: String? {
        switch self {
        case .warmUp, .coolDown:
            nil
        case .work(let round), .rest(let round):
            "Round \(round.number) of \(round.total)"
        case .getReady(let pose):
            caption("Get ready", pose.side?.label)
        case .hold(let pose):
            caption(pose.side?.label, "Stretch \(pose.position.number) of \(pose.position.total)")
        case .switchSides(let pose):
            caption("Switch sides", pose.side.map { "\($0.label) next" })
        }
    }

    public var tone: Tone {
        switch self {
        case .warmUp, .getReady: .prepare
        case .work: .effort
        case .rest, .switchSides: .recover
        case .hold: .stretch
        case .coolDown: .cool
        }
    }

    public var howTo: URL? {
        switch self {
        case .warmUp, .work, .rest, .coolDown: nil
        case .getReady(let pose), .hold(let pose), .switchSides(let pose): pose.stretch.howTo
        }
    }

    var announcement: Utterance? {
        switch self {
        case .warmUp: Utterance("Warm up")
        case .work(let round):
            round.isLast && round.total > 1 ? Utterance("Last round") : Utterance("Round " + spelledOut[round.number])
        case .rest: Utterance("Rest")
        case .coolDown: Utterance("Cool down")
        case .getReady(let pose):
            Utterance(pose.side.map { "\(pose.stretch.name), \($0.label.lowercased())" } ?? pose.stretch.name)
        case .hold: nil
        case .switchSides: .switchSides
        }
    }

    var pulse: Pulse? {
        switch self {
        case .hold(let pose):
            if case .reps(let count, let every) = pose.stretch.amount { Pulse(count: count, every: every) } else { nil }
        case .warmUp, .work, .rest, .coolDown, .getReady, .switchSides:
            nil
        }
    }

    /// A gap leads into a hold. "Up next" looks past it, and a restart from the hold lands on it.
    var isGap: Bool {
        switch self {
        case .getReady, .switchSides: true
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

/// The pacing of a hold that counts reps.
struct Pulse: Hashable, Sendable {
    let count: Count
    let every: Span

    /// Where reps 2...count start, measured from the start of the hold.
    var beats: [TimeInterval] {
        (1..<count.value).map { TimeInterval($0) * every.interval }
    }

    func rep(at sinceStart: TimeInterval) -> Ordinal {
        Ordinal(number: min(count.value, Int(sinceStart / every.interval) + 1), total: count.value)
    }
}

extension Side {
    var label: String {
        switch self {
        case .left: "Left side"
        case .right: "Right side"
        }
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
    public let duration: TimeInterval
}

public struct SegmentID: Hashable, Sendable {
    let index: Int
}

struct Segment: Equatable, Sendable {
    let id: SegmentID
    let phase: Phase
    let start: TimeInterval
    let duration: TimeInterval
    var end: TimeInterval { start + duration }
    var span: PhaseSpan { PhaseSpan(phase: phase, duration: duration) }
}

struct Timeline: Equatable, Sendable {
    let segments: [Segment]
    var total: TimeInterval { segments[segments.count - 1].end }

    init(_ plan: Plan) {
        var segments: [Segment] = []
        func append(_ phase: Phase, _ duration: TimeInterval?) {
            guard let duration else { return }
            segments.append(Segment(id: SegmentID(index: segments.count), phase: phase,
                                    start: segments.last?.end ?? 0, duration: duration))
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
                switch stretch.sides {
                case .once:
                    let pose = Pose(stretch: stretch, side: nil, position: position)
                    append(.getReady(pose), routine.getReady.interval)
                    append(.hold(pose), stretch.amount.duration)
                case .each:
                    let left = Pose(stretch: stretch, side: .left, position: position)
                    let right = Pose(stretch: stretch, side: .right, position: position)
                    append(.getReady(left), routine.getReady.interval)
                    append(.hold(left), stretch.amount.duration)
                    append(.switchSides(to: right), routine.switchSides.interval)
                    append(.hold(right), stretch.amount.duration)
                }
            }
        }
        self.segments = segments
    }

    func segment(at offset: TimeInterval) -> Segment? {
        guard offset < total else { return nil }
        var low = 0
        var high = segments.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if segments[middle].start <= offset { low = middle } else { high = middle - 1 }
        }
        return segments[low]
    }

    func upNext(after id: SegmentID) -> Segment? {
        segments[(id.index + 1)...].first { !$0.phase.isGap }
    }

    func restartPoint(for id: SegmentID) -> Segment {
        let current = segments[id.index]
        guard !current.phase.isGap, id.index > 0, segments[id.index - 1].phase.isGap else { return current }
        return segments[id.index - 1]
    }
}
