import IntervalCore
import SwiftUI

struct RunScreen: View {
    let run: RunModel
    let session: Session
    let log: AudioLog
    private let outline: [PhaseSpan]

    init(run: RunModel, session: Session, log: AudioLog) {
        self.run = run
        self.session = session
        self.log = log
        outline = session.workout.outline
    }

    var body: some View {
        // Read out here. A paused or waiting run has no tick left to notice a change with.
        let undo: (() -> Void)? = run.undo == nil ? nil : { run.undoLast() }
        let cuesAreSilent = log.cuesAreSilent
        // The readout observes the monitor itself, so a reading redraws it and nothing else.
        let heartRate = run.heartRate.remembered == nil ? nil : run.heartRate
        TimelineView(RunTicks(zero: session.zeroDate, halt: session.haltDate)) { context in
            let snapshot = session.snapshot(at: context.date)
            let tone = RunTone(snapshot)
            ZStack {
                LinearGradient(colors: [tone.fill, tone.fill.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: tone)
                switch snapshot {
                case .active(let progress):
                    ActiveRunView(
                        name: session.workout.name,
                        progress: progress,
                        outline: outline,
                        cuesAreSilent: cuesAreSilent,
                        heartRate: heartRate,
                        pause: run.pause,
                        resume: run.resume,
                        skip: { run.skip(progress.segment) },
                        restart: { run.restart(progress.segment) },
                        undo: undo,
                        end: run.end,
                        endIsKept: HistoryStore.records(session.workout.id)
                            ? { History.keeps(.endedEarly, worked: session.worked(at: $0)) } : nil)
                case .finished(let worked):
                    FinishedView(name: session.workout.name, worked: worked, undo: undo, close: run.end)
                }
            }
        }
        .foregroundStyle(Color.white)
        .preferredColorScheme(.dark)
    }
}

/// The whole seconds after `zero`, up to `halt`. Nothing on the screen changes at any other time, so
/// a run that is paused, waiting or finished is drawn once and not again.
private struct RunTicks: TimelineSchedule {
    let zero: Date?
    let halt: Date?

