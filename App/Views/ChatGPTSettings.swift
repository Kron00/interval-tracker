import IntervalCore
import SwiftUI

/// The ChatGPT sections of the Settings form: the sign-in, the model, and the API key.
struct ChatGPTSettings: View {
    @Environment(ChatGPTModel.self) private var chatGPT
    @State private var keyDraft = ""
    @State private var pastedAddress = ""
    @State private var showsSafariRoute = false

    var body: some View {
        Section {
            StatusRow(chatGPT: chatGPT)
                .planUsageNotice(chatGPT)
                .task {
                    await chatGPT.load()
                    await chatGPT.loadModels()
                }
            if chatGPT.canPay, !chatGPT.models.isEmpty {
                Picker("Model", selection: Bindable(chatGPT).model) {
                    ForEach(chatGPT.models, id: \.self) { model in
                        Text(model).tag(Optional(model))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("modelPicker")
            }
            switch chatGPT.status {
            case .signedOut, .keyOnly: signedOutRows
            case .signingIn: signingInRows
            case .planUsage: signedInRows
            case .signedInWithoutPlanUsage:
                ContinueWithChatGPTButton(chatGPT: chatGPT, minHeight: 50)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                signOutButton
            }
        } header: {
            Text("ChatGPT")
        } footer: {
            Text("In the library, tap + and then Describe a workout. Only the text you type is sent to OpenAI.")
        }

        Section {
            if chatGPT.hasAPIKey {
                LabeledContent("API key", value: "Saved on this iPhone")
                Button("Remove key", role: .destructive) {
                    Task { await chatGPT.setAPIKey(nil) }
                }
                .accessibilityIdentifier("removeKeyButton")
            } else {
                SecureField("sk-...", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("apiKeyField")
                Button("Save key") {
                    let key = keyDraft
                    keyDraft = ""
                    Task { await chatGPT.setAPIKey(key) }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("saveKeyButton")
            }
        } header: {
            Text("OpenAI API key")
        } footer: {
            Text("Optional. The key pays when you are not signed in, or when your plan cannot be used here. OpenAI bills a key for each request. The key is kept in this iPhone's Keychain.")
        }
    }

    @ViewBuilder
    private var signedOutRows: some View {
        ContinueWithChatGPTButton(chatGPT: chatGPT, minHeight: 50)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        if let problem = chatGPT.signInProblem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(Tone.prepare.tint)
                .accessibilityIdentifier("signInProblem")
        }
        DisclosureGroup("Trouble signing in?", isExpanded: $showsSafariRoute) {
            Text("Sign in with Safari instead. When ChatGPT is done, Safari may say that it cannot open the page. Copy the address from Safari's address bar, come back here, and paste it.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            Button("Sign in with Safari") {
                Task { await chatGPT.signIn(by: .safari) }
            }
            .accessibilityIdentifier("signInWithSafari")
        }
        .accessibilityIdentifier("signInTrouble")
    }

    @ViewBuilder
    private var signingInRows: some View {
        if chatGPT.signInRoute == .safari {
            TextField("Paste the address", text: $pastedAddress, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("pasteAddressField")
            Button("Finish sign-in") {
                chatGPT.paste(pastedAddress)
                pastedAddress = ""
            }
            .disabled(pastedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("finishSignInButton")
            if let problem = chatGPT.signInProblem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Tone.prepare.tint)
                    .accessibilityIdentifier("signInProblem")
            }
        }
        Button("Cancel sign-in", role: .destructive, action: chatGPT.cancelSignIn)
            .accessibilityIdentifier("cancelSignInButton")
    }

    @ViewBuilder
    private var signedInRows: some View {
        Link(destination: OpenAI.manageUsage) {
            LabeledContent("Manage usage") {
                Image(systemName: "arrow.up.right")
            }
        }
        .accessibilityIdentifier("manageUsageLink")
        signOutButton
    }

    private var signOutButton: some View {
        Button("Sign out", role: .destructive) {
            Task { await chatGPT.signOut() }
        }
        .accessibilityIdentifier("signOutButton")
    }
}

/// The account in one row: a mark, what pays, and who is signed in.
private struct StatusRow: View {
    let chatGPT: ChatGPTModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isOn ? Color.black : Color.secondary)
                .frame(width: 44, height: 44)
                .background(isOn ? Tone.stretch.tint : Color(white: 0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityIdentifier("chatGPTStatus")
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            if chatGPT.status == .signingIn {
                Spacer()
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }

    private var isOn: Bool { chatGPT.status == .planUsage }

    private var title: String {
        switch chatGPT.status {
        case .planUsage: "Using ChatGPT plan"
        case .signedOut: "Build workouts with ChatGPT"
        case .signingIn: "Signing in"
        case .keyOnly: "Using your API key"
        case .signedInWithoutPlanUsage: "Signed in without plan usage"
        }
    }

    private var detail: String {
        switch chatGPT.status {
        case .planUsage: chatGPT.email ?? "Signed in"
        case .signedOut: "Sign in to pay with your ChatGPT plan."
        case .signingIn: chatGPT.signInRoute == .safari ? "Finish in Safari, then come back." : "Finish on the ChatGPT page."
        case .keyOnly: "Sign in to pay with your ChatGPT plan instead."
        case .signedInWithoutPlanUsage:
            chatGPT.hasAPIKey ? "Your API key pays until you allow it." : "Allow it to build workouts on your plan."
        }
    }
}
