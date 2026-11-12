import IntervalCore
import SwiftUI

private enum LibrarySheet: Identifiable {
    case detail(TimerDefinition)
    case editor(TimerDraft)
    case settings

    var id: String {
        switch self {
        case .detail(let timer): "detail-\(timer.id)"
        case .editor(let draft): "editor-\(draft.id)"
        case .settings: "settings"
        }
    }
}

struct LibraryScreen: View {
    let store: LibraryStore
    let run: RunModel
    let log: AudioLog

    @State private var sheet: LibrarySheet?

    var body: some View {
        NavigationStack {
            List {
                Section("Presets") {
                    ForEach(TimerDefinition.builtIn) { timer in
                        row(timer)
                            .swipeActions { duplicateButton(timer).tint(.accentColor) }
                            .contextMenu { duplicateButton(timer) }
                    }
                }
                Section("My timers") {
                    if store.library.timers.isEmpty {
                        Text("Tap + to build your own, or duplicate a preset.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.library.timers) { timer in
                        row(timer)
                            .swipeActions { deleteButton(timer) }
                            .contextMenu {
                                Button {
                                    sheet = .editor(TimerDraft(timer))
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                duplicateButton(timer)
                                deleteButton(timer)
                            }
                    }
                }
            }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .editor(TimerDraft())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New timer")
                    .accessibilityIdentifier("addTimerButton")
                }
            }
            .sheet(item: $sheet, content: content)
            .alert("Timer library", isPresented: problemIsShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.problem ?? "")
            }
        }
    }

    @ViewBuilder
    private func content(for sheet: LibrarySheet) -> some View {
        switch sheet {
        case .detail(let timer):
            TimerDetailSheet(
                timer: timer,
                isPreset: isPreset(timer),
                start: { start(timer) },
                edit: { self.sheet = .editor(TimerDraft(timer)) },
                duplicate: {
                    duplicate(timer)
                    self.sheet = nil
                },
                close: { self.sheet = nil })
                .task { run.prepare(timer, cues: store.library.cues) }
        case .editor(let draft):
            EditorScreen(
                draft: draft,
                title: store.library.timers.contains { $0.id == draft.id } ? "Edit timer" : "New timer",
                save: { timer in
                    store.update { $0.save(timer) }
                    self.sheet = nil
                },
                cancel: { self.sheet = nil })
        case .settings:
            SettingsScreen(
                store: store,
                log: log,
                startAudioCheck: { start(.audioCheck) },
                close: { self.sheet = nil })
                .task { run.prepare(.audioCheck, cues: store.library.cues) }
        }
    }

    private func row(_ timer: TimerDefinition) -> some View {
        Button {
            sheet = .detail(timer)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timer.name)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(timer.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Text(ClockText.remaining(timer.totalDuration))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("timerRow-\(timer.name)")
    }

    private func duplicateButton(_ timer: TimerDefinition) -> some View {
        Button {
            duplicate(timer)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
    }

    private func deleteButton(_ timer: TimerDefinition) -> some View {
        Button(role: .destructive) {
            store.update { $0.delete(timer.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var problemIsShown: Binding<Bool> {
        Binding(get: { store.problem != nil }, set: { if !$0 { store.problem = nil } })
    }

    private func isPreset(_ timer: TimerDefinition) -> Bool {
        TimerDefinition.builtIn.contains { $0.id == timer.id }
    }

    private func start(_ timer: TimerDefinition) {
        sheet = nil
        run.start(timer, cues: store.library.cues)
    }

    private func duplicate(_ timer: TimerDefinition) {
        let copy = TimerDefinition(
            name: "\(timer.name) copy", warmUp: timer.warmUp, work: timer.work, rest: timer.rest,
            rounds: timer.rounds, coolDown: timer.coolDown, restAfterLastRound: timer.restAfterLastRound)
        store.update { $0.save(copy) }
    }
}

struct TimerDetailSheet: View {
    let timer: TimerDefinition
    let isPreset: Bool
    let start: () -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let warmUp = timer.warmUp {
                    LabeledContent("Warm-up", value: warmUp.clockText)
                }
                LabeledContent("Work", value: timer.work.clockText)
                if let rest = timer.rest {
                    LabeledContent("Rest", value: rest.clockText)
                }
                LabeledContent("Rounds", value: "\(timer.rounds.value)")
                if let coolDown = timer.coolDown {
                    LabeledContent("Cool-down", value: coolDown.clockText)
                }
                LabeledContent("Total", value: ClockText.remaining(timer.totalDuration))
                    .fontWeight(.semibold)
            }
            .monospacedDigit()
            .navigationTitle(timer.name)
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
                Button(action: start) {
                    Label("Start", systemImage: "play.fill")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("startButton")
                .padding()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension Span {
    var clockText: String { ClockText.remaining(TimeInterval(seconds)) }
}

extension TimerDefinition {
    var summary: String {
        let intervals = "\(rounds.value) × \(work.clockText)" + (rest.map { " / \($0.clockText)" } ?? "")
        return [
            warmUp.map { "\($0.clockText) warm-up" },
            intervals,
            coolDown.map { "\($0.clockText) cool-down" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
