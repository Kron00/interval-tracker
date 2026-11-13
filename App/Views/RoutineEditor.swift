import IntervalCore
import SwiftUI

struct RoutineDraft: Equatable {
    var getReady = 10
    var switchSides = 5
    var stretches: [StretchDraft] = []

    init() {}

    init(_ routine: Routine) {
        getReady = routine.getReady.seconds
        switchSides = routine.switchSides.seconds
        stretches = routine.stretches.map(StretchDraft.init)
    }

    var routine: Routine? {
        guard let getReady = Span(seconds: getReady), let switchSides = Span(seconds: switchSides) else { return nil }
        let valid = stretches.compactMap(\.stretch)
        guard valid.count == stretches.count else { return nil }
        return Routine(getReady: getReady, switchSides: switchSides, stretches: valid)
    }

    /// Why `routine` is nil, in words. `Routine.init` and `Stretch.init` decide what is valid. This only
    /// works out which of their rules to name.
    var problem: String? {
        if stretches.isEmpty { return "Add a stretch." }
        for (index, stretch) in stretches.enumerated() {
            if let problem = stretch.problem(number: index + 1) { return problem }
        }
        guard routine == nil else { return nil }
        if getReady < Routine.minimumGetReady {
            return "Get ready needs \(clock(Routine.minimumGetReady)) or more, so the voice can name the stretch."
        }
        if switchSides < Routine.minimumSwitchSides {
            return "Switch sides needs \(clock(Routine.minimumSwitchSides)) or more."
        }
        return "A routine holds up to \(Routine.maximumStretches) stretches."
    }

    func number(of id: StretchDraft.ID) -> Int {
        (stretches.firstIndex { $0.id == id } ?? 0) + 1
    }

    /// Looked up by id, so a binding to a stretch stays safe after the list is reordered or the stretch is deleted.
    subscript(stretch id: StretchDraft.ID) -> StretchDraft {
        get { stretches.first { $0.id == id } ?? StretchDraft() }
        set {
            guard let index = stretches.firstIndex(where: { $0.id == id }) else { return }
            stretches[index] = newValue
        }
    }

    private func clock(_ seconds: Int) -> String { ClockText.remaining(TimeInterval(seconds)) }
}

struct StretchDraft: Equatable, Identifiable {
    let id: UUID
    var name = ""
    var usesReps = false
    var holdSeconds = 30
    var reps = 10
    var eachSide = false
    var link = ""

    init() { id = UUID() }

    init(_ stretch: Stretch) {
        id = stretch.id
        name = stretch.name
        switch stretch.amount {
        case .hold(let span):
            holdSeconds = span.seconds
        case .reps(let count):
            usesReps = true
            reps = count.value
        }
        eachSide = stretch.sides == .each
        link = stretch.howTo?.absoluteString ?? ""
    }

    var amount: Amount? {
        usesReps ? Count(reps).map(Amount.reps) : Span(seconds: holdSeconds).map(Amount.hold)
    }

    var sides: Sides { eachSide ? .each : .once }

    var stretch: Stretch? {
        guard let amount, let howTo else { return nil }
        return Stretch(id: id, name: name, amount: amount, sides: sides, howTo: howTo)
    }

    func problem(number: Int) -> String? {
        guard let amount else { return "Stretch \(number) needs a length above 0:00." }
        guard Stretch(id: id, name: name, amount: amount, sides: sides, howTo: nil) != nil else {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Name stretch \(number)."
                : "Shorten the name of stretch \(number) to \(Stretch.maximumNameLength) characters."
        }
        return stretch == nil ? "The link of stretch \(number) is not a web address." : nil
    }

    /// The link as typed, with "https://" added when it has no scheme. The outer nil means the text
    /// is not a link at all. The inner nil means there is no link.
    private var howTo: URL?? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .some(nil) }
        return URL(string: text.contains("://") ? text : "https://" + text).map(Optional.some)
    }
}

extension Amount {
    func text(_ sides: Sides) -> String {
        let amount = switch self {
        case .hold(let span): span.clockText
        case .reps(let count): count.repsText
        }
        return sides == .each ? "\(amount) each side" : amount
    }
}

struct RoutineSections: View {
    @Binding var draft: RoutineDraft
    let willShowWheel: () -> Void
    let open: (StretchDraft.ID) -> Void

    @State private var expanded: Gap?

    private enum Gap { case getReady, switchSides }

