import IntervalCore
import SwiftUI

@main
struct IntervalTrackerApp: App {
    @State private var log: AudioLog
    @State private var store: LibraryStore
    @State private var history: HistoryStore
    @State private var run: RunModel

    init() {
        let log = AudioLog()
        _log = State(initialValue: log)
        _store = State(initialValue: LibraryStore(fileURL: Self.fileURL("library")))
        let history = HistoryStore(fileURL: Self.historyURL())
        _history = State(initialValue: history)
        let run = RunModel(
            player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log))
        run.onRunOver = history.record
        _run = State(initialValue: run)
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, history: history, run: run, log: log)
                .preferredColorScheme(.dark)
        }
    }

    private static func fileURL(_ name: String) -> URL {
        let arguments = ProcessInfo.processInfo.arguments
        let fresh = arguments.contains("-uiTesting")
        guard fresh || arguments.contains("-uiTestingKeepLibrary") else {
            return URL.applicationSupportDirectory.appendingPathComponent("\(name).json")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(name).json")
        if fresh { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A UI test hands over the history file it wants to start from in `UITEST_HISTORY`.
    private static func historyURL() -> URL {
        let url = fileURL("history")
        if let seed = ProcessInfo.processInfo.environment["UITEST_HISTORY"] {
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
