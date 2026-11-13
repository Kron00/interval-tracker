import SwiftUI

extension RunActivityAttributes {
    /// The heart rate on the card. Only a run with a remembered monitor has one.
    enum HeartRate: Codable, Hashable {
        case reading(bpm: Int, zone: ZoneTone)
        /// No fresh reading, or no link to the monitor. The card shows a dash.
        case dash

        /// nil for a dash, so going stale and coming back count as a change of zone.
        var zone: ZoneTone? {
            if case .reading(_, let zone) = self { zone } else { nil }
        }
    }
}

/// The colour of a heart-rate zone, on the run screen, the card and in History. Cool to hot, and
/// apart from the phase colours, because a zone is shown on top of a phase.
enum ZoneTone: String, Codable, Hashable, CaseIterable {
    case below, one, two, three, four, five

    var tint: Color {
        switch self {
        case .below: Color(red: 0.80, green: 0.82, blue: 0.86)
        case .one: Color(red: 0.45, green: 0.90, blue: 1.00)
        case .two: Color(red: 0.60, green: 0.92, blue: 0.30)
        case .three: Color(red: 1.00, green: 0.90, blue: 0.25)
        case .four: Color(red: 1.00, green: 0.52, blue: 0.16)
        case .five: Color(red: 1.00, green: 0.30, blue: 0.62)
        }
    }

    var label: String {
        switch self {
        case .below: "Below zone 1"
        case .one: "Zone 1"
        case .two: "Zone 2"
        case .three: "Zone 3"
        case .four: "Zone 4"
        case .five: "Zone 5"
        }
    }
}
