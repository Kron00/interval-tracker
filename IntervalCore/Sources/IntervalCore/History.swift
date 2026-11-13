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

    public init(id: UUID = UUID(), startedAt: Date, workoutID: Workout.ID, name: String, kind: Kind,
                worked: TimeInterval, planned: TimeInterval, outcome: Outcome) {
        self.id = id; self.startedAt = startedAt; self.workoutID = workoutID; self.name = name
        self.kind = kind; self.worked = worked; self.planned = planned; self.outcome = outcome
    }

    /// What `session` amounts to when its run is over at `now`: completed if it has finished, and
    /// ended early with the time worked so far if it has not.
    public init(_ session: Session, startedAt: Date, endedAt now: Date) {
        let isFinished = if case .finished = session.snapshot(at: now) { true } else { false }
        self.init(
            startedAt: startedAt, workoutID: session.workout.id, name: session.workout.name,
            kind: session.workout.plan.kind, worked: session.worked(at: now),
            planned: session.workout.totalDuration, outcome: isFinished ? .completed : .endedEarly)
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

    /// Keeps every completed run, and a run ended early only after `minimumWork`. The oldest
    /// entries make room once there are more than `limit`.
    public mutating func add(_ record: WorkoutRecord) {
        guard record.outcome == .completed || record.worked >= Self.minimumWork else { return }
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
