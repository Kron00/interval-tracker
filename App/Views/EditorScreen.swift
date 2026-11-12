import IntervalCore
import SwiftUI

struct TimerDraft: Equatable {
    let id: UUID
    var name = ""
    var hasWarmUp = true
    var warmUp = 300
    var work = 60
    var hasRest = true
    var rest = 60
    var rounds = 5
    var restAfterLastRound = true
    var hasCoolDown = true
    var coolDown = 300

    init() { id = UUID() }

    init(_ timer: TimerDefinition) {
        id = timer.id
        name = timer.name
        hasWarmUp = timer.warmUp != nil
        warmUp = timer.warmUp?.seconds ?? warmUp
        work = timer.work.seconds
        hasRest = timer.rest != nil
        rest = timer.rest?.seconds ?? rest
        rounds = timer.rounds.value
        restAfterLastRound = timer.restAfterLastRound
        hasCoolDown = timer.coolDown != nil
        coolDown = timer.coolDown?.seconds ?? coolDown
    }

    /// The same values under a new identity, so editing a copy never touches the original.
    init(copyOf timer: TimerDefinition) {
        self.init(TimerDefinition(
            name: "\(timer.name) copy", warmUp: timer.warmUp, work: timer.work, rest: timer.rest,
            rounds: timer.rounds, coolDown: timer.coolDown, restAfterLastRound: timer.restAfterLastRound))
    }

    var problem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Name the timer to save it." }
        return definition == nil ? "Each phase that is switched on needs a length above 0:00." : nil
    }

    var definition: TimerDefinition? {
        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let work = Span(seconds: work),
              let rounds = RoundCount(rounds),
              let warmUp = Self.span(warmUp, enabled: hasWarmUp),
              let rest = Self.span(rest, enabled: hasRest),
              let coolDown = Self.span(coolDown, enabled: hasCoolDown)
        else { return nil }
        return TimerDefinition(
            id: id, name: name, warmUp: warmUp, work: work, rest: rest,
            rounds: rounds, coolDown: coolDown, restAfterLastRound: restAfterLastRound)
    }

    private static func span(_ seconds: Int, enabled: Bool) -> Span?? {
        enabled ? Span(seconds: seconds).map(Optional.some) : .some(nil)
    }
}

struct EditorScreen: View {
    let title: String
    let save: (TimerDefinition) -> Void
    let cancel: () -> Void

    private let original: TimerDraft
    @State private var draft: TimerDraft
    @State private var expanded: SpanField?
    @FocusState private var nameIsFocused: Bool

    private enum SpanField { case warmUp, work, rest, coolDown }

    init(draft: TimerDraft, title: String, save: @escaping (TimerDefinition) -> Void, cancel: @escaping () -> Void) {
        self.title = title
        self.save = save
        self.cancel = cancel
        original = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        let definition = draft.definition
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .focused($nameIsFocused)
                        .accessibilityIdentifier("nameField")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Total")
                                .foregroundStyle(Color.secondary)
                            Spacer()
                            Text(definition.map { ClockText.remaining($0.totalDuration) } ?? "–")
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .accessibilityIdentifier("editorTotal")
                        }
                        if let definition {
                            TimelineStrip(spans: definition.outline)
                                .frame(height: 10)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if let problem = draft.problem {
                        Text(problem).accessibilityIdentifier("editorProblem")
                    }
                }
                Section {
                    Toggle(isOn: $draft.hasWarmUp) { phaseLabel("Warm-up", Theme.warmUp) }
                        .tint(Theme.warmUp)
                    if draft.hasWarmUp {
                        durationRow("Length", $draft.warmUp, .warmUp)
                    }
                }
                Section("Rounds") {
                    durationRow("Work", $draft.work, .work, color: Theme.work)
                    Toggle(isOn: $draft.hasRest) { phaseLabel("Rest", Theme.rest) }
                        .tint(Theme.rest)
                    if draft.hasRest {
                        durationRow("Length", $draft.rest, .rest)
                    }
                    Stepper("Rounds: \(draft.rounds)", value: $draft.rounds, in: 1...99)
                    if draft.hasRest {
                        Toggle("Rest after last round", isOn: $draft.restAfterLastRound)
                            .tint(Theme.rest)
                    }
                }
                Section {
                    Toggle(isOn: $draft.hasCoolDown) { phaseLabel("Cool-down", Theme.coolDown) }
                        .tint(Theme.coolDown)
                    if draft.hasCoolDown {
                        durationRow("Length", $draft.coolDown, .coolDown)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let definition { save(definition) }
                    }
                    .disabled(definition == nil)
                    .accessibilityIdentifier("saveButton")
                }
            }
        }
        .interactiveDismissDisabled(draft != original)
        .presentationBackground(Theme.background)
    }

    private func durationRow(_ label: String, _ seconds: Binding<Int>, _ field: SpanField, color: Color? = nil) -> some View {
        DurationRow(label: label, color: color, identifier: "duration-\(field)", seconds: seconds, isExpanded: expanded == field) {
            nameIsFocused = false
            withAnimation { expanded = expanded == field ? nil : field }
        }
    }

    private func phaseLabel(_ title: String, _ color: Color) -> some View {
        PhaseLabel(title: title, color: color)
    }
}

private struct PhaseLabel: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
        }
    }
}

private struct DurationRow: View {
    let label: String
    let color: Color?
    let identifier: String
    @Binding var seconds: Int
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            LabeledContent {
                Text(ClockText.remaining(TimeInterval(seconds)))
                    .monospacedDigit()
                    .foregroundStyle(isExpanded ? Color.accentColor : Color.secondary)
            } label: {
                if let color {
                    PhaseLabel(title: label, color: color).foregroundStyle(Color.primary)
                } else {
                    Text(label).foregroundStyle(Color.primary)
                }
            }
        }
        .accessibilityIdentifier(identifier)
        if isExpanded {
            HStack(spacing: 0) {
                wheel("Minutes", 0..<100, unit: "min", get: { seconds / 60 }, set: { seconds = $0 * 60 + seconds % 60 })
                wheel("Seconds", 0..<60, unit: "s", get: { seconds % 60 }, set: { seconds = seconds / 60 * 60 + $0 })
            }
            .frame(height: 140)
        }
    }

    private func wheel(
        _ title: String, _ range: Range<Int>, unit: String,
        get: @escaping () -> Int, set: @escaping (Int) -> Void
    ) -> some View {
        Picker(title, selection: Binding(get: get, set: set)) {
            ForEach(range, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
