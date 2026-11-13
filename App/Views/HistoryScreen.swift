import IntervalCore
import SwiftUI

struct HistoryScreen: View {
    let history: HistoryStore
    let library: LibraryStore
    let run: RunModel

    @State private var selected: WorkoutRecord?
    @State private var confirmingClear = false

    var body: some View {
        let days = history.history.days(in: .current)
        Group {
            if days.isEmpty {
                emptyState
            } else {
                list(days)
            }
        }
        .background(Theme.background)
        .navigationTitle("History")
        .toolbar {
            if !days.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear all") { confirmingClear = true }
                        .accessibilityIdentifier("clearHistoryButton")
                }
            }
        }
        .navigationDestination(item: $selected) { record in
            HistoryEntryScreen(record: record, workout: workout(for: record), run: run, cues: library.library.cues)
        }
        .alert("Clear all history?", isPresented: $confirmingClear) {
            Button("Clear all", role: .destructive) { history.update { $0.clear() } }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Every entry is removed. Your workouts stay in the library.")
        }
        .alert("History", isPresented: problemIsShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(history.problem ?? "")
        }
    }

    private func list(_ days: [History.Day]) -> some View {
        List {
            WeekSummaryCard(summary: history.history.summary(ofWeekContaining: .now, in: .current))
                .cardRow()
            ForEach(days) { day in
                Section(Self.title(of: day.date)) {
                    ForEach(day.records) { record in
                        Button {
                            selected = record
                        } label: {
                            HistoryCard(record: record)
                        }
                        .buttonStyle(.plain)
                        .cardRow()
                        .accessibilityIdentifier("historyRow-\(record.name)")
                        .swipeActions {
                            Button(role: .destructive) {
                                history.update { $0.delete(record.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)
            Text("No workouts yet")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .accessibilityIdentifier("historyEmpty")
            Text("A workout you finish appears here. So does a workout you end early after a minute or more of work.")
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var problemIsShown: Binding<Bool> {
        Binding(get: { history.problem != nil }, set: { if !$0 { history.problem = nil } })
    }

    /// The workout as the library has it now. nil once it has been deleted.
    private func workout(for record: WorkoutRecord) -> Workout? {
        (Workout.builtIn + library.library.workouts).first { $0.id == record.workoutID }
    }

    private static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let date = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return day.formatted(calendar.isDate(day, equalTo: .now, toGranularity: .year) ? date : date.year())
    }
}

private struct WeekSummaryCard: View {
    let summary: History.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week")
                .font(.headline)
                .foregroundStyle(Color.secondary)
            HStack(alignment: .firstTextBaseline) {
                figure("\(summary.workouts)", unit)
                Spacer()
                figure(ClockText.remaining(summary.worked), "worked")
            }
        }
        .padding(16)
        .background(Theme.card, in: Theme.cardShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(summary.workouts) \(unit), \(ClockText.remaining(summary.worked)) worked")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("historySummary")
    }

    private var unit: String { summary.workouts == 1 ? "workout" : "workouts" }

    private func figure(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.headline)
                .foregroundStyle(Color.secondary)
        }
        .lineLimit(1)
    }
}

private struct HistoryCard: View {
    let record: WorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text(ClockText.remaining(record.worked))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            WorkedBar(record: record)
                .frame(height: 10)
            HStack(spacing: 6) {
                Image(systemName: record.outcome.symbol)
                    .foregroundStyle(record.outcome.tint)
                    .accessibilityHidden(true)
                Text("\(record.outcome.label) · \(record.startedAt.formatted(date: .omitted, time: .shortened))")
                Spacer()
                // Only a run that fell short of its plan has something to compare. Reps and
                // restarts take a run past it.
                if record.worked < record.planned {
                    Text("of \(ClockText.remaining(record.planned))")
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
        }
        .padding(16)
        .background(Theme.card, in: Theme.cardShape)
        .contentShape(Theme.cardShape)
    }
}

/// How much of the planned time was worked. Reps and restarts can take a run past its plan, and
/// the bar is then full.
private struct WorkedBar: View {
    let record: WorkoutRecord

    var body: some View {
        Canvas { context, size in
            let radius = min(size.height / 2, 4)
            let whole = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: whole, cornerRadius: radius), with: .color(.white.opacity(0.14)))
            guard record.planned > 0, record.worked > 0 else { return }
            var done = whole
            done.size.width = max(size.height, size.width * min(record.worked / record.planned, 1))
            context.fill(Path(roundedRect: done, cornerRadius: radius), with: .color(record.kind.tint))
        }
        .accessibilityHidden(true)
    }
}

struct HistoryEntryScreen: View {
    let record: WorkoutRecord
    /// nil when the library no longer has the workout.
    let workout: Workout?
    let run: RunModel
    let cues: CuePreferences

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text(ClockText.remaining(record.worked))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityIdentifier("historyWorked")
                    Text("worked")
                        .font(.headline)
                        .foregroundStyle(Color.secondary)
                }
                WorkedBar(record: record)
                    .frame(height: 14)
                VStack(spacing: 0) {
                    row("Result", record.outcome.label, mark: record.outcome.tint)
                    Divider()
                    row("Date", record.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    Divider()
                    row("Started", record.startedAt.formatted(date: .omitted, time: .shortened))
                    Divider()
                    row("Kind", record.kind.label)
                    Divider()
                    row("Planned", ClockText.remaining(record.planned))
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: Theme.cardShape)
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Group {
                if let workout {
                    Button {
                        run.start(workout, cues: cues)
                    } label: {
                        Label("Start again", systemImage: "play.fill")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("startAgainButton")
                    .task { run.prepare(workout, cues: cues) }
                } else {
                    Text("This workout is no longer in your library.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .accessibilityIdentifier("workoutGone")
                }
            }
            .padding()
            .background(Theme.background)
        }
    }

    private func row(_ label: String, _ value: String, mark: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer()
            if let mark {
                Circle()
                    .fill(mark)
                    .frame(width: 12, height: 12)
            }
            Text(value)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .font(.title3)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 16)
    }
}

private extension View {
    /// The spacing of a card in the library list, with nothing of the list's own drawn around it.
    func cardRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private extension WorkoutRecord.Outcome {
    var label: String {
        switch self {
        case .completed: "Completed"
        case .endedEarly: "Ended early"
        }
    }

    var symbol: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .endedEarly: "stop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .completed: Tone.stretch.tint
        case .endedEarly: Tone.prepare.tint
        }
    }
}

private extension WorkoutRecord.Kind {
    var label: String {
        switch self {
        case .intervals: "Interval timer"
        case .routine: "Stretch routine"
        }
    }

    var tint: Color {
        switch self {
        case .intervals: Tone.effort.tint
        case .routine: Tone.stretch.tint
        }
    }
}
