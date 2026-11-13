import ActivityKit
import SwiftUI
import WidgetKit

extension RunActivityAttributes: ActivityAttributes {}

@main
struct IntervalTrackerWidgets: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenCard(name: context.attributes.workoutName, state: context.state)
                .activityBackgroundTint(context.state.tone.fill)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.workoutName)
                        .modifier(IslandLabel())
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.caption ?? "")
                        .modifier(IslandLabel())
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(alignment: .center, spacing: 12) {
                            PhaseTitle(text: state.title, size: 28)
                                .foregroundStyle(state.tone.tint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ClockFace(clock: state.clock, size: 44, sizeOfLongText: 30)
                                .foregroundStyle(Color.white)
                        }
                        PhaseBar(clock: state.clock, fill: state.tone.tint)
                        StatusRow(state: state)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Dial(state: state)
            } compactTrailing: {
                ClockFace(clock: state.clock, size: 15, sizeOfLongText: 15)
                    .foregroundStyle(state.isHeadsUp ? Color.white : state.tone.tint)
            } minimal: {
                Dial(state: state)
            }
            .keylineTint(state.tone.tint)
        }
    }
}

/// The same block of colour as the run screen: the phase's deep fill, white text, and the clock as
/// the largest thing on it.
private struct LockScreenCard: View {
    let name: String
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    // The caption says which stretch and which side this is. Where it and the
                    // workout's name do not fit on one line, the name gives way.
                    ViewThatFits(in: .horizontal) {
                        Text([name, state.caption].compactMap { $0 }.joined(separator: " · "))
                        Text(state.caption ?? name)
                    }
                    .font(.footnote.weight(.semibold))
                    .opacity(0.8)
                    .lineLimit(1)
                    PhaseTitle(text: state.title, size: 30)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ClockFace(clock: state.clock, size: 52, sizeOfLongText: 36)
            }
            PhaseBar(clock: state.clock, fill: Color.white)
            StatusRow(state: state)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [state.tone.fill, state.tone.fill.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .background(Color.black)
        }
    }
}

/// A phase name is one big line. A stretch name can be 40 characters, so it is set smaller on two.
private struct PhaseTitle: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let isLong = text.count > 12
        Text(text.uppercased())
            .font(.system(size: isLong ? size * 0.7 : size, weight: .heavy, design: .rounded))
            .lineLimit(isLong ? 2 : 1)
            .minimumScaleFactor(0.6)
            // The system offers a Live Activity less height than it may take, and the title would
            // shrink to fit the offer.
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The small lines beside the camera in the expanded Dynamic Island.
private struct IslandLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// The countdown, or what stands in its place while nothing counts.
private struct ClockFace: View {
    let clock: RunActivityAttributes.Clock
    let size: CGFloat
    /// "10 reps" and "1:00:00" are wider than "4:00", and at full size they would crowd out the title.
    let sizeOfLongText: CGFloat

    var body: some View {
        switch clock {
        case .counting(let from, let to):
            // A timer text takes all the width it is offered. The hidden text is the widest this
            // countdown gets, so the clock is exactly that wide and the title keeps the rest.
            let widest = Self.widest(to.timeIntervalSince(from))
            Text(widest)
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(timerInterval: from...to, countsDown: true)
                        .multilineTextAlignment(.trailing)
                }
                .font(font(for: widest))
                .monospacedDigit()
                .lineLimit(1)
        case .paused(let text), .waiting(let text, _, _), .finished(let text):
            Text(text)
                .font(font(for: text))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func font(for text: String) -> Font {
        .system(size: text.count > 5 ? sizeOfLongText : size, weight: .bold, design: .rounded)
    }

    private static func widest(_ length: TimeInterval) -> String {
        length >= 3600 ? "0:00:00" : length >= 600 ? "00:00" : "0:00"
    }
}

/// How far the phase has got. The system moves it, like the countdown.
private struct PhaseBar: View {
    let clock: RunActivityAttributes.Clock
    let fill: Color

    var body: some View {
        switch clock {
        case .counting(let from, let to):
            ProgressView(timerInterval: from...to, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.linear)
                .tint(fill)
        case .paused, .waiting(_, for: .start, _):
            ProgressView(value: 0)
                .tint(fill)
        case .waiting(_, for: .next, _), .finished:
            ProgressView(value: 1)
                .tint(fill)
        }
    }
}

/// The one thing to know about the run's state, when there is one, and what comes next. A waiting
/// run has the button that moves it on where the others have a badge.
private struct StatusRow: View {
    let state: RunActivityAttributes.ContentState

    /// The height of the button. The row takes it in every state, so a card is as tall with a
    /// badge as it is with the button.
    private static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            if case .waiting(_, let advance, let wait) = state.clock {
                Button(intent: AdvanceRunIntent(wait: wait)) {
                    Label(advance.title, systemImage: advance.symbol)
                        .font(.subheadline.weight(.heavy))
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 96, minHeight: Self.height)
                        .foregroundStyle(Color.black)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            } else if let status = state.status {
                Label(status.text.uppercased(), systemImage: status.symbol)
                    .font(.caption.weight(.heavy))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .foregroundStyle(status.isUrgent ? Color.black : Color.white)
                    .background(status.isUrgent ? Color.white : Color.white.opacity(0.22), in: Capsule())
                Spacer(minLength: 0)
            }
            if let upNext = state.upNext {
                Text("Up next: \(upNext)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if state.status == nil, !state.isWaiting {
                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.height)
    }
}

/// The compact and minimal Dynamic Island: a ring that empties with the phase, or a symbol for a
/// run that is not counting.
private struct Dial: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if case .counting(let from, let to) = state.clock, !state.isHeadsUp {
            ProgressView(timerInterval: from...to, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.circular)
                .tint(state.tone.tint)
        } else {
            Image(systemName: state.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(state.isHeadsUp ? Color.white : state.tone.tint)
        }
    }
}

private struct Status: Equatable {
    let text: String
    let symbol: String
    /// Drawn black on white, so it is the first thing seen.
    var isUrgent = false
}

private extension RunActivityAttributes.Advance {
    var title: String {
        switch self {
        case .start: "Start"
        case .next: "Next"
        }
    }

    var symbol: String {
        switch self {
        case .start: "play.fill"
        case .next: "forward.end.fill"
        }
    }
}

private extension RunActivityAttributes.ContentState {
    /// The badge. A waiting run has none, because its button says what it waits for.
    var status: Status? {
        switch clock {
        case .counting: isHeadsUp ? Status(text: "Get ready", symbol: "bell.fill", isUrgent: true) : nil
        case .paused: Status(text: "Paused", symbol: "pause.fill")
        case .waiting: nil
        case .finished: Status(text: "Time worked", symbol: "checkmark")
        }
    }

    var isWaiting: Bool {
        if case .waiting = clock { true } else { false }
    }

    /// What the compact Dynamic Island draws for a run that is not counting.
    var symbol: String {
        if case .waiting(_, let advance, _) = clock { advance.symbol } else { status?.symbol ?? "timer" }
    }
}
