import Foundation

/// One run of a workout, as the history keeps it. The name and the kind are copies, so an entry
/// reads the same after its workout is renamed or deleted.
public struct WorkoutRecord: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case intervals, routine
    }

    public enum Outcome: String, Hashable, Sendable, Codable {
        case completed, endedEarly
    }

    public let id: UUID
    public let startedAt: Date
    public let workoutID: Workout.ID
    public let name: String
    public let kind: Kind
    /// The figure the finish screen shows. Paused time, skipped time and waits for Start are not in it.
    public let worked: TimeInterval
    /// The workout's timed length when the run started.
    public let planned: TimeInterval
    public let outcome: Outcome
    /// nil for a run with no heart-rate reading, and for every run that versions before 1.4 wrote.
    public let heartRate: HeartRateSummary?

    /// No run is recorded as longer than this. A routine left waiting on a stretch counted in reps
    /// keeps counting until it is ended, which can be days later.
    public static let longest: TimeInterval = 7 * 24 * 3600

    /// A length outside `0...longest` becomes the nearer end of that range.
    public init(id: UUID = UUID(), startedAt: Date, workoutID: Workout.ID, name: String, kind: Kind,
                worked: TimeInterval, planned: TimeInterval, outcome: Outcome, heartRate: HeartRateSummary? = nil) {
        self.id = id; self.startedAt = startedAt; self.workoutID = workoutID; self.name = name
        self.kind = kind; self.outcome = outcome; self.heartRate = heartRate
        self.worked = min(max(worked, 0), Self.longest)
        self.planned = min(max(planned, 0), Self.longest)
    }

    /// A file can hold any number. One that is not a length or not a date would crash the screen
    /// that formats it, so the file is refused here and the store sets it aside.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        workoutID = try container.decode(Workout.ID.self, forKey: .workoutID)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(Kind.self, forKey: .kind)
        worked = try container.decode(TimeInterval.self, forKey: .worked)
        planned = try container.decode(TimeInterval.self, forKey: .planned)
        outcome = try container.decode(Outcome.self, forKey: .outcome)
        heartRate = try container.decodeIfPresent(HeartRateSummary.self, forKey: .heartRate)
        guard (0...Self.longest).contains(worked) else {
            throw DecodingError.dataCorruptedError(forKey: .worked, in: container, debugDescription: "Not a length: \(worked).")
        }
        guard (0...Self.longest).contains(planned) else {
            throw DecodingError.dataCorruptedError(forKey: .planned, in: container, debugDescription: "Not a length: \(planned).")
        }
        guard Self.plausibleDates.contains(startedAt) else {
            throw DecodingError.dataCorruptedError(forKey: .startedAt, in: container, debugDescription: "Not a date: \(startedAt).")
        }
    }

    /// From 2001 to about 2318. Outside it a number is not a date this app wrote.
    private static let plausibleDates = Date(timeIntervalSinceReferenceDate: 0)...Date(timeIntervalSinceReferenceDate: 10_000_000_000)

    /// What `session` amounts to when its run is over at `now`: completed if it has finished, and
    /// ended early with the time worked so far if it has not.
    public init(_ session: Session, startedAt: Date, endedAt now: Date, heartRate: HeartRateSummary? = nil) {
        let isFinished = if case .finished = session.snapshot(at: now) { true } else { false }
        self.init(
            startedAt: startedAt, workoutID: session.workout.id, name: session.workout.name,
            kind: session.workout.plan.kind, worked: session.worked(at: now),
            planned: session.workout.totalDuration, outcome: isFinished ? .completed : .endedEarly,
            heartRate: heartRate)
    }
}

extension Plan {
    public var kind: WorkoutRecord.Kind {
        switch self {
        case .intervals: .intervals
        case .routine: .routine
        }
    }
}

public struct History: Equatable, Sendable {
    /// Newest first.
    public private(set) var records: [WorkoutRecord] = []

    public static let limit = 1000
    /// A run ended before this much work was a false start, and is not kept.
    public static let minimumWork: TimeInterval = 60

    public struct Day: Identifiable, Equatable, Sendable {
        /// The start of the day in the calendar that grouped it.
        public let date: Date
        public let records: [WorkoutRecord]
        public var id: Date { date }
    }

    public struct Summary: Equatable, Sendable {
        public let workouts: Int
        public let worked: TimeInterval
    }

    public init() {}

    /// Parses the versioned file format. Throws on any other version.
    public init(json: Data) throws {
        records = Self.newestFirst(try JSONDecoder().decode(File.self, from: json).records)
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(records: records))
    }

    /// Whether the history keeps a run with this outcome and this much work: every completed run,
    /// and a run ended early only after `minimumWork`. `add` goes by it, and so does the line that
    /// tells a user what ending a run will do.
    public static func keeps(_ outcome: WorkoutRecord.Outcome, worked: TimeInterval) -> Bool {
        outcome == .completed || worked >= minimumWork
    }

    /// Adds a run that `keeps` lets in. The oldest entries make room once there are more than `limit`.
    public mutating func add(_ record: WorkoutRecord) {
        guard Self.keeps(record.outcome, worked: record.worked) else { return }
        records = Self.newestFirst(records + [record])
    }

    public mutating func delete(_ id: WorkoutRecord.ID) {
        records.removeAll { $0.id == id }
    }

    public mutating func clear() {
        records = []
    }

    /// The entries by the day each run started on in `calendar`, newest day first.
    public func days(in calendar: Calendar) -> [Day] {
        var days: [Day] = []
        for record in records {
            let date = calendar.startOfDay(for: record.startedAt)
            if let last = days.last, last.date == date {
                days[days.count - 1] = Day(date: date, records: last.records + [record])
            } else {
                days.append(Day(date: date, records: [record]))
            }
        }
        return days
    }

    /// The runs that started in the week `now` is in. `calendar` says which day a week starts on.
    public func summary(ofWeekContaining now: Date, in calendar: Calendar) -> Summary {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return Summary(workouts: 0, worked: 0)
        }
        let records = records.filter { week.start <= $0.startedAt && $0.startedAt < week.end }
        return Summary(workouts: records.count, worked: records.reduce(0) { $0 + $1.worked })
    }

    private static func newestFirst(_ records: [WorkoutRecord]) -> [WorkoutRecord] {
        Array(records.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    /// Dates are written as Foundation writes them, in seconds since 2001, because that value
    /// reads back as the same instant to the last bit.
    private struct File: Codable {
        static let currentVersion = 1

        var version = File.currentVersion
        var records: [WorkoutRecord]

        init(records: [WorkoutRecord]) {
            self.records = records
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            guard version == File.currentVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version, in: container,
                    debugDescription: "Unsupported history version \(version).")
            }
            records = try container.decode([WorkoutRecord].self, forKey: .records)
        }
    }
}
