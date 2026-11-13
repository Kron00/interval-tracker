import IntervalCore
import SwiftUI

struct WorkoutDraft: Equatable {
    let id: UUID
    var name = ""
    var plan: PlanDraft

    init(new plan: PlanDraft) {
        id = UUID()
        self.plan = plan
    }

    init(_ workout: Workout) {
        id = workout.id
        name = workout.name
        plan = PlanDraft(workout.plan)
    }

    /// The same values under a new identity, so editing a copy never touches the original.
    init(copyOf workout: Workout) {
        var copy = workout.forked()
        copy.name = "\(workout.name) copy"
        self.init(copy)
    }

    var problem: String? {
        if trimmedName.isEmpty { return "Name the \(plan.noun) to save it." }
        return plan.problem
    }

    var workout: Workout? {
        trimmedName.isEmpty ? nil : workout(named: trimmedName)
    }

    /// The workout as it stands, for showing its total and strip before it has a name.
    var preview: Workout? { workout(named: "") }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func workout(named name: String) -> Workout? {
        plan.plan.map { Workout(id: id, name: name, plan: $0) }
    }
}

enum PlanDraft: Equatable {
    case intervals(IntervalsDraft)
    case routine(RoutineDraft)

    init(_ plan: Plan) {
        switch plan {
        case .intervals(let intervals): self = .intervals(IntervalsDraft(intervals))
        case .routine(let routine): self = .routine(RoutineDraft(routine))
        }
    }

    var plan: Plan? {
        switch self {
        case .intervals(let draft): draft.intervals.map(Plan.intervals)
        case .routine(let draft): draft.routine.map(Plan.routine)
        }
    }

    var problem: String? {
        switch self {
        case .intervals(let draft): draft.problem
        case .routine(let draft): draft.problem
        }
    }

    var noun: String {
        switch self {
        case .intervals: "timer"
        case .routine: "routine"
        }
    }

    // A binding cannot reach into an enum case, so each kind's editor binds through one of these.
    // The fallback is never shown, because an editor exists only for the case its draft is in.
    var intervals: IntervalsDraft {
        get { if case .intervals(let draft) = self { draft } else { IntervalsDraft() } }
        set { self = .intervals(newValue) }
    }

    var routine: RoutineDraft {
        get { if case .routine(let draft) = self { draft } else { RoutineDraft() } }
        set { self = .routine(newValue) }
    }
}

struct IntervalsDraft: Equatable {
    var hasWarmUp = true
    var warmUp = 300
    var work = 60
    var hasRest = true
    var rest = 60
    var rounds = 5
    var restAfterLastRound = true
    var hasCoolDown = true
    var coolDown = 300

    init() {}

    init(_ intervals: Intervals) {
        hasWarmUp = intervals.warmUp != nil
        warmUp = intervals.warmUp?.seconds ?? warmUp
        work = intervals.work.seconds
        hasRest = intervals.rest != nil
        rest = intervals.rest?.seconds ?? rest
        rounds = intervals.rounds.value
        restAfterLastRound = intervals.restAfterLastRound
        hasCoolDown = intervals.coolDown != nil
        coolDown = intervals.coolDown?.seconds ?? coolDown
    }

    var problem: String? {
        intervals == nil ? "Each phase that is switched on needs a length above 0:00." : nil
    }

    var intervals: Intervals? {
        guard let work = Span(seconds: work),
              let rounds = Count(rounds),
              let warmUp = Self.span(warmUp, enabled: hasWarmUp),
              let rest = Self.span(rest, enabled: hasRest),
              let coolDown = Self.span(coolDown, enabled: hasCoolDown)
        else { return nil }
        return Intervals(
            warmUp: warmUp, work: work, rest: rest, rounds: rounds, coolDown: coolDown,
            restAfterLastRound: restAfterLastRound)
    }

    private static func span(_ seconds: Int, enabled: Bool) -> Span?? {
        enabled ? Span(seconds: seconds).map(Optional.some) : .some(nil)
    }
}

struct EditorScreen: View {
    let title: String
    let save: (Workout) -> Void
    let cancel: () -> Void

    private let original: WorkoutDraft
    @State private var draft: WorkoutDraft
    @State private var openStretch: StretchDraft.ID?
    @FocusState private var nameIsFocused: Bool

    init(draft: WorkoutDraft, title: String, save: @escaping (Workout) -> Void, cancel: @escaping () -> Void) {
        self.title = title
        self.save = save
        self.cancel = cancel
        original = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        let workout = draft.workout
        let preview = draft.preview
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
                            Text(preview?.totalText ?? "–")
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .accessibilityIdentifier("editorTotal")
                        }
                        if let preview {
                            TimelineStrip(spans: preview.outline)
                                .frame(height: 10)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if let problem = draft.problem {
                        Text(problem).accessibilityIdentifier("editorProblem")
                    }
                }
                switch draft.plan {
                case .intervals:
                    IntervalSections(draft: $draft.plan.intervals, willShowWheel: { nameIsFocused = false })
                case .routine:
                    RoutineSections(draft: $draft.plan.routine, open: { openStretch = $0 })
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
                        if let workout { save(workout) }
                    }
                    .disabled(workout == nil)
                    .accessibilityIdentifier("saveButton")
                }
            }
            .navigationDestination(item: $openStretch) { id in
                StretchEditor(
                    stretch: $draft.plan.routine[stretch: id],
                    number: draft.plan.routine.number(of: id))
            }
        }
        .interactiveDismissDisabled(draft != original)
        .presentationBackground(Theme.background)
    }
}

struct IntervalSections: View {
    @Binding var draft: IntervalsDraft
    let willShowWheel: () -> Void

    @State private var expanded: SpanField?

    private enum SpanField { case warmUp, work, rest, coolDown }

    var body: some View {
        Section {
            Toggle(isOn: $draft.hasWarmUp) { PhaseLabel(title: "Warm-up", color: Tone.prepare.tint) }
                .tint(Tone.prepare.tint)
            if draft.hasWarmUp {
                durationRow("Length", $draft.warmUp, .warmUp)
            }
        }
        Section("Rounds") {
            durationRow("Work", $draft.work, .work, color: Tone.effort.tint)
            Toggle(isOn: $draft.hasRest) { PhaseLabel(title: "Rest", color: Tone.recover.tint) }
                .tint(Tone.recover.tint)
            if draft.hasRest {
                durationRow("Length", $draft.rest, .rest)
            }
            Stepper("Rounds: \(draft.rounds)", value: $draft.rounds, in: 1...99)
            if draft.hasRest {
                Toggle("Rest after last round", isOn: $draft.restAfterLastRound)
                    .tint(Tone.recover.tint)
            }
        }
        Section {
            Toggle(isOn: $draft.hasCoolDown) { PhaseLabel(title: "Cool-down", color: Tone.cool.tint) }
                .tint(Tone.cool.tint)
            if draft.hasCoolDown {
                durationRow("Length", $draft.coolDown, .coolDown)
            }
        }
    }

    private func durationRow(_ label: String, _ seconds: Binding<Int>, _ field: SpanField, color: Color? = nil) -> some View {
        DurationRow(label: label, color: color, identifier: "duration-\(field)", seconds: seconds, isExpanded: expanded == field) {
            willShowWheel()
            withAnimation { expanded = expanded == field ? nil : field }
        }
    }
}

struct PhaseLabel: View {
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

struct DurationRow: View {
    let label: String
    var color: Color?
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
