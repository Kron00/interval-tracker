import SwiftUI

/// What the Live Activity shows. The app and the widget extension both compile this file, and it is
/// all the extension knows about a run.
struct RunActivityAttributes: Codable, Hashable {
    struct ContentState: Codable, Hashable {
        var title: String
        var caption: String?
        /// nil once the workout has finished.
        var upNext: String?
        var tone: RunTone
        var clock: Clock
        /// Work begins when the phase ends, and it is time to say so.
        var isHeadsUp: Bool
    }

    /// What stands where the clock is.
    enum Clock: Codable, Hashable {
        /// The system draws the countdown from these two dates and ticks it by itself.
        case counting(from: Date, to: Date)
        case paused(String)
        /// A rep count, or the length of the hold that Start begins.
        case waiting(String, for: Advance)
        /// The time worked.
        case finished(String)
    }

    /// The tap a waiting run waits for.
    enum Advance: String, Codable, Hashable {
        case start, next
    }

    var workoutName: String
}

/// The colour family a run is drawn in, on the run screen and in the Live Activity.
enum RunTone: String, Codable, Hashable, CaseIterable {
    case prepare, effort, recover, stretch, cool, paused, finished

    /// Vivid, for small marks on black.
    var tint: Color {
        switch self {
        case .prepare: Color(red: 1.00, green: 0.72, blue: 0.22)
        case .effort: Color(red: 1.00, green: 0.33, blue: 0.33)
        case .recover: Color(red: 0.33, green: 0.63, blue: 1.00)
        case .stretch: Color(red: 0.20, green: 0.84, blue: 0.72)
        case .cool: Color(red: 0.70, green: 0.52, blue: 1.00)
        case .paused: Color(red: 0.72, green: 0.75, blue: 0.80)
        case .finished: Color(red: 0.20, green: 0.83, blue: 0.56)
        }
    }

    /// Deep, so white text stays readable on a fill.
    var fill: Color {
        switch self {
        case .prepare: Color(red: 0.68, green: 0.47, blue: 0.00)
        case .effort: Color(red: 0.76, green: 0.11, blue: 0.13)
        case .recover: Color(red: 0.09, green: 0.33, blue: 0.75)
        case .stretch: Color(red: 0.00, green: 0.46, blue: 0.50)
        case .cool: Color(red: 0.42, green: 0.26, blue: 0.64)
        case .paused: Color(red: 0.26, green: 0.28, blue: 0.31)
        case .finished: Color(red: 0.02, green: 0.35, blue: 0.25)
        }
    }
}
