import Foundation

public struct Library: Equatable, Sendable {
    /// User workouts only, in display order. Built-ins come from `Workout.builtIn`.
    public private(set) var workouts: [Workout] = []
    public var cues = CuePreferences()

    public init() {}

    /// Parses the versioned file format. Throws on any other version and on any invalid value
    /// (e.g. `"work": 0`). Version 1 never shipped, so nothing migrates it.
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        workouts = file.workouts
        cues = file.cues
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(workouts: workouts, cues: cues))
    }

    /// Inserts, or replaces the workout with the same id. Saving a built-in id forks it under a fresh id.
    @discardableResult
    public mutating func save(_ workout: Workout) -> Workout {
        guard !Workout.builtIn.contains(where: { $0.id == workout.id }) else {
            return save(workout.forked())
        }
        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = workout
        } else {
            workouts.append(workout)
        }
        return workout
    }

    public mutating func delete(_ id: Workout.ID) {
        workouts.removeAll { $0.id == id }
    }

    private struct File: Codable {
        static let currentVersion = 2

        var version = File.currentVersion
        var workouts: [Workout]
        var cues: CuePreferences

        init(workouts: [Workout], cues: CuePreferences) {
            self.workouts = workouts
            self.cues = cues
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            guard version == File.currentVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version, in: container,
                    debugDescription: "Unsupported library version \(version).")
            }
            workouts = try container.decode([Workout].self, forKey: .workouts)
            cues = try container.decode(CuePreferences.self, forKey: .cues)
        }
    }
}
