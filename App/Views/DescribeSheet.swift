import IntervalCore
import SwiftUI

enum DescribeState: Equatable {
    case idle
    case generating
    case result(GeneratedWorkout)
    case failed(GenerationFailure)
}

/// Describe a workout in words and get it back built. Nothing reaches the library until Save.
struct DescribeSheet: View {
    let save: (Workout) -> Void
    let edit: (Workout) -> Void
    let close: () -> Void

    @Environment(ChatGPTModel.self) private var chatGPT
    @State private var description = ""
    @State private var state = DescribeState.idle
    @State private var generation: Task<Void, Never>?
    @FocusState private var descriptionIsFocused: Bool

    private static let examples: [(text: String, symbol: String, tone: Tone)] = [
        ("15-minute hip mobility routine", "figure.flexibility", .stretch),
        ("Tabata on the bike, 8 rounds", "figure.outdoor.cycle", .effort),
        ("Pyramid intervals: 1, 2, 3, 2, 1 minutes hard with equal rest", "chart.bar.fill", .recover),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch state {
                    case .idle: form(failure: nil)
                    case .failed(let failure): form(failure: failure)
                    case .generating: waiting
                    case .result(let generated): result(generated)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                        .accessibilityIdentifier("describeCloseButton")
                }
                if case .result = state {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Reword") {
                            show(.idle)
                            descriptionIsFocused = true
                        }
                        .accessibilityIdentifier("rewordButton")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    switch state {
                    case .idle, .failed: startBar
                    case .generating: cancelBar
                    case .result(let generated): resultBar(generated.workout)
                    }
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
        .interactiveDismissDisabled(state != .idle)
        .planUsageNotice(chatGPT)
        .task { await chatGPT.load() }
        .onDisappear { generation?.cancel() }
    }

    private var title: String {
        if case .result(let generated) = state { generated.workout.name } else { "Describe a workout" }
    }

    private func form(failure: GenerationFailure?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let failure {
                FailureCard(failure: failure)
            }
            TextField("A stretch routine, an interval session, anything you can time.", text: $description, axis: .vertical)
                .lineLimit(4...10)
                .font(.system(.title3, design: .rounded))
                .focused($descriptionIsFocused)
                .padding(16)
                .frame(minHeight: 132, alignment: .topLeading)
                .background(Theme.card, in: Theme.cardShape)
                .contentShape(Theme.cardShape)
                .onTapGesture { descriptionIsFocused = true }
                .accessibilityIdentifier("describeField")
            Text("Or start from an example")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(Self.examples.enumerated()), id: \.offset) { index, example in
                    Button {
                        description = example.text
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: example.symbol)
                                .frame(width: 24)
                            Text(example.text)
                                .multilineTextAlignment(.leading)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(example.tone.tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(example.tone.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityIdentifier("example-\(index + 1)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waiting: some View {
        VStack(spacing: 36) {
            VStack(alignment: .leading, spacing: 6) {
                Text("You asked for")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                Text(asked)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.card, in: Theme.cardShape)
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Building your workout")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityIdentifier("generatingTitle")
                Text("This takes a few seconds.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private func result(_ generated: GeneratedWorkout) -> some View {
        VStack(spacing: 22) {
            if let note = generated.note {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .accessibilityIdentifier("generationNote")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            WorkoutBreakdown(workout: generated.workout)
        }
    }

    @ViewBuilder
    private var startBar: some View {
        AccountLine(chatGPT: chatGPT)
        if chatGPT.canPay {
            Button(action: generate) {
                Label("Generate", systemImage: "sparkles")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .disabled(asked.isEmpty)
            .accessibilityIdentifier("generateButton")
        } else {
            ContinueWithChatGPTButton(chatGPT: chatGPT)
        }
        Label("Only the text you type is sent to OpenAI.", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
    }

    private var cancelBar: some View {
        Button(action: cancel) {
            Text("Cancel")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .accessibilityIdentifier("cancelGenerationButton")
    }

    @ViewBuilder
    private func resultBar(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            Button {
                edit(workout)
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("editGeneratedButton")
            Button(action: generate) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("tryAgainButton")
        }
        .buttonStyle(.bordered)
        .tint(.white)
        Button {
            save(workout)
        } label: {
            Label("Save", systemImage: "checkmark")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("saveGeneratedButton")
    }

    private var asked: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generate() {
        let asked = asked
        guard !asked.isEmpty else { return }
        descriptionIsFocused = false
        show(.generating)
        generation = Task {
            let outcome = await chatGPT.generate(asked)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let generated): show(.result(generated))
            case .failure(let failure): show(.failed(failure))
            }
        }
    }

    private func cancel() {
        generation?.cancel()
        show(.idle)
    }

    private func show(_ next: DescribeState) {
        withAnimation(.easeInOut(duration: 0.25)) { state = next }
    }
}

private struct FailureCard: View {
    let failure: GenerationFailure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tone.prepare.tint)
            VStack(alignment: .leading, spacing: 10) {
                Text(failure.message)
                    .font(.subheadline)
                    .accessibilityIdentifier("generationFailure")
                if failure.offersManageUsage {
                    Link("Manage usage", destination: OpenAI.manageUsage)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Tone.prepare.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Who pays for the next request, in one line.
private struct AccountLine: View {
    let chatGPT: ChatGPTModel

    var body: some View {
        VStack(spacing: 6) {
            Label(text, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(chatGPT.canPay ? Tone.stretch.tint : Color.secondary)
                .accessibilityIdentifier("accountLine")
            if let problem = chatGPT.signInProblem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Tone.prepare.tint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var text: String {
        switch chatGPT.status {
        case .planUsage: "Using your ChatGPT plan"
        case .keyOnly: "Using your OpenAI API key"
        case .signedOut: "Sign in to use your ChatGPT plan"
        case .signingIn: "Signing in"
        case .signedInWithoutPlanUsage:
            chatGPT.hasAPIKey ? "Using your OpenAI API key" : "This app may not use your ChatGPT plan yet"
        }
    }

    private var symbol: String {
        switch chatGPT.status {
        case .planUsage: "checkmark.seal.fill"
        case .keyOnly: "key.fill"
        case .signedOut, .signingIn: "person.crop.circle"
        case .signedInWithoutPlanUsage: chatGPT.hasAPIKey ? "key.fill" : "exclamationmark.circle"
        }
    }
}

/// The sign-in button. OpenAI asks for this label.
struct ContinueWithChatGPTButton: View {
    let chatGPT: ChatGPTModel
    var minHeight: CGFloat = 64

    var body: some View {
        Button {
            Task { await chatGPT.signIn(by: .sheet, askAgain: asksAgain) }
        } label: {
            Text(asksAgain ? "Allow plan usage" : "Continue with ChatGPT")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .disabled(chatGPT.status == .signingIn)
        .accessibilityIdentifier("continueWithChatGPT")
    }

    /// Someone who is signed in and declined plan usage is shown ChatGPT's consent page again.
    private var asksAgain: Bool { chatGPT.status == .signedInWithoutPlanUsage }
}

extension View {
    func planUsageNotice(_ chatGPT: ChatGPTModel) -> some View {
        alert("You're using your ChatGPT plan", isPresented: Bindable(chatGPT).planNoticeIsShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Workouts you describe count toward your plan's usage. You can see and limit that in ChatGPT, under Settings, then Usage.")
        }
    }
}
