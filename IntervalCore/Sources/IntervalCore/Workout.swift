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

/// A number of rounds or reps, always 1...99.
public struct Count: Hashable, Sendable, Codable {
    public let value: Int

    public init?(_ value: Int) {
        guard (1...99).contains(value) else { return nil }
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let count = Count(try container.decode(Int.self)) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A count is 1...99.")
        }
        self = count
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct Workout: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var plan: Plan

    public init(id: UUID = UUID(), name: String, plan: Plan) {
        self.id = id; self.name = name; self.plan = plan
    }

    /// The timed length. A stretch counted in reps has none, so it adds nothing here.
    public var totalDuration: TimeInterval { Timeline(plan).total }

    /// Every phase of the workout in order, for drawing it. A wait for Start is not something to
    /// draw, so it is left out.
    public var outline: [PhaseSpan] {
        Timeline(plan).segments.filter { $0.phase.pendingHold == nil }.map(\.span)
    }

    /// The same workout under a fresh id.
    public func forked() -> Workout { Workout(name: name, plan: plan) }

    public static let norwegian4x4 = Workout(
        id: codeConstantID(1), name: "Norwegian 4x4",
        plan: .intervals(Intervals(
            warmUp: literal(minutes: 5), work: literal(minutes: 4), rest: literal(minutes: 3),
            rounds: literal(count: 4), coolDown: literal(minutes: 5))))

    public static let hiit2020 = Workout(
        id: codeConstantID(2), name: "20/20 HIIT",
        plan: .intervals(Intervals(
            warmUp: literal(minutes: 5), work: literal(seconds: 20), rest: literal(seconds: 20),
            rounds: literal(count: 9), coolDown: literal(minutes: 3))))

    public static let audioCheck = Workout(
        id: codeConstantID(3), name: "Audio check",
        plan: .intervals(Intervals(
            warmUp: literal(seconds: 30), work: literal(seconds: 10), rest: literal(seconds: 10),
            rounds: literal(count: 2), coolDown: nil, restAfterLastRound: false)))

    public static let dailyStretch = Workout(
        id: codeConstantID(4), name: "Daily Stretch",
        plan: .routine(Routine(
            stretches: [
                builtInStretch(1, "Cat-Cow", .reps(literal(count: 10)), .once, video: "1Y0YjXS9sKI"),
                builtInStretch(2, "Child's Pose", .hold(literal(seconds: 45)), .once, video: "_ZX_zTOBgp8"),
                builtInStretch(3, "Cobra", .hold(literal(seconds: 30)), .once, video: "Aqyvevt4EUU"),
                builtInStretch(4, "Hip Flexor Couch Stretch", .hold(literal(seconds: 45)), .each, video: "m2u7jOCMyBg"),
                builtInStretch(5, "Pigeon", .hold(literal(seconds: 45)), .each, video: "lqCqETr7Q0g"),
                builtInStretch(6, "Butterfly", .hold(literal(seconds: 45)), .once, video: "MHwUChXNy-Y"),
                builtInStretch(7, "Standing Hamstring", .hold(literal(seconds: 45)), .once, video: "goN4rWbQUn4"),
                builtInStretch(8, "Doorway Pec", .hold(literal(seconds: 30)), .once, video: "M850sCj9LHQ"),
                builtInStretch(9, "Thread the Needle", .hold(literal(seconds: 30)), .each, video: "SkQhKf74nZk"),
                builtInStretch(10, "Passive Dead Hang", .hold(literal(seconds: 30)), .once, video: "3CEmHJXbNpc"),
            ])!))

    public static let builtIn: [Workout] = [.norwegian4x4, .hiit2020, .dailyStretch]

    private static func codeConstantID(_ number: UInt8, part: UInt8 = 0) -> UUID {
        UUID(uuid: (0x49, 0x4E, 0x54, 0x56, 0x4C, 0x43, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, part, number))
    }

    private static func literal(minutes: Int = 0, seconds: Int = 0) -> Span {
        Span(minutes: minutes, seconds: seconds)!
    }

    private static func literal(count: Int) -> Count { Count(count)! }

    private static func builtInStretch(_ number: UInt8, _ name: String, _ amount: Amount, _ sides: Sides,
                                       video: String) -> Stretch {
        Stretch(id: codeConstantID(4, part: number), name: name, amount: amount, sides: sides,
                howTo: URL(string: "https://youtu.be/" + video))!
    }
}

/// In JSON the plan's key says which kind it is: `"intervals": {...}` or `"routine": {...}`.
extension Workout: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, intervals, routine
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        switch (container.contains(.intervals), container.contains(.routine)) {
        case (true, false):
            plan = .intervals(try container.decode(Intervals.self, forKey: .intervals))
        case (false, true):
            plan = .routine(try container.decode(Routine.self, forKey: .routine))
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A workout has either intervals or a routine."))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        switch plan {
        case .intervals(let intervals): try container.encode(intervals, forKey: .intervals)
        case .routine(let routine): try container.encode(routine, forKey: .routine)
        }
    }
}

