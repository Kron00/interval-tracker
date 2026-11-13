import Foundation
import IntervalCore
import Observation

@MainActor @Observable
final class LibraryStore {
    private(set) var library = Library()
    var problem: String?

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            library = try Library(json: Data(contentsOf: fileURL))
        } catch {
            let stamp = Int(Date.now.timeIntervalSince1970)
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("library.corrupt-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
                problem = "Your saved workouts could not be read. The file was kept as \(aside.lastPathComponent)."
            } catch {
                problem = "Your saved workouts could not be read, and the file could not be set aside."
            }
        }
    }

    func update(_ body: (inout Library) -> Void) {
        let before = library
        body(&library)
        guard library != before else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try library.json().write(to: fileURL, options: .atomic)
        } catch {
            problem = "Your change could not be saved: \(error.localizedDescription)"
        }
    }
}
