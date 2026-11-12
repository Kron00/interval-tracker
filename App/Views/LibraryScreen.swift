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
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
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
                start: { start(timer, cues: store.library.cues) },
                edit: { self.sheet = .editor(TimerDraft(timer)) },
                duplicate: { self.sheet = .editor(TimerDraft(copyOf: timer)) },
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
                startAudioCheck: { start(.audioCheck, cues: SettingsScreen.audioCheckCues) },
                close: { self.sheet = nil })
                .task { run.prepare(.audioCheck, cues: SettingsScreen.audioCheckCues) }
        }
    }

    private func row(_ timer: TimerDefinition) -> some View {
        Button {
            sheet = .detail(timer)
        } label: {
            TimerCard(timer: timer)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("timerRow-\(timer.name)")
    }

    private func duplicateButton(_ timer: TimerDefinition) -> some View {
        Button {
            sheet = .editor(TimerDraft(copyOf: timer))
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

    private func start(_ timer: TimerDefinition, cues: CuePreferences) {
        sheet = nil
        run.start(timer, cues: cues)
    }
}

struct TimerCard: View {
    let timer: TimerDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(timer.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text(ClockText.remaining(timer.totalDuration))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            TimelineStrip(spans: timer.outline)
                .frame(height: 10)
            Text(timer.summary)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .padding(16)
        .background(Theme.card, in: Theme.cardShape)
        .contentShape(Theme.cardShape)
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
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 2) {
                        Text(ClockText.remaining(timer.totalDuration))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("total")
                            .font(.headline)
                            .foregroundStyle(Color.secondary)
                    }
                    TimelineStrip(spans: timer.outline)
                        .frame(height: 14)
                    VStack(spacing: 0) {
                        if let warmUp = timer.warmUp {
                            phaseRow("Warm-up", warmUp.clockText, Theme.warmUp)
                            Divider()
                        }
                        phaseRow("Work", "\(timer.rounds.value) × \(timer.work.clockText)", Theme.work)
                        if let rest = timer.rest {
                            Divider()
                            phaseRow("Rest", "\(restCount) × \(rest.clockText)", Theme.rest)
                        }
                        if let coolDown = timer.coolDown {
                            Divider()
                            phaseRow("Cool-down", coolDown.clockText, Theme.coolDown)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.card, in: Theme.cardShape)
                }
                .padding(20)
            }
            .background(Theme.background)
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
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("startButton")
                .padding()
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }

    private var restCount: Int {
        timer.restAfterLastRound ? timer.rounds.value : timer.rounds.value - 1
    }

    private func phaseRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
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
