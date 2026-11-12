import IntervalCore
import SwiftUI
import UIKit

struct SettingsScreen: View {
    let store: LibraryStore
    let log: AudioLog
    let startAudioCheck: () -> Void
    let close: () -> Void

    /// The check describes a 3-second countdown and a spoken "Round one", so it never follows the saved cue settings.
    static let audioCheckCues = CuePreferences(countdown: .three, voice: true)

    @AppStorage(SettingsKey.keepScreenOn) private var keepScreenOn = true
    @AppStorage(SettingsKey.duckingStrategy) private var strategy = DuckingStrategy.toggleOption

    var body: some View {
        NavigationStack {
            Form {
                Section("Cues") {
                    Picker("Countdown", selection: cue(\.countdown)) {
                        ForEach(Countdown.allCases, id: \.self) { countdown in
                            Text(countdown.label).tag(countdown)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Voice cues", isOn: cue(\.voice))
                }

                Section("Screen") {
                    Toggle("Keep screen on during a run", isOn: $keepScreenOn)
                }

                Section {
                    Text("Start your music, run the check, then lock the phone.")
                    Label("At 0:27 you hear three beeps, a tone and \"Round one\". Silence means the app was suspended while locked.", systemImage: "1.circle")
                    Label(strategy.checkExpectation, systemImage: "2.circle")
                    Label("After \"Workout complete\" at 1:02 the music plays at full volume.", systemImage: "3.circle")
                    Button("Run 1-minute audio check", action: startAudioCheck)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("audioCheckButton")
                } header: {
                    Text("Audio check")
                } footer: {
                    Text("The check always uses a 3-second countdown and voice cues, whatever is set above.")
                }

                Section {
                    NavigationLink("Troubleshooting") {
                        TroubleshootingScreen(log: log)
                    }
                    .accessibilityIdentifier("troubleshootingLink")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
    }

    private func cue<Value>(_ keyPath: WritableKeyPath<CuePreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.library.cues[keyPath: keyPath] },
            set: { value in store.update { $0.cues[keyPath: keyPath] = value } })
    }
}

private struct TroubleshootingScreen: View {
    let log: AudioLog

    @AppStorage(SettingsKey.duckingStrategy) private var strategy = DuckingStrategy.toggleOption

    var body: some View {
        Form {
            Section {
                Picker("Music ducking", selection: $strategy) {
                    ForEach(DuckingStrategy.allCases, id: \.self) { strategy in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(strategy.title)
                            Text(strategy.explanation)
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                        .tag(strategy)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Music ducking")
            } footer: {
                Text("How your music is lowered while a cue plays. Change it only if the audio check fails, then run the check again.")
            }

            Section {
                if log.lines.isEmpty {
                    Text("Nothing yet. Lines appear here during a run.")
                        .foregroundStyle(Color.secondary)
                } else {
                    Button("Copy log") {
                        UIPasteboard.general.string = log.lines.joined(separator: "\n")
                    }
                    ForEach(Array(log.lines.enumerated()), id: \.offset) { line in
                        Text(line.element)
                            .font(.caption.monospaced())
                    }
                }
            } header: {
                Text("Audio log")
            }
        }
        .navigationTitle("Troubleshooting")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Countdown {
    var label: String {
        switch self {
        case .off: "Off"
        case .three: "3 s"
        case .five: "5 s"
        }
    }
}

private extension DuckingStrategy {
    var title: String {
        switch self {
        case .toggleOption: "Dip for each cue"
        case .cycleSession: "Dip, then restart audio"
        case .wholeRun: "Low for the whole run"
        }
    }

    var checkExpectation: String {
        switch self {
        case .toggleOption, .cycleSession:
            "The music dips for each cue and returns to full between cues. If it stays low or never dips, change Music ducking under Troubleshooting."
        case .wholeRun:
            "The music stays low for the whole check, because Music ducking is set to low for the whole run."
        }
    }

    var explanation: String {
        switch self {
        case .toggleOption: "Lowers the music around each cue. Try this first."
        case .cycleSession: "Restarts the app's audio after each cue to force the music back up."
        case .wholeRun: "Keeps the music lowered from start to finish, so cues are always heard."
        }
    }
}
