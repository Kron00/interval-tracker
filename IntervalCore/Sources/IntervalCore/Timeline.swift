import Foundation

public struct Round: Hashable, Sendable {
    /// 1-based.
    public let number: Int
    public let total: Int
    public var isLast: Bool { number == total }
}

public enum Phase: Hashable, Sendable {
    case warmUp
    case work(Round)
    /// The rest that follows work round `number`.
    case rest(Round)
    case coolDown

    public var round: Round? {
        switch self {
        case .work(let round), .rest(let round): round
        case .warmUp, .coolDown: nil
        }
    }

    public var title: String {
        switch self {
        case .warmUp: "Warm-up"
        case .work: "Work"
        case .rest: "Rest"
        case .coolDown: "Cool-down"
        }
    }
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
}

struct Timeline: Equatable, Sendable {
    let segments: [Segment]
    var total: TimeInterval { segments[segments.count - 1].end }

    init(_ definition: TimerDefinition) {
        var segments: [Segment] = []
        func append(_ phase: Phase, _ span: Span?) {
            guard let span else { return }
            segments.append(Segment(id: SegmentID(index: segments.count), phase: phase,
                                    start: segments.last?.end ?? 0, duration: span.interval))
        }

        let total = definition.rounds.value
        append(.warmUp, definition.warmUp)
        for number in 1...total {
            let round = Round(number: number, total: total)
            append(.work(round), definition.work)
            if number < total || definition.restAfterLastRound {
                append(.rest(round), definition.rest)
            }
        }
        append(.coolDown, definition.coolDown)
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

    func segment(after id: SegmentID) -> Segment? {
        segments.indices.contains(id.index + 1) ? segments[id.index + 1] : nil
    }
}
