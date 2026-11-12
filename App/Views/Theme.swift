import IntervalCore
import SwiftUI

enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.11)
    static let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    static let warmUp = Color(red: 1.00, green: 0.72, blue: 0.22)
    static let work = Color(red: 1.00, green: 0.33, blue: 0.33)
    static let rest = Color(red: 0.33, green: 0.63, blue: 1.00)
    static let coolDown = Color(red: 0.70, green: 0.52, blue: 1.00)
}

extension Phase {
    /// Vivid, for small marks on black.
    var tint: Color {
        switch self {
        case .warmUp: Theme.warmUp
        case .work: Theme.work
        case .rest: Theme.rest
        case .coolDown: Theme.coolDown
        }
    }
}

/// The whole workout as one bar, each phase a block as wide as its share of the time.
/// With `elapsed` it is a progress bar. Without, each block takes its phase's colour.
struct TimelineStrip: View, Equatable {
    let spans: [PhaseSpan]
    var elapsed: TimeInterval?

    var body: some View {
        Canvas { context, size in
            let total = spans.reduce(0) { $0 + $1.duration }
            guard total > 0 else { return }
            let gap: CGFloat = size.width / CGFloat(spans.count) > 8 ? 3 : 0
            let radius = min(size.height / 2, 4)
            var start: TimeInterval = 0
            for span in spans {
                let x = size.width * start / total
                let width = max(1, size.width * span.duration / total - gap)
                let block = CGRect(x: x, y: 0, width: width, height: size.height)
                if let elapsed {
                    context.fill(Path(roundedRect: block, cornerRadius: radius), with: .color(.white.opacity(0.28)))
                    let done = min(max((elapsed - start) / span.duration, 0), 1)
                    if done > 0 {
                        var filled = block
                        filled.size.width = width * done
                        context.fill(Path(roundedRect: filled, cornerRadius: radius), with: .color(.white))
                    }
                } else {
                    context.fill(Path(roundedRect: block, cornerRadius: radius), with: .color(span.phase.tint))
                }
                start += span.duration
            }
        }
        .accessibilityHidden(true)
    }
}
