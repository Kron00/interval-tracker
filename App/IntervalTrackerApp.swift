import IntervalCore
import SwiftUI

@main
struct IntervalTrackerApp: App {
    @State private var log: AudioLog
    @State private var store: LibraryStore
    @State private var history: HistoryStore
    @State private var run: RunModel
    @State private var chatGPT: ChatGPTModel

    init() {
        let log = AudioLog()
        _log = State(initialValue: log)
        _store = State(initialValue: LibraryStore(fileURL: Self.fileURL("library")))
        let history = HistoryStore(fileURL: Self.historyURL())
        _history = State(initialValue: history)
        let run = RunModel(
            player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log),
            liveActivity: LiveActivityController(log: log))
        run.onRunOver = history.record
        _run = State(initialValue: run)
        _chatGPT = State(initialValue: .forThisLaunch())
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, history: history, run: run, log: log)
                .environment(chatGPT)
                .preferredColorScheme(.dark)
        }
    }

    private static var isUITest: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeepLibrary")
    }

    private static func fileURL(_ name: String) -> URL {
        guard isUITest else {
            return URL.applicationSupportDirectory.appendingPathComponent("\(name).json")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(name).json")
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A UI test hands over the history file it wants to start from in `UITEST_HISTORY`. Only a
    /// UI-test launch reads it, because any other launch has the user's own history at this address.
    private static func historyURL() -> URL {
        let url = fileURL("history")
        if isUITest, let seed = ProcessInfo.processInfo.environment["UITEST_HISTORY"] {
            try? Data(seed.utf8).write(to: url)
        }
        return url
    }
}

/// The run screen sits above the library in one hierarchy instead of being presented over it, so
/// starting a run never has to wait for a sheet to finish dismissing.
struct RootView: View {
    let store: LibraryStore
    let history: HistoryStore
    let run: RunModel
    let log: AudioLog

    var body: some View {
        ZStack {
            LibraryScreen(store: store, history: history, run: run, log: log)
                .accessibilityHidden(run.session != nil)
            if let session = run.session {
                RunScreen(run: run, session: session, log: log)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: run.session != nil)
    }
}
