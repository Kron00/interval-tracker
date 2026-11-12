import IntervalCore
import SwiftUI
import UIKit

struct SettingsScreen: View {
    let store: LibraryStore
    let log: AudioLog
    let startAudioCheck: () -> Void
    let close: () -> Void

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
                    Text("How your music is lowered while a cue plays. If the audio check fails with one, try the next.")
                }

                Section {
                    Text("Start your music, run the check, then lock the phone.")
                    Label("At 0:27 you hear three beeps, a tone and \"Round one\". Silence means the app was suspended while locked.", systemImage: "1.circle")
                    Label("The music dips for each cue and returns to full between them. If it stays low, change the ducking setting above.", systemImage: "2.circle")
                    Label("After \"Workout complete\" at 1:02 the music keeps playing at full volume.", systemImage: "3.circle")
                    Button("Run 1-minute audio check", action: startAudioCheck)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("audioCheckButton")
                } header: {
                    Text("Audio check")
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

    var explanation: String {
        switch self {
        case .toggleOption: "Lowers the music around each cue. Try this first."
        case .cycleSession: "Restarts the app's audio after each cue to force the music back up."
        case .wholeRun: "Keeps the music lowered from start to finish, so cues are always heard."
        }
    }
}
