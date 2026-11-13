import IntervalCore
import SwiftUI
import UIKit

struct SettingsScreen: View {
    let store: LibraryStore
    let log: AudioLog
    /// nil while the Live Activity works.
    let liveActivityProblem: String?
    let startAudioCheck: () -> Void
    let close: () -> Void

    /// The check describes a spoken "Get ready", a 3-second countdown and a spoken "Round one", so it
    /// never follows the saved cue settings. Its warm-up is 30 seconds, which is long enough for 10
    /// seconds of notice and too short for 30.
    static let audioCheckCues = CuePreferences(countdown: .three, voice: true, headsUp: .ten)

    @AppStorage(SettingsKey.keepScreenOn) private var keepScreenOn = true
    @AppStorage(SettingsKey.duckingStrategy) private var strategy = DuckingStrategy.toggleOption
    @AppStorage(SettingsKey.headphoneControls) private var headphoneControls = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Countdown", selection: cue(\.countdown)) {
                        ForEach(Countdown.allCases, id: \.self) { countdown in
                            Text(countdown.label).tag(countdown)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Voice cues", isOn: cue(\.voice))
                    Picker("Get ready before work", selection: cue(\.headsUp)) {
                        ForEach(HeadsUp.allCases, id: \.self) { headsUp in
                            Text(headsUp.label).tag(headsUp)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Cues")
                } footer: {
                    Text("In an interval timer, the voice says \"Get ready\" this long before a warm-up or a rest ends and work begins. A phase gets no notice if it is less than 15 seconds longer than this.")
                }

                Section {
                    LabeledContent("Live Activity", value: liveActivityProblem == nil ? "On" : "Off")
                } header: {
                    Text("Lock screen and Dynamic Island")
                } footer: {
                    Text(liveActivityProblem ?? "A workout shows on the lock screen and in the Dynamic Island, with the time left and what is up next, while you use other apps. It lights up when the voice says \"Get ready\".")
                }

                Section {
                    Toggle("Headphone controls", isOn: $headphoneControls)
                        .accessibilityIdentifier("headphoneControlsSetting")
                } header: {
                    Text("Headphones")
                } footer: {
                    Text("Music from other apps stops during a workout. Press to pause or resume. Double-press to skip a phase, or to move on from a stretch. Triple-press to restart. While a stretch routine waits, a single press is Start or Next.")
                }

                Section("Screen") {
                    Toggle("Keep screen on during a run", isOn: $keepScreenOn)
                }

                Section {
                    Text("Start your music, run the check, then lock the phone.")
                    Label("The lock screen shows \"Warm-up\" with a countdown. At 0:20 you hear \"Get ready. Ten seconds.\" and the lock screen lights up.", systemImage: "1.circle")
                    Label("At 0:27 you hear three beeps, a tone and \"Round one\". Silence means the app was suspended while locked.", systemImage: "2.circle")
                    if headphoneControls {
                        Label("The music stops when the check starts, because Headphone controls is on.", systemImage: "3.circle")
                    } else {
                        Label(strategy.checkExpectation, systemImage: "3.circle")
                        Label("After \"Workout complete\" at 1:02 the music plays at full volume.", systemImage: "4.circle")
                    }
                    Button("Run 1-minute audio check", action: startAudioCheck)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("audioCheckButton")
                } header: {
                    Text("Audio check")
                } footer: {
                    Text("The check always uses 10 seconds of notice, a 3-second countdown and voice cues, whatever is set above.")
                }

                Section {
                    Text("Turn on Headphone controls, run the audio check, then lock the phone.")
                    Label("The lock screen shows \"Warm-up\" and \"Audio check\" with pause, back and forward buttons.", systemImage: "1.circle")
                    Label("Press pause, wait 10 seconds, then press play. The countdown carries on from where it stopped.", systemImage: "2.circle")
                    Label("Now press the headphones. One press pauses, two skip, three restart.", systemImage: "3.circle")
                } header: {
                    Text("Headphone check")
                } footer: {
                    Text("If the lock screen shows nothing, or a press does nothing, open Troubleshooting, tap Copy log, and report it.")
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

private extension HeadsUp {
    var label: String {
        switch self {
        case .off: "Off"
        case .ten: "10 s"
        case .thirty: "30 s"
        }
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
