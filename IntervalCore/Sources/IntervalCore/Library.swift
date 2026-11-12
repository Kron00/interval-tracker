import Foundation

public struct Library: Equatable, Sendable {
    /// User timers only, in display order. Built-ins come from `TimerDefinition.builtIn`.
    public private(set) var timers: [TimerDefinition] = []
    public var cues = CuePreferences()

    public init() {}

    /// Parses the versioned file format. Throws on unknown version or any invalid value (e.g. `"work": 0`).
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        timers = file.timers
        cues = file.cues
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(timers: timers, cues: cues))
    }

    /// Inserts, or replaces the timer with the same id. Saving a built-in id forks it under a fresh id.
    @discardableResult
    public mutating func save(_ timer: TimerDefinition) -> TimerDefinition {
        guard !TimerDefinition.builtIn.contains(where: { $0.id == timer.id }) else {
            return save(TimerDefinition(
                name: timer.name, warmUp: timer.warmUp, work: timer.work, rest: timer.rest,
                rounds: timer.rounds, coolDown: timer.coolDown,
                restAfterLastRound: timer.restAfterLastRound))
        }
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers[index] = timer
        } else {
            timers.append(timer)
        }
        return timer
    }

    public mutating func delete(_ id: TimerDefinition.ID) {
        timers.removeAll { $0.id == id }
    }

    private struct File: Codable {
        static let currentVersion = 1

        var version = File.currentVersion
        var timers: [TimerDefinition]
        var cues: CuePreferences

        init(timers: [TimerDefinition], cues: CuePreferences) {
            self.timers = timers
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
            timers = try container.decode([TimerDefinition].self, forKey: .timers)
            cues = try container.decode(CuePreferences.self, forKey: .cues)
        }
    }
}
