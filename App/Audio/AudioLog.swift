import Foundation
import Observation

@MainActor @Observable
final class AudioLog {
    private(set) var lines: [String] = []
    /// True while the player is failing to start audio, so the run screen can say the cues are silent.
    var cuesAreSilent = false

    private static let capacity = 200
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func note(_ line: String) {
        lines.append("\(Self.clock.string(from: .now)) \(line)")
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }
}
