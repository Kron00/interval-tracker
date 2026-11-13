import IntervalCore
import SwiftUI

struct RoutineDraft: Equatable {
    /// Picked from a menu of valid values, so it needs no plain draft of its own.
    var countIn = Routine.defaultCountIn
    var stretches: [StretchDraft] = []

    init() {}

    init(_ routine: Routine) {
        countIn = routine.countIn
        stretches = routine.stretches.map(StretchDraft.init)
    }

    var routine: Routine? {
        let valid = stretches.compactMap(\.stretch)
        guard valid.count == stretches.count else { return nil }
        return Routine(countIn: countIn, stretches: valid)
    }

    /// Why `routine` is nil, in words. `Routine.init` and `Stretch.init` decide what is valid. This only
    /// works out which of their rules to name.
    var problem: String? {
        if stretches.isEmpty { return "Add a stretch." }
        for (index, stretch) in stretches.enumerated() {
            if let problem = stretch.problem(number: index + 1) { return problem }
        }
        return routine == nil ? "A routine holds up to \(Routine.maximumStretches) stretches." : nil
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
    let open: (StretchDraft.ID) -> Void

    /// A routine from a file can have a count-in the menu does not offer. It is listed too, so the
    /// menu always shows what the routine has.
    private var countIns: [Span?] {
        let offered = [nil, Span(seconds: 3), Span(seconds: 5), Span(seconds: 10)]
        return offered.contains(draft.countIn)
            ? offered : (offered + [draft.countIn]).sorted { ($0?.seconds ?? 0) < ($1?.seconds ?? 0) }
    }

    var body: some View {
        Section {
            Picker("Count-in after Start", selection: $draft.countIn) {
                ForEach(countIns, id: \.self) { countIn in
                    Text(countIn.map { "\($0.seconds) s" } ?? "Off").tag(countIn)
                }
            }
            .pickerStyle(.menu)
            .tint(Tone.prepare.tint)
            .accessibilityIdentifier("countInPicker")
        } footer: {
            Text("The time between Start and the hold, to get into position. Reps have no count-in.")
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
            Text(waitNote + (draft.stretches.count > 1 ? " Hold and drag a stretch to move it. Swipe left to delete it." : ""))
                .accessibilityIdentifier("stretchesFooter")
        }
    }

    private var waitNote: String {
        "Each stretch waits until you tap Start\(draft.countIn == nil ? "" : ", then counts in"). Reps wait for Next."
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
                Text("A video or a page that shows the stretch. You can open it from the routine while it waits and while it is paused.")
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
        [stretch.usesReps ? "Reps are not timed. Do them at your own pace, then tap Next." : "The hold waits for Start, counts down, and beeps at zero.",
         stretch.eachSide ? "Left side first, then right." : nil]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