    func entries(from start: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        // A paused run has one thing to show, as if it had halted now.
        let halt = halt ?? start
        let latest = zero.map { $0 + max(0, start.timeIntervalSince($0).rounded(.down)) } ?? start
        return sequence(first: min(latest, halt)) { date in
            if date < halt { return min(date + 1, halt) }
            // TimelineView does not draw the last entry of a schedule that ends. With the halt as the
            // last entry, the screen stayed one second short of every wait. So a date that never
            // comes follows the halt.
            return date < .distantFuture ? .distantFuture : nil
        }
    }
}

private enum Motion {
    static let change = Animation.easeInOut(duration: 0.25)
    static let chip = AnyTransition.opacity.combined(with: .scale(scale: 0.9))
}

/// Nothing here changes place when the run changes state. Every block has a fixed height and the clock
/// takes what is left, so a pause, a skip or a chip changes only what is drawn inside a block.
struct ActiveRunView: View {
    let name: String
    let progress: RunProgress
    let outline: [PhaseSpan]
    let cuesAreSilent: Bool
    /// nil while no heart-rate monitor is remembered, and then the readout has no slot.
    let heartRate: HeartRateMonitor?
    let pause: () -> Void
    let resume: () -> Void
    let skip: () -> Void
    let restart: () -> Void
    let undo: (() -> Void)?
    let end: () -> Void
    /// Whether the history keeps the run if it is ended at a date. nil for a run that is never recorded.
    let endIsKept: ((Date) -> Bool)?

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.openURL) private var openURL
    @State private var confirmingEnd = false

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isLandscape {
                HStack(spacing: 24) {
                    VStack(spacing: 8) {
                        clock
                        waitLine
                        heartRateLine
                        chips
                    }
                    VStack(spacing: 6) {
                        header
                        captionLine
                        upNextLine
                        Spacer(minLength: 0)
                        overall
                        controls
                    }
                    .frame(maxWidth: 372)
                }
            } else {
                VStack(spacing: 12) {
                    header
                    clock
                    VStack(spacing: 6) {
                        captionLine
                        upNextLine
                        waitLine
                    }
                    heartRateLine
                    overall
                    chips
                    controls
                }
            }
        }
        .padding(20)
        .overlay {
            if confirmingEnd { endConfirmation }
        }
        .animation(.easeOut(duration: 0.15), value: confirmingEnd)
    }

    /// Drawn by the app, not as a system alert: on iOS 27 an alert is translucent glass, and over the
    /// red Work screen its red destructive button was hard to read.
    private var endConfirmation: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { confirmingEnd = false }
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    Text("End this workout?")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    if let endIsKept {
                        // The answer changes while the dialog is open, and a waiting or paused
                        // run screen is not redrawn. So the line keeps its own time.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(endIsKept(context.date)
                                ? "It will be saved to History as ended early."
                                : "Under a minute of work, so it won't be saved to History.")
                                .font(.system(.body, design: .rounded))
                                .multilineTextAlignment(.center)
                                .lineLimit(2, reservesSpace: true)
                                .opacity(0.8)
                                .accessibilityIdentifier("endHistoryNote")
                        }
                    }
                }
                .padding(.bottom, 6)
                Button("Keep going") { confirmingEnd = false }
                    .buttonStyle(RunButtonStyle(isProminent: true))
                    .accessibilityIdentifier("keepGoingButton")
                Button("End workout", action: end)
                    .buttonStyle(RunButtonStyle(isProminent: false, fill: Tone.effort.tint))
                    .accessibilityIdentifier("confirmEndButton")
            }
            .padding(22)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .frame(maxWidth: 420)
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
        .transition(.opacity)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Line(font: .headline) {
                Text(name).opacity(0.8)
            }
            title
            Line(font: (isLandscape ? Font.title3 : .title2).weight(.semibold)) {
                if progress.isPaused {
                    Text("in \(progress.phase.title)")
                        .opacity(0.85)
                        .transition(.opacity)
                }
            }
            .animation(Motion.change, value: progress.isPaused)
        }
        .overlay(alignment: .top) {
            if cuesAreSilent {
                Label("No sound. Audio could not start. Retrying.", systemImage: "speaker.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .transition(.opacity)
                    .accessibilityIdentifier("audioWarning")
            }
        }
        .animation(Motion.change, value: cuesAreSilent)
    }

    /// The slot is two smaller lines tall. A phase name fills it as one big line, and a stretch name,
    /// which can be 40 characters, wraps onto both.
    private var title: some View {
        let text = progress.isPaused ? "PAUSED" : progress.phase.title.uppercased()
        let isLong = text.count > 12
        return Text("A\nA")
            .font(.system(size: isLandscape ? 26 : 44, weight: .heavy, design: .rounded))
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay {
                Text(text)
                    .font(.system(size: isLandscape ? 44 : 64, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(isLong ? 2 : 1)
                    .minimumScaleFactor(0.3)
                    .contentTransition(.opacity)
            }
            .animation(Motion.change, value: text)
            .contentShape(.accessibility, Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("phaseTitle")
    }

    /// The clock, or what stands in its place while the run waits.
    private var clock: some View {
        ZStack {
            switch Face(progress) {
            case .time:
                // The hidden text is the phase's full length, so the digits keep one size for the whole phase.
                // The digits cut from one second to the next. Rolling them with `numericText` took a running
                // timer from 3% of a core to 71% in the simulator.
                Text(ClockText.remaining(progress.phaseDuration))
                    .hidden()
                    .overlay {
                        Text(ClockText.remaining(progress.phaseRemaining))
                            .accessibilityIdentifier("timeRemaining")
                    }
            case .reps(let count):
                Text("\(Text("\(count.value)"))\(Text(" \(count.repsUnit)").font(Self.unitFont))")
                    .accessibilityIdentifier("repCount")
            case .length(let length):
                // Dimmed, so a clock that has not started does not read as one that has stopped.
                Text(ClockText.remaining(length))
                    .opacity(0.6)
                    .accessibilityIdentifier("holdLength")
            }
        }
        .font(.system(size: 320, weight: .bold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.05)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.accessibility, Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clock")
    }

    private static let unitFont = Font.system(size: 110, weight: .bold, design: .rounded)

    private var captionLine: some View {
        Line(font: .system(size: isLandscape ? 28 : 34, weight: .semibold, design: .rounded)) {
            if let caption = progress.caption {
                Text(caption)
                    .contentTransition(.opacity)
                    .transition(.opacity)
                    .accessibilityIdentifier("roundLabel")
            }
        }
        .animation(Motion.change, value: progress.caption)
    }

    private var upNextLine: some View {
        let text = "Up next: \(progress.upNextText)"
        return Line(font: .title2.weight(.medium)) {
            Text(text)
                .opacity(0.85)
                .contentTransition(.opacity)
        }
        .animation(Motion.change, value: text)
    }

    private var waitLine: some View {
        let prompt = progress.isWaiting && !progress.isPaused
            ? (progress.reps == nil ? "Tap Start" : "Tap Next when done") : nil
        return Line(font: .system(size: 34, weight: .bold, design: .rounded), padding: 6) {
            if let prompt {
                Text(prompt)
                    .contentTransition(.opacity)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2), in: Capsule())
                    .transition(Motion.chip)
                    .accessibilityIdentifier("waitPrompt")
            }
        }
        .animation(Motion.change, value: prompt)
    }

    @ViewBuilder
    private var heartRateLine: some View {
        if let heartRate { HeartRateReadout(monitor: heartRate) }
    }

    private var overall: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total left")
                    .font(.title3.weight(.medium))
                    .opacity(0.85)
                Spacer()
                Text(ClockText.remaining(progress.totalRemaining))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("totalRemaining")
            }
            TimelineStrip(spans: outline, elapsed: progress.elapsed)
                .frame(height: 8)
        }
    }

    private var chips: some View {
        // A countdown leaves no time for a video. A pause and a wait do, and nothing counts in either.
        let link = progress.isPaused || progress.isWaiting ? progress.phase.howTo : nil
        return HStack(spacing: 12) {
            RunChip(title: "How to", symbol: "play.circle.fill", identifier: "howToButton", action: link.map { link in
                { openURL(link) }
            })
            RunChip(title: "Undo", symbol: "arrow.uturn.backward", identifier: "undoButton", action: undo)
        }
    }

    /// Laid out like a music player, because the headphone presses mean the same things: previous
    /// restarts, play and pause, next moves on. While the run waits, Start or Next takes the big
    /// button. A wait has nothing to restart or to skip, so the small buttons beside it go dim and
    /// the one thing left to do is the only thing to hit.
    private var controls: some View {
        let primary = Primary(progress)
        let advanceIsPrimary = primary.advances
        return HStack(spacing: 12) {
            iconButton("End", "xmark", identifier: "endButton") { confirmingEnd = true }
            iconButton("Restart", "backward.end.fill", identifier: "restartButton", action: restart)
                .disabled(progress.isWaiting)
                .opacity(progress.isWaiting ? 0.3 : 1)
                .animation(Motion.change, value: progress.isWaiting)

            Button(action: action(for: primary)) {
                HStack(spacing: 8) {
                    Image(systemName: primary.symbol)
                        .contentTransition(.symbolEffect(.replace))
                    Text(primary.title)
                        .contentTransition(.opacity)
                }
                .animation(Motion.change, value: primary)
            }
            .buttonStyle(RunButtonStyle(isProminent: true))
            .accessibilityIdentifier("primaryButton")

            iconButton(progress.phase.advanceTitle, "forward.end.fill", identifier: "skipButton", action: skip)
                .disabled(advanceIsPrimary)
                .opacity(advanceIsPrimary ? 0.3 : 1)
                .accessibilityHidden(advanceIsPrimary)
                .animation(Motion.change, value: advanceIsPrimary)
        }
    }

    private func action(for primary: Primary) -> () -> Void {
        switch primary {
        case .pause: pause
        case .resume: resume
        case .start, .next: skip
        }
    }

    private func iconButton(_ title: String, _ symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
        }
        .buttonStyle(RunButtonStyle(isProminent: false))
        .frame(width: 72)
        .accessibilityIdentifier(identifier)
    }
}

