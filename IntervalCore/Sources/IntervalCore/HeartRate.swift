import Foundation

/// One beat-per-minute figure from a heart-rate monitor, and when it arrived.
public struct HeartRateReading: Hashable, Sendable {
    public static let plausible = 25...250
    /// A reading older than this is not shown as the current heart rate.
    public static let freshFor: TimeInterval = 5

    public let bpm: Int
    public let date: Date

    /// nil for a figure no heart beats at. A strap that has lost skin contact sends 0.
    public init?(bpm: Int, at date: Date) {
        guard Self.plausible.contains(bpm) else { return nil }
        self.bpm = bpm
        self.date = date
    }

    public func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(date) <= Self.freshFor
    }
}

/// The five zones, and the band below the first.
public enum HeartRateZone: Int, CaseIterable, Comparable, Hashable, Sendable {
    case belowOne, one, two, three, four, five

    /// The share of the maximum heart rate at which each zone begins, in percent.
    var floorPercent: Int {
        switch self {
        case .belowOne: 0
        case .one: 50
        case .two: 60
        case .three: 70
        case .four: 80
        case .five: 90
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The maximum heart rate the user has set. It decides where every zone begins.
public struct MaxHeartRate: Hashable, Sendable, Codable {
    public static let range = 120...220
    public static let standard = MaxHeartRate(uncheckedValue: 190)

    public let value: Int

    public init?(_ value: Int) {
        guard Self.range.contains(value) else { return nil }
        self.value = value
    }

    private init(uncheckedValue: Int) {
        value = uncheckedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard let valid = MaxHeartRate(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a maximum heart rate: \(value).")
        }
        self = valid
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    /// Compared in whole numbers, so 60% of 190 is 114 exactly and 114 is in zone 2.
    public func zone(of bpm: Int) -> HeartRateZone {
        HeartRateZone.allCases.last { bpm * 100 >= $0.floorPercent * value } ?? .belowOne
    }

    /// The lowest heart rate in `zone`.
    public func floor(of zone: HeartRateZone) -> Int {
        (zone.floorPercent * value + 99) / 100
    }
}

/// What the history keeps of the heart rate of one run.
public struct HeartRateSummary: Hashable, Sendable, Codable {
    /// One point of the graph, at a whole number of seconds after the run started.
    public struct Point: Hashable, Sendable, Codable {
        public let second: Int
        public let bpm: Int

        public init(second: Int, bpm: Int) {
            self.second = second
            self.bpm = bpm
        }

        /// Written as `[second, bpm]`. A graph of an hour has 720 points, and named keys would
        /// make it several times the size.
        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            second = try container.decode(Int.self)
            bpm = try container.decode(Int.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(second)
            try container.encode(bpm)
        }
    }

    /// A reading placed on the run's own clock: the time worked when it arrived. That clock stands
    /// still while the run is paused or waits for Start, so a pause between two readings is not
    /// time in a zone, and no reading of a run lies further out than the run's own length.
    public struct Sample: Hashable, Sendable {
        public let second: TimeInterval
        public let bpm: Int

        /// Made from a reading, so its heart rate is one the history file takes back.
        public init(_ reading: HeartRateReading, second: TimeInterval) {
            self.second = second
            bpm = reading.bpm
        }

        private init(second: TimeInterval, bpm: Int) {
            self.second = second
            self.bpm = bpm
        }

        func capped(at longest: TimeInterval) -> Sample {
            Sample(second: min(max(second, 0), longest), bpm: bpm)
        }
    }

    /// The graph has at most one point in this many seconds.
    public static let traceStep = 5
    /// Time from one reading to the next counts toward the zone of the first, unless the next
    /// came more than this much later. A pause or a lost signal is not time in a zone.
    public static let longestGap: TimeInterval = 10

    public let average: Int
    public let maximum: Int
    /// The setting when the run took place. The zones of this run were worked out with it.
    public let maxHeartRate: MaxHeartRate
    /// Seconds in each zone, indexed by `HeartRateZone.rawValue`.
    public let secondsInZone: [TimeInterval]
    public let trace: [Point]

    /// nil when there was no reading. A sample past `WorkoutRecord.longest` counts as being at it,
    /// so every summary this writes is one the history file reads back.
    public init?(_ samples: [Sample], maxHeartRate: MaxHeartRate) {
        guard !samples.isEmpty else { return nil }
        let readings = samples
            .map { $0.capped(at: WorkoutRecord.longest) }
            .sorted { $0.second < $1.second }
        let beats = readings.map(\.bpm)
        average = Self.mean(beats)
        maximum = beats.max() ?? 0
        self.maxHeartRate = maxHeartRate

        var seconds = Array(repeating: TimeInterval(0), count: HeartRateZone.allCases.count)
        for (reading, next) in zip(readings, readings.dropFirst()) {
            let gap = next.second - reading.second
            if gap <= Self.longestGap {
                seconds[maxHeartRate.zone(of: reading.bpm).rawValue] += gap
            }
        }
        secondsInZone = seconds.map { min($0, WorkoutRecord.longest) }

        var buckets: [(slot: Int, beats: [Int])] = []
        for reading in readings {
            let slot = Int(reading.second) / Self.traceStep
            if buckets.last?.slot == slot {
                buckets[buckets.count - 1].beats.append(reading.bpm)
            } else {
                buckets.append((slot, [reading.bpm]))
            }
        }
        trace = buckets.map { Point(second: $0.slot * Self.traceStep, bpm: Self.mean($0.beats)) }
    }

    public func seconds(in zone: HeartRateZone) -> TimeInterval {
        secondsInZone[zone.rawValue]
    }

    /// A damaged file is refused here, and the store sets it aside.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        average = try container.decode(Int.self, forKey: .average)
        maximum = try container.decode(Int.self, forKey: .maximum)
        maxHeartRate = try container.decode(MaxHeartRate.self, forKey: .maxHeartRate)
        secondsInZone = try container.decode([TimeInterval].self, forKey: .secondsInZone)
        trace = try container.decode([Point].self, forKey: .trace)
        func refuse(_ key: CodingKeys, _ what: String) -> DecodingError {
            .dataCorruptedError(forKey: key, in: container, debugDescription: what)
        }
        let bpm = HeartRateReading.plausible
        guard bpm.contains(average), bpm.contains(maximum), average <= maximum else {
            throw refuse(.average, "Not a heart rate: \(average) on average, \(maximum) at most.")
        }
        guard secondsInZone.count == HeartRateZone.allCases.count,
              secondsInZone.allSatisfy({ (0...WorkoutRecord.longest).contains($0) }) else {
            throw refuse(.secondsInZone, "Not a time in each zone: \(secondsInZone).")
        }
        guard trace.allSatisfy({ bpm.contains($0.bpm) && (0...Int(WorkoutRecord.longest)).contains($0.second) }) else {
            throw refuse(.trace, "A point of the graph is not a heart rate at a time in the run.")
        }
    }

    private static func mean(_ beats: [Int]) -> Int {
        Int((Double(beats.reduce(0, +)) / Double(beats.count)).rounded())
    }
}
