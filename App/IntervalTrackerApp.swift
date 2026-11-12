import IntervalCore
import SwiftUI

@main
struct IntervalTrackerApp: App {
    @State private var log: AudioLog
    @State private var store: LibraryStore
    @State private var run: RunModel

    init() {
        let log = AudioLog()
        _log = State(initialValue: log)
        _store = State(initialValue: LibraryStore(fileURL: Self.libraryURL()))
        _run = State(initialValue: RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log)))
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, run: run, log: log)
        }
    }

    /// UI tests get a throwaway file. `-uiTesting` starts it empty, `-uiTestingKeepLibrary` reuses it
    /// so a test can relaunch and see what the previous launch saved.
    private static func libraryURL() -> URL {
        let arguments = ProcessInfo.processInfo.arguments
        let fresh = arguments.contains("-uiTesting")
        guard fresh || arguments.contains("-uiTestingKeepLibrary") else {
            return URL.applicationSupportDirectory.appendingPathComponent("library.json")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-library.json")
        if fresh { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

/// The run screen sits above the library in one hierarchy instead of being presented over it, so
/// starting a run never has to wait for a sheet to finish dismissing.
struct RootView: View {
    let store: LibraryStore
    let run: RunModel
    let log: AudioLog

    var body: some View {
        ZStack {
            LibraryScreen(store: store, run: run, log: log)
                .accessibilityHidden(run.session != nil)
            if let session = run.session {
                RunScreen(run: run, session: session)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: run.session != nil)
    }
}