/// What fills the clock's place.
private enum Face {
    case time
    /// A stretch counted in reps has no time to show.
    case reps(Count)
    /// A hold that waits for Start shows the length it will count down from.
    case length(TimeInterval)

    init(_ progress: RunProgress) {
        if let reps = progress.reps {
            self = .reps(reps)
        } else if let length = progress.phase.pendingHold {
            self = .length(length)
        } else {
            self = .time
        }
    }
}

/// What the big button does.
private enum Primary {
    case pause, resume
    /// The two ways out of a wait: Start begins a timed hold, Next leaves a stretch counted in reps.
    case start, next

    init(_ progress: RunProgress) {
        if progress.isPaused {
            self = .resume
        } else if progress.isWaiting {
            self = progress.phase.pendingHold == nil ? .next : .start
        } else {
            self = .pause
        }
    }

    var advances: Bool { self == .start || self == .next }

    var title: String {
        switch self {
        case .pause: "Pause"
        case .resume: "Resume"
        case .start: "Start"
        case .next: "Next"
        }
    }

    var symbol: String {
        switch self {
        case .pause: "pause.fill"
        case .resume, .start: "play.fill"
        case .next: "forward.end.fill"
        }
    }
}

/// One line of text that keeps its height and its place whether or not it has anything to show.
private struct Line<Content: View>: View {
    let font: Font
    var padding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        Text(" ")
            .hidden()
            .padding(.vertical, padding)
            .frame(maxWidth: .infinity)
            .overlay { content }
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// A button that comes and goes inside a space that is always kept for it.
private struct RunChip: View {
    let title: String
    let symbol: String
    let identifier: String
    let action: (() -> Void)?

