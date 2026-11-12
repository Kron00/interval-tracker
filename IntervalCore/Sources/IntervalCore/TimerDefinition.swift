import Foundation

/// A whole number of seconds, always 1...86_400. There is no zero span: "no warm-up" is `nil`.
public struct Span: Hashable, Comparable, Sendable, Codable {
    public let seconds: Int

    public init?(seconds: Int) {
        guard (1...86_400).contains(seconds) else { return nil }
        self.seconds = seconds
    }

    public init?(minutes: Int, seconds: Int) { self.init(seconds: minutes * 60 + seconds) }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let span = Span(seconds: try container.decode(Int.self)) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A span is 1...86400 whole seconds.")
        }
        self = span
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }

    public static func < (a: Span, b: Span) -> Bool { a.seconds < b.seconds }
    var interval: TimeInterval { TimeInterval(seconds) }
}

/// Number of work rounds, always 1...99.
public struct RoundCount: Hashable, Sendable, Codable {
    public let value: Int

    public init?(_ value: Int) {
        guard (1...99).contains(value) else { return nil }
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let count = RoundCount(try container.decode(Int.self)) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A round count is 1...99.")
        }
        self = count
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct TimerDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var warmUp: Span?
    public var work: Span
    public var rest: Span?
    public var rounds: RoundCount
    public var coolDown: Span?
    public var restAfterLastRound: Bool

    public init(id: UUID = UUID(), name: String, warmUp: Span?, work: Span, rest: Span?,
                rounds: RoundCount, coolDown: Span?, restAfterLastRound: Bool = true) {
        self.id = id; self.name = name; self.warmUp = warmUp; self.work = work
        self.rest = rest; self.rounds = rounds; self.coolDown = coolDown
        self.restAfterLastRound = restAfterLastRound
    }

    public var totalDuration: TimeInterval { Timeline(self).total }

    public static let norwegian4x4 = TimerDefinition(
        id: codeConstantID(1), name: "Norwegian 4x4",
        warmUp: literal(minutes: 5), work: literal(minutes: 4), rest: literal(minutes: 3),
        rounds: literal(rounds: 4), coolDown: literal(minutes: 5))

    public static let hiit2020 = TimerDefinition(
        id: codeConstantID(2), name: "20/20 HIIT",
        warmUp: literal(minutes: 5), work: literal(seconds: 20), rest: literal(seconds: 20),
        rounds: literal(rounds: 9), coolDown: literal(minutes: 3))

    public static let audioCheck = TimerDefinition(
        id: codeConstantID(3), name: "Audio check",
        warmUp: literal(seconds: 30), work: literal(seconds: 10), rest: literal(seconds: 10),
        rounds: literal(rounds: 2), coolDown: nil, restAfterLastRound: false)

    public static let builtIn: [TimerDefinition] = [.norwegian4x4, .hiit2020]

    private static func codeConstantID(_ number: UInt8) -> UUID {
        UUID(uuid: (0x49, 0x4E, 0x54, 0x56, 0x4C, 0x43, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, number))
    }

    private static func literal(minutes: Int = 0, seconds: Int = 0) -> Span {
        Span(minutes: minutes, seconds: seconds)!
    }

    private static func literal(rounds: Int) -> RoundCount { RoundCount(rounds)! }
}
