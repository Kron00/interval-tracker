import IntervalCore
import SwiftUI

/// What the editor holds while the user types. Any combination of values is allowed here.
/// `definition` is the one place a draft becomes a timer, or fails to.
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

    /// nil while the name is blank or an enabled span is 0:00.
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

    /// Outer nil means invalid. Inner nil means the phase is switched off.
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
                        .accessibilityIdentifier("nameField")
                }
                Section {
                    Toggle("Warm-up", isOn: $draft.hasWarmUp)
                    if draft.hasWarmUp {
                        durationRow("Length", $draft.warmUp, .warmUp)
                    }
                }
                Section("Rounds") {
                    durationRow("Work", $draft.work, .work)
                    Toggle("Rest", isOn: $draft.hasRest)
                    if draft.hasRest {
                        durationRow("Length", $draft.rest, .rest)
                    }
                    Stepper("Rounds: \(draft.rounds)", value: $draft.rounds, in: 1...99)
                    if draft.hasRest {
                        Toggle("Rest after last round", isOn: $draft.restAfterLastRound)
                    }
                }
                Section {
                    Toggle("Cool-down", isOn: $draft.hasCoolDown)
                    if draft.hasCoolDown {
                        durationRow("Length", $draft.coolDown, .coolDown)
                    }
                }
                Section {
                    LabeledContent("Total", value: definition.map { ClockText.remaining($0.totalDuration) } ?? "–")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
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
    }

    private func durationRow(_ label: String, _ seconds: Binding<Int>, _ field: SpanField) -> some View {
        DurationRow(label: label, seconds: seconds, isExpanded: expanded == field) {
            withAnimation { expanded = expanded == field ? nil : field }
        }
    }
}

/// A m:ss value that opens two wheels inline when tapped.
private struct DurationRow: View {
    let label: String
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
                Text(label).foregroundStyle(Color.primary)
            }
        }
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