    var body: some View {
        ZStack {
            if let action {
                Button(action: action) {
                    Label(title, systemImage: symbol)
                }
                .buttonStyle(RunButtonStyle(isProminent: false, minHeight: 52))
                .accessibilityIdentifier(identifier)
                .transition(Motion.chip)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .animation(.easeOut(duration: 0.2), value: action != nil)
    }
}

struct FinishedView: View {
    let name: String
    let worked: TimeInterval
    let undo: (() -> Void)?
    let close: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if verticalSizeClass != .compact {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 88))
                    .accessibilityHidden(true)
            }
            Text("Workout complete")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(name)
                .font(.title2.weight(.medium))
                .opacity(0.85)
                .lineLimit(1)
            Text(ClockText.remaining(worked))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier("timeWorked")
            Text("worked")
                .font(.headline)
                .opacity(0.8)
            Spacer(minLength: 0)
            RunChip(title: "Undo", symbol: "arrow.uturn.backward", identifier: "undoButton", action: undo)
            Button("Done", action: close)
                .buttonStyle(RunButtonStyle(isProminent: true))
                .accessibilityIdentifier("doneButton")
        }
        .padding(20)
    }
}

private struct RunButtonStyle: ButtonStyle {
    let isProminent: Bool
    var minHeight: CGFloat = 72
    var fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        configuration.label
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .background(fill ?? (isProminent ? Color.white : Color.white.opacity(0.22)), in: shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
