import IntervalCore
import SwiftUI

private enum LibrarySheet: Identifiable {
    case detail(Workout)
    case editor(WorkoutDraft)
    case describe
    case settings

    var id: String {
        switch self {
        case .detail(let workout): "detail-\(workout.id)"
        case .editor(let draft): "editor-\(draft.id)"
        case .describe: "describe"
        case .settings: "settings"
        }
    }
}

struct LibraryScreen: View {
    let store: LibraryStore
    let history: HistoryStore
    let run: RunModel
    let log: AudioLog

    @State private var sheet: LibrarySheet?
    @State private var pendingDelete: Workout?

    var body: some View {
        NavigationStack {
            List {
                Section("Presets") {
                    ForEach(Workout.builtIn) { workout in
                        row(workout)
                            .swipeActions { duplicateButton(workout).tint(.accentColor) }
                            .contextMenu { duplicateButton(workout) }
                    }
                }
                Section("My workouts") {
                    if store.library.workouts.isEmpty {
                        Text("Tap + to build your own, or duplicate a preset.")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(store.library.workouts) { workout in
                        row(workout)
                            .swipeActions { deleteButton(workout) }
                            .contextMenu {
                                Button {
                                    sheet = .editor(WorkoutDraft(workout))
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                duplicateButton(workout)
                                Button(role: .destructive) {
                                    pendingDelete = workout
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Intervals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryScreen(history: history, library: store, run: run)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                    .accessibilityIdentifier("historyButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sheet = .editor(WorkoutDraft(new: .intervals(IntervalsDraft())))
                        } label: {
                            Label("Interval timer", systemImage: "timer")
                        }
                        .accessibilityIdentifier("newIntervalTimer")
                        Button {
                            sheet = .editor(WorkoutDraft(new: .routine(RoutineDraft())))
                        } label: {
                            Label("Stretch routine", systemImage: "figure.flexibility")
                        }
                        .accessibilityIdentifier("newStretchRoutine")
                        Button {
                            sheet = .describe
                        } label: {
                            Label("Describe a workout", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("describeWorkout")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New workout")
                    .accessibilityIdentifier("addTimerButton")
                }
            }
            .sheet(item: $sheet, content: content)
            .alert("Delete \"\(pendingDelete?.name ?? "")\"?", isPresented: deleteIsPending, presenting: pendingDelete) { workout in
                Button("Delete", role: .destructive) { store.update { $0.delete(workout.id) } }
                Button("Keep", role: .cancel) {}
            }
            .alert("Library", isPresented: problemIsShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.problem ?? "")
            }
        }
    }

    @ViewBuilder
    private func content(for sheet: LibrarySheet) -> some View {
        switch sheet {
        case .detail(let workout):
            WorkoutDetailSheet(
                workout: workout,
                isPreset: isPreset(workout),
                start: { start(workout, cues: store.library.cues) },
                edit: { self.sheet = .editor(WorkoutDraft(workout)) },
                duplicate: { self.sheet = .editor(WorkoutDraft(copyOf: workout)) },
                close: { self.sheet = nil })
                .task { run.prepare(workout, cues: store.library.cues) }
        case .editor(let draft):
            EditorScreen(
                draft: draft,
                title: "\(store.library.workouts.contains { $0.id == draft.id } ? "Edit" : "New") \(draft.plan.noun)",
                save: { workout in
                    store.update { $0.save(workout) }
                    self.sheet = nil
                },
                cancel: { self.sheet = nil })
        case .describe:
            DescribeSheet(
                // The new card is the last one in the list and can be off the screen, so the
                // workout opens as a tap on its card would open it.
                save: { workout in
                    store.update { $0.save(workout) }
                    self.sheet = .detail(workout)
                },
                saveEdited: { workout in
                    store.update { $0.save(workout) }
                    self.sheet = nil
                },
                close: { self.sheet = nil })
        case .settings:
            SettingsScreen(
                store: store,
                log: log,
                liveActivityProblem: run.liveActivityProblem,
                startAudioCheck: { start(.audioCheck, cues: SettingsScreen.audioCheckCues) },
                close: { self.sheet = nil })
                .task { run.prepare(.audioCheck, cues: SettingsScreen.audioCheckCues) }
        }
    }

    private func row(_ workout: Workout) -> some View {
        Button {
            sheet = .detail(workout)
        } label: {
            WorkoutCard(workout: workout)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("timerRow-\(workout.name)")
    }

    private func duplicateButton(_ workout: Workout) -> some View {
        Button {
            sheet = .editor(WorkoutDraft(copyOf: workout))
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
    }

    private func deleteButton(_ workout: Workout) -> some View {
        Button(role: .destructive) {
            store.update { $0.delete(workout.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var deleteIsPending: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var problemIsShown: Binding<Bool> {
        Binding(get: { store.problem != nil }, set: { if !$0 { store.problem = nil } })
    }

    private func isPreset(_ workout: Workout) -> Bool {
        Workout.builtIn.contains { $0.id == workout.id }
    }

    private func start(_ workout: Workout, cues: CuePreferences) {
        sheet = nil
        run.start(workout, cues: cues)
    }
}

struct WorkoutCard: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text(workout.totalText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            TimelineStrip(spans: workout.outline)
                .frame(height: 10)
            Text(workout.plan.summary)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .padding(16)
        .background(Theme.card, in: Theme.cardShape)
        .contentShape(Theme.cardShape)
    }
}

struct WorkoutDetailSheet: View {
    let workout: Workout
    let isPreset: Bool
    let start: () -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                WorkoutBreakdown(workout: workout)
                    .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                }
                ToolbarItem(placement: .primaryAction) {
                    if isPreset {
                        Button("Duplicate", action: duplicate)
                    } else {
                        Button("Edit", action: edit)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if case .routine = workout.plan {
                        HeadphoneControlsCard()
                    }
                    Button(action: start) {
                        Label("Start", systemImage: "play.fill")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("startButton")
                }
                .padding()
                .background(Theme.background)
                .background(alignment: .top) {
                    LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                        .offset(y: -28)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }
}

/// A workout laid out to read before it is run: the total, the strip, and every step.
struct WorkoutBreakdown: View {
    let workout: Workout

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 2) {
                Text(workout.totalText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("detailTotal")
                Text("total")
                    .font(.headline)
                    .foregroundStyle(Color.secondary)
            }
            TimelineStrip(spans: workout.outline)
                .frame(height: 14)
            Group {
                switch workout.plan {
                case .intervals(let intervals): IntervalRows(intervals: intervals)
                case .routine(let routine): StretchRows(routine: routine)
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: Theme.cardShape)
        }
    }
}

private struct IntervalRows: View {
    let intervals: Intervals

    var body: some View {
        VStack(spacing: 0) {
            if let warmUp = intervals.warmUp {
                row("Warm-up", warmUp.clockText, .prepare)
                Divider()
            }
            row("Work", "\(intervals.rounds.value) × \(intervals.work.clockText)", .effort)
            if let rest = intervals.rest {
                Divider()
                row("Rest", "\(restCount) × \(rest.clockText)", .recover)
            }
            if let coolDown = intervals.coolDown {
                Divider()
                row("Cool-down", coolDown.clockText, .cool)
            }
        }
    }

    private var restCount: Int {
        intervals.restAfterLastRound ? intervals.rounds.value : intervals.rounds.value - 1
    }

    private func row(_ label: String, _ value: String, _ tone: Tone) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tone.tint)
                .frame(width: 12, height: 12)
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .font(.title3)
        .padding(.vertical, 16)
    }
}

private struct StretchRows: View {
    let routine: Routine

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(routine.stretches.enumerated()), id: \.element.id) { index, stretch in
                if index > 0 { Divider() }
                HStack(spacing: 14) {
                    Text("\(index + 1)")
                        .font(.system(.headline, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Tone.stretch.tint)
                        .frame(minWidth: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stretch.name)
                            .font(.title3)
                            .lineLimit(2)
                        Text(stretch.amount.text(stretch.sides))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer(minLength: 8)
                    if let howTo = stretch.howTo {
                        Button {
                            openURL(howTo)
                        } label: {
                            Text("How to")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Tone.stretch.tint)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Tone.stretch.tint.opacity(0.16), in: Capsule())
                        }
                        .accessibilityLabel("How to do \(stretch.name)")
                        .accessibilityIdentifier("howTo-\(stretch.name)")
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}

private struct HeadphoneControlsCard: View {
    @AppStorage(SettingsKey.headphoneControls) private var isOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                Label("Headphone controls", systemImage: "headphones")
                    .font(.headline)
            }
            .accessibilityIdentifier("headphoneControlsToggle")
            Text("Other audio stops while this is on. When the routine waits, press once for Start or Next.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension Span {
    var clockText: String { ClockText.remaining(TimeInterval(seconds)) }
}

extension Count {
    var repsUnit: String { value == 1 ? "rep" : "reps" }
    var repsText: String { "\(value) \(repsUnit)" }
}

extension PhaseSpan {
    var lengthText: String { phase.reps?.repsText ?? ClockText.remaining(duration) }
}

extension RunProgress {
    /// What a waiting run waits on: a rep count, or the length of the hold that Start begins.
    var awaited: String? { reps?.repsText ?? phase.pendingHold.map(ClockText.remaining) }

    /// What follows this phase, as "Work 4:00". "Finish" in the last phase.
    var upNextText: String {
        upNext.map { "\($0.phase.title(following: phase)) \($0.lengthText)" } ?? "Finish"
    }
}

extension Workout {
    /// Reps are not timed, so a routine that has them shows its timed length and says reps come on top.
    var totalText: String {
        ClockText.remaining(totalDuration) + (outline.contains { $0.phase.reps != nil } ? " + reps" : "")
    }
}

extension Plan {
    var summary: String {
        switch self {
        case .intervals(let intervals):
            let rounds = "\(intervals.rounds.value) × \(intervals.work.clockText)"
                + (intervals.rest.map { " / \($0.clockText)" } ?? "")
            return [
                intervals.warmUp.map { "\($0.clockText) warm-up" },
                rounds,
                intervals.coolDown.map { "\($0.clockText) cool-down" },
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        case .routine(let routine):
            let count = routine.stretches.count
            let eachSide = routine.stretches.filter { $0.sides == .each }.count
            return [
                count == 1 ? "1 stretch" : "\(count) stretches",
                eachSide > 0 ? "\(eachSide) each side" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }
    }
}
