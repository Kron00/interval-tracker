import Foundation
import IntervalCore
import Observation

/// The history has a file of its own. A history file that cannot be read is set aside like a bad
/// library file, and it never takes the saved workouts with it.
@MainActor @Observable
final class HistoryStore {
    private(set) var history = History()
    var problem: String?

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            history = try History(json: Data(contentsOf: fileURL))
        } catch {
            let stamp = Int(Date.now.timeIntervalSince1970)
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("history.corrupt-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
                problem = "Your workout history could not be read. The file was kept as \(aside.lastPathComponent)."
            } catch {
                problem = "Your workout history could not be read, and the file could not be set aside."
            }
        }
    }

    /// The audio check in Settings is a test of the phone, not a workout, so it is left out.
    func record(_ record: WorkoutRecord) {
        guard record.workoutID != Workout.audioCheck.id else { return }
        update { $0.add(record) }
    }

    func update(_ body: (inout History) -> Void) {
        let before = history
        body(&history)
        guard history != before else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try history.json().write(to: fileURL, options: .atomic)
        } catch {
            problem = "Your history could not be saved: \(error.localizedDescription)"
        }
    }
}
