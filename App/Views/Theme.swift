import IntervalCore
import SwiftUI

enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.11)
    static let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
}

extension Tone {
    /// Vivid, for small marks on black.
    var tint: Color {
        switch self {
        case .prepare: Color(red: 1.00, green: 0.72, blue: 0.22)
        case .effort: Color(red: 1.00, green: 0.33, blue: 0.33)
        case .recover: Color(red: 0.33, green: 0.63, blue: 1.00)
        case .stretch: Color(red: 0.20, green: 0.84, blue: 0.72)
        case .cool: Color(red: 0.70, green: 0.52, blue: 1.00)
        }
    }

    /// Deep, so white text stays readable on a full-screen fill.
    var runColor: Color {
        switch self {
        case .prepare: Color(red: 0.68, green: 0.47, blue: 0.00)
        case .effort: Color(red: 0.76, green: 0.11, blue: 0.13)
        case .recover: Color(red: 0.09, green: 0.33, blue: 0.75)
        case .stretch: Color(red: 0.00, green: 0.46, blue: 0.50)
        case .cool: Color(red: 0.42, green: 0.26, blue: 0.64)
        }
    }
}

/// The whole workout as one bar, each phase a block as wide as its share of the time. A stretch
/// counted in reps has no time, so it is a marker of a fixed small width and takes nothing from the
/// share of the timed blocks.
/// With `elapsed` it is a progress bar. Without, each block takes its phase's colour.
struct TimelineStrip: View, Equatable {
    let spans: [PhaseSpan]
    var elapsed: TimeInterval?

    var body: some View {
        Canvas { context, size in
            let total = spans.reduce(0) { $0 + $1.duration }
            guard total > 0 else { return }
            let gap: CGFloat = size.width / CGFloat(spans.count) > 8 ? 3 : 0
            let marker = min(gap + 4, size.width / CGFloat(spans.count))
            let timedWidth = size.width - marker * CGFloat(spans.filter { $0.duration == 0 }.count)
            let radius = min(size.height / 2, 4)
            var start: TimeInterval = 0
            var x: CGFloat = 0
            for span in spans {
                let slot = span.duration == 0 ? marker : timedWidth * span.duration / total
                let width = max(1, slot - gap)
                let block = CGRect(x: x, y: 0, width: width, height: size.height)
                x += slot
                if let elapsed {
                    context.fill(Path(roundedRect: block, cornerRadius: radius), with: .color(.white.opacity(0.28)))
                    // A marker fills when the run reaches it.
                    let done = span.duration == 0 ? (elapsed >= start ? 1 : 0) : min(max((elapsed - start) / span.duration, 0), 1)
                    if done > 0 {
                        var filled = block
                        filled.size.width = width * done
                        context.fill(Path(roundedRect: filled, cornerRadius: radius), with: .color(.white))
                    }
                } else {
                    context.fill(Path(roundedRect: block, cornerRadius: radius), with: .color(span.phase.tone.tint))
                }
                start += span.duration
            }
        }
        .accessibilityHidden(true)
    }
}
