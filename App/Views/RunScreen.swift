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
        outline = session.definition.outline
    }

    var body: some View {
        TimelineView(.periodic(from: session.zeroDate ?? .now, by: 1)) { context in
            let snapshot = session.snapshot(at: context.date)
            let tone = RunTone(snapshot)
            let undoSkip: (() -> Void)? = run.beforeSkip == nil ? nil : { run.undoSkip() }
            ZStack {
                LinearGradient(colors: [tone.color, tone.color.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: tone)
                switch snapshot {
                case .active(let progress):
                    ActiveRunView(
                        name: session.definition.name,
                        progress: progress,
                        outline: outline,
                        cuesAreSilent: log.cuesAreSilent,
                        pause: run.pause,
                        resume: run.resume,
                        skip: { run.skip(progress.segment) },
                        undoSkip: undoSkip,
                        end: run.end)
                case .finished(let worked):
                    FinishedView(name: session.definition.name, worked: worked, close: run.end)
                }
            }
        }
        .foregroundStyle(Color.white)
        .preferredColorScheme(.dark)
    }
}

private enum RunTone: Hashable {
    case warmUp, work, rest, coolDown, paused, finished

    init(_ snapshot: Snapshot) {
        switch snapshot {
        case .finished:
            self = .finished
        case .active(let progress) where progress.isPaused:
            self = .paused
        case .active(let progress):
            switch progress.phase {
            case .warmUp: self = .warmUp
            case .work: self = .work
            case .rest: self = .rest
            case .coolDown: self = .coolDown
            }
        }
    }

    var color: Color {
        switch self {
        case .warmUp: Color(red: 0.68, green: 0.47, blue: 0.00)
        case .work: Color(red: 0.76, green: 0.11, blue: 0.13)
        case .rest: Color(red: 0.09, green: 0.33, blue: 0.75)
        case .coolDown: Color(red: 0.42, green: 0.26, blue: 0.64)
        case .paused: Color(red: 0.26, green: 0.28, blue: 0.31)
        case .finished: Color(red: 0.02, green: 0.35, blue: 0.25)
        }
    }
}

struct ActiveRunView: View {
    let name: String
    let progress: RunProgress
    let outline: [PhaseSpan]
    let cuesAreSilent: Bool
    let pause: () -> Void
    let resume: () -> Void
    let skip: () -> Void
    let undoSkip: (() -> Void)?
    let end: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var confirmingEnd = false

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isLandscape {
                HStack(spacing: 24) {
                    clock
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 10) {
                        header
                        details
                        Spacer(minLength: 0)
                        overall
                        controls
                    }
                    .frame(maxWidth: 340)
                }
            } else {
                VStack(spacing: 12) {
                    header
                    Spacer(minLength: 0)
                    clock
                    details
                    Spacer(minLength: 0)
                    overall
                    controls
                }
            }
        }
        .padding(20)
        .confirmationDialog("End this workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End workout", role: .destructive, action: end)
            Button("Keep going", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.headline)
                .opacity(0.8)
                .lineLimit(1)
            if cuesAreSilent {
                Label("No sound. Audio could not start. Retrying.", systemImage: "speaker.slash.fill")
                    .font(.headline)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("audioWarning")
            }
            Text(progress.isPaused ? "PAUSED" : progress.phase.title.uppercased())
                .font(.system(size: isLandscape ? 44 : 64, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("phaseTitle")
            if progress.isPaused {
                Text("in \(progress.phase.title)")
                    .font(.title2.weight(.semibold))
                    .opacity(0.85)
            }
        }
    }

    private var clock: some View {
        Text(ClockText.remaining(progress.phaseDuration))
            .hidden()
            .overlay {
                Text(ClockText.remaining(progress.phaseRemaining))
                    .accessibilityIdentifier("timeRemaining")
            }
            .font(.system(size: 320, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.05)
    }

    private var details: some View {
        VStack(spacing: 6) {
            if let round = progress.phase.round {
                Text("Round \(round.number) of \(round.total)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("roundLabel")
            }
            Text("Up next: \(progress.upNext.map { "\($0.phase.title) \(ClockText.remaining($0.duration))" } ?? "Finish")")
                .font(.title2.weight(.medium))
                .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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
            TimelineStrip(spans: outline, elapsed: progress.totalDuration - progress.totalRemaining)
                .frame(height: 8)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if let undoSkip {
                Button(action: undoSkip) {
                    Label("Undo skip", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(RunButtonStyle(isProminent: false, minHeight: 52))
                .accessibilityIdentifier("undoSkipButton")
            }
            mainControls
        }
    }

    private var mainControls: some View {
        HStack(spacing: 12) {
            Button {
                confirmingEnd = true
            } label: {
                Label("End", systemImage: "xmark").labelStyle(.iconOnly)
            }
            .buttonStyle(RunButtonStyle(isProminent: false))
            .frame(width: 72)
            .accessibilityIdentifier("endButton")

            Button(action: progress.isPaused ? resume : pause) {
                Label(progress.isPaused ? "Resume" : "Pause", systemImage: progress.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(RunButtonStyle(isProminent: true))
            .accessibilityIdentifier("pauseResumeButton")

            Button(action: skip) {
                Label("Skip", systemImage: "forward.end.fill")
            }
            .buttonStyle(RunButtonStyle(isProminent: false))
            .accessibilityIdentifier("skipButton")
        }
    }
}

struct FinishedView: View {
    let name: String
    let worked: TimeInterval
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
            Spacer(minLength: 0)
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

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        configuration.label
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .background(isProminent ? Color.white : Color.white.opacity(0.22), in: shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