    var body: some View {
        Section {
            gapRow("Get ready", $draft.getReady, .getReady, color: Tone.prepare.tint)
            gapRow("Switch sides", $draft.switchSides, .switchSides, color: Tone.recover.tint)
        } header: {
            Text("Gaps")
        } footer: {
            Text("Get ready comes before every stretch, and the voice names the stretch in it. Switch sides comes between the left and the right side. Both run by themselves.")
        }
        Section {
            ForEach(Array(draft.stretches.enumerated()), id: \.element.id) { index, stretch in
                Button {
                    open(stretch.id)
                } label: {
                    StretchRow(number: index + 1, stretch: stretch)
                }
                .accessibilityIdentifier("stretchRow-\(stretch.name)")
            }
            .onMove { draft.stretches.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { draft.stretches.remove(atOffsets: $0) }
            Button {
                let stretch = StretchDraft()
                draft.stretches.append(stretch)
                open(stretch.id)
            } label: {
                Label("Add stretch", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
            }
            .disabled(draft.stretches.count >= Routine.maximumStretches)
            .accessibilityIdentifier("addStretchButton")
        } header: {
            Text("Stretches")
        } footer: {
            Text(draft.stretches.count > 1
                ? "After each stretch the routine waits until you tap Next. Hold and drag a stretch to move it. Swipe left to delete it."
                : "After each stretch the routine waits until you tap Next.")
                .accessibilityIdentifier("stretchesFooter")
        }
    }

    private func gapRow(_ label: String, _ seconds: Binding<Int>, _ gap: Gap, color: Color) -> some View {
        DurationRow(label: label, color: color, identifier: "duration-\(gap)", seconds: seconds, isExpanded: expanded == gap) {
            willShowWheel()
            withAnimation { expanded = expanded == gap ? nil : gap }
        }
    }
}

private struct StretchRow: View {
    let number: Int
    let stretch: StretchDraft

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Tone.stretch.tint)
                .frame(minWidth: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(stretch.name.isEmpty ? "New stretch" : stretch.name)
                    .foregroundStyle(stretch.name.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(stretch.amount?.text(stretch.sides) ?? "No length")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.6))
        }
        .contentShape(Rectangle())
    }
}

struct StretchEditor: View {
    @Binding var stretch: StretchDraft
    let number: Int

    @State private var holdIsExpanded = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Field { case name, link }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $stretch.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .focused($focus, equals: .name)
                    .submitLabel(.done)
                    .accessibilityIdentifier("stretchNameField")
            } footer: {
                if let problem = stretch.problem(number: number) {
                    Text(problem).accessibilityIdentifier("stretchProblem")
                }
            }
            Section {
                Picker("Amount", selection: $stretch.usesReps) {
                    Text("Hold").tag(false)
                    Text("Reps").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("amountPicker")
                if stretch.usesReps {
                    Stepper("Reps: \(stretch.reps)", value: $stretch.reps, in: 1...99)
                        .accessibilityIdentifier("repsStepper")
                } else {
                    DurationRow(
                        label: "Length", color: Tone.stretch.tint, identifier: "duration-hold",
                        seconds: $stretch.holdSeconds, isExpanded: holdIsExpanded
                    ) {
                        focus = nil
                        withAnimation { holdIsExpanded.toggle() }
                    }
                }
                Toggle("Each side", isOn: $stretch.eachSide)
                    .tint(Tone.stretch.tint)
                    .accessibilityIdentifier("eachSideToggle")
            } footer: {
                Text(amountNote)
            }
            Section {
                TextField("https://", text: $stretch.link)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .link)
                    .submitLabel(.done)
                    .accessibilityIdentifier("stretchLinkField")
                if let link = stretch.stretch?.howTo {
                    Button {
                        openURL(link)
                    } label: {
                        Label("Open link", systemImage: "play.circle.fill")
                    }
                }
            } header: {
                Text("How-to link")
            } footer: {
                Text("A video or a page that shows the stretch. You can open it from the routine, while you get ready, and while the routine waits.")
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Stretch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("stretchDoneButton")
            }
        }
        .onAppear {
            if stretch.name.isEmpty { focus = .name }
        }
    }

    private var amountNote: String {
        [stretch.usesReps ? "Reps are not timed. Do them at your own pace, then tap Next." : "The hold counts down, beeps at zero, then waits for Next.",
         stretch.eachSide ? "Left side first, then right." : nil]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
