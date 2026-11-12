import IntervalCore
import SwiftUI

struct RunScreen: View {
    let run: RunModel
    let session: Session

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let snapshot = session.snapshot(at: context.date)
            let tone = RunTone(snapshot)
            ZStack {
                tone.color
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: tone)
                switch snapshot {
                case .active(let progress):
                    ActiveRunView(
                        name: session.definition.name,
                        progress: progress,
                        pause: run.pause,
                        resume: run.resume,
                        skip: { run.skip(progress.segment) },
                        end: run.end)
                case .finished(let total):
                    FinishedView(name: session.definition.name, total: total, close: run.end)
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
        case .warmUp: Color(red: 0.80, green: 0.38, blue: 0.04)
        case .work: Color(red: 0.76, green: 0.11, blue: 0.13)
        case .rest: Color(red: 0.09, green: 0.33, blue: 0.75)
        case .coolDown: Color(red: 0.02, green: 0.46, blue: 0.50)
        case .paused: Color(red: 0.26, green: 0.28, blue: 0.31)
        case .finished: Color(red: 0.02, green: 0.35, blue: 0.25)
        }
    }
}

struct ActiveRunView: View {
    let name: String
    let progress: RunProgress
    let pause: () -> Void
    let resume: () -> Void
    let skip: () -> Void
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
            Text(progress.phase.title.uppercased())
                .font(.system(size: isLandscape ? 44 : 64, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("phaseTitle")
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
            Text("Up next: \(progress.upNext?.title ?? "Finish")")
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
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * (1 - progress.totalRemaining / progress.totalDuration))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }

    private var controls: some View {
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
    let total: TimeInterval
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
            Text(ClockText.remaining(total))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
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

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        configuration.label
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .background(isProminent ? Color.white : Color.white.opacity(0.22), in: shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