public enum Plan: Hashable, Sendable {
    case intervals(Intervals)
    case routine(Routine)
}

public struct Intervals: Hashable, Sendable, Codable {
    public var warmUp: Span?
    public var work: Span
    public var rest: Span?
    public var rounds: Count
    public var coolDown: Span?
    public var restAfterLastRound: Bool

    public init(warmUp: Span?, work: Span, rest: Span?, rounds: Count, coolDown: Span?,
                restAfterLastRound: Bool = true) {
        self.warmUp = warmUp; self.work = work; self.rest = rest; self.rounds = rounds
        self.coolDown = coolDown; self.restAfterLastRound = restAfterLastRound
    }
}

/// Stretches in order. Each timed hold waits for Start and then counts in. Always 1...99 stretches.
public struct Routine: Hashable, Sendable, Codable {
    /// The count-in between Start and each timed hold, 1...30 s. nil means the hold begins on Start.
    public let countIn: Span?
    public let stretches: [Stretch]

    public static let defaultCountIn = Span(seconds: 3)
    public static let maximumCountIn = 30
    public static let maximumStretches = 99

    public init?(countIn: Span? = Routine.defaultCountIn, stretches: [Stretch]) {
        guard (countIn?.seconds ?? 0) <= Routine.maximumCountIn,
              (1...Routine.maximumStretches).contains(stretches.count) else { return nil }
        self.countIn = countIn; self.stretches = stretches
    }

    private enum CodingKeys: String, CodingKey {
        case countIn, stretches
    }

    /// In JSON `"countIn": 0` means none. A file without the key was written before the count-in
    /// existed and gets the default. Such a file has `getReady` and `switchSides` values. They set
    /// the length of gaps that no longer exist, so they are ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let invalid = DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "A routine has 1...99 stretches and a count-in of 0...30 s."))
        var countIn = Routine.defaultCountIn
        if let seconds = try container.decodeIfPresent(Int.self, forKey: .countIn) {
            guard seconds == 0 || Span(seconds: seconds) != nil else { throw invalid }
            countIn = Span(seconds: seconds)
        }
        guard let routine = Routine(
            countIn: countIn, stretches: try container.decode([Stretch].self, forKey: .stretches)) else { throw invalid }
        self = routine
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(countIn?.seconds ?? 0, forKey: .countIn)
        try container.encode(stretches, forKey: .stretches)
    }
}

public struct Stretch: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Trimmed, 1...40 characters. The voice speaks it as written.
    public let name: String
    public let amount: Amount
    public let sides: Sides
    /// http or https only.
    public let howTo: URL?

    public static let maximumNameLength = 40

    public init?(id: UUID = UUID(), name: String, amount: Amount, sides: Sides, howTo: URL?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Stretch.maximumNameLength).contains(name.count) else { return nil }
        if let howTo {
            guard let scheme = howTo.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        }
        self.id = id; self.name = name; self.amount = amount; self.sides = sides; self.howTo = howTo
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let stretch = Stretch(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            amount: try container.decode(Amount.self, forKey: .amount),
            sides: try container.decode(Sides.self, forKey: .sides),
            howTo: try container.decodeIfPresent(URL.self, forKey: .howTo)) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A stretch has a name of 1...40 characters and an http or https link."))
        }
        self = stretch
    }
}

/// What one side of a stretch asks for: a timed hold, or a number of reps done at your own pace.
/// In JSON: `{"hold": 45}` or `{"reps": 10}`.
public enum Amount: Hashable, Sendable, Codable {
    case hold(Span)
    case reps(Count)

    private enum CodingKeys: String, CodingKey {
        case hold, reps
    }

    /// App version 1.1 paced reps and wrote `{"reps": 10, "every": 5}`. The pace is ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.hold), container.contains(.reps)) {
        case (true, false):
            self = .hold(try container.decode(Span.self, forKey: .hold))
        case (false, true):
            self = .reps(try container.decode(Count.self, forKey: .reps))
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "An amount is either a hold or reps."))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hold(let span): try container.encode(span, forKey: .hold)
        case .reps(let count): try container.encode(count, forKey: .reps)
        }
    }
}

public enum Sides: String, Hashable, Sendable, Codable, CaseIterable {
    case once
    /// Left first, then right.
    case each

    var inOrder: [Side?] {
        switch self {
        case .once: [nil]
        case .each: [.left, .right]
        }
    }
}

public enum Side: String, Hashable, Sendable {
    case left, right
}
