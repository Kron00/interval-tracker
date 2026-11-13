import IntervalCore
import XCTest
@testable import IntervalTracker

@MainActor
final class RunReportTests: XCTestCase {
    /// A wait ends as soon as it is met, so a long limit costs nothing on a healthy machine.
    private static let patience: TimeInterval = 30

    private var reports: [WorkoutRecord] = []

    func testARunThatFinishesByItselfIsReportedOnceAndDoneDoesNotReportItAgain() throws {
        let run = makeRun()
        let began = Date.now
        run.start(try timer(work: 1), cues: CuePreferences())

        waitForReports(1)
        XCTAssertEqual(reports.first?.outcome, .completed)
        XCTAssertEqual(reports.first?.worked, 1)
        XCTAssertEqual(reports.first?.planned, 1)
        XCTAssertEqual(reports.first?.name, "Test")
        XCTAssertEqual(reports.first?.kind, .intervals)
        XCTAssertEqual(try XCTUnwrap(reports.first).startedAt.timeIntervalSince(began), 0, accuracy: 0.5)

        run.end()
        letTheTimerTick()
        XCTAssertEqual(reports.count, 1, "leaving the finish screen reports nothing new")
    }

    func testASkipThatFinishesIsNotReportedWhileUndoCanBringTheRunBack() throws {
        let run = makeRun()
        run.start(try timer(work: 30), cues: CuePreferences())
        run.skip(try progress(run).segment)
        XCTAssertThrowsError(try progress(run), "the skip finished the workout")
        XCTAssertNotNil(run.undo)

        letTheTimerTick()
        XCTAssertEqual(reports, [], "Undo is still offered")

        run.undoLast()
        letTheTimerTick()
        XCTAssertEqual(try progress(run).phase.title, "Work")
        XCTAssertEqual(reports, [], "the run is back, and there is nothing to take out of the history")

        run.end()
        XCTAssertEqual(reports.map(\.outcome), [.endedEarly])
    }

    func testASkipThatFinishesIsReportedWhenTheFinishScreenIsLeft() throws {
        let run = makeRun()
        run.start(try timer(work: 30), cues: CuePreferences())
        run.skip(try progress(run).segment)

        run.end()

        XCTAssertEqual(reports.map(\.outcome), [.completed])
        XCTAssertEqual(reports.first?.planned, 30)
    }

    func testASkipThatFinishesIsReportedOnceUndoIsGone() throws {
        let run = makeRun()
        run.start(try timer(work: 30), cues: CuePreferences())
        run.skip(try progress(run).segment)

        waitForReports(1)
        XCTAssertNil(run.undo)
        XCTAssertEqual(reports.map(\.outcome), [.completed])

        run.end()
        XCTAssertEqual(reports.count, 1)
    }

    func testEndingARunPartWayReportsItAsEndedEarly() throws {
        let run = makeRun()
        run.start(.norwegian4x4, cues: CuePreferences())
        letTheTimerTick()
        XCTAssertEqual(reports, [], "a run in progress is not in the history")

        run.end()

        let record = try XCTUnwrap(reports.first)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(record.outcome, .endedEarly)
        XCTAssertEqual(record.workoutID, Workout.norwegian4x4.id)
        XCTAssertEqual(record.planned, 2280)
        XCTAssertLessThan(record.worked, 5)
    }

    private func makeRun() -> RunModel {
        let log = AudioLog()
        let run = RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log))
        run.onRunOver = { [unowned self] in reports.append($0) }
        addTeardownBlock { @MainActor in run.end() }
        return run
    }

    private func timer(work seconds: Int) throws -> Workout {
        Workout(name: "Test", plan: .intervals(Intervals(
            warmUp: nil, work: try XCTUnwrap(Span(seconds: seconds)), rest: nil,
            rounds: try XCTUnwrap(Count(1)), coolDown: nil)))
    }

    private func progress(_ run: RunModel) throws -> RunProgress {
        guard case .active(let progress)? = run.session?.snapshot(at: .now) else { throw NotActive() }
        return progress
    }

    private func waitForReports(_ count: Int) {
        let deadline = Date.now + Self.patience
        while reports.count < count, Date.now < deadline { RunLoop.main.run(until: .now + 0.05) }
        XCTAssertEqual(reports.count, count)
    }

    /// The model checks ten times a second whether a run is over.
    private func letTheTimerTick() {
        RunLoop.main.run(until: .now + 0.35)
    }

    private struct NotActive: Error {}
}

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testARecordedRunIsReadBackFromTheFile() {
        let completed = record(worked: 2280, .completed)
        let endedEarly = record(worked: 75.5, .endedEarly, startedAt: completed.startedAt + 3600)
        let store = HistoryStore(fileURL: file("history"))
        store.record(completed)
        store.record(endedEarly)

        let reopened = HistoryStore(fileURL: file("history"))

        XCTAssertEqual(reopened.history.records, [endedEarly, completed])
        XCTAssertNil(reopened.problem)
    }

    func testAFalseStartAndTheAudioCheckAreNotKept() {
        let store = HistoryStore(fileURL: file("history"))

        store.record(record(worked: 59, .endedEarly))
        store.record(record(of: .audioCheck, worked: 60, .completed))

        XCTAssertEqual(store.history.records, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file("history").path))
    }

    func testAHistoryFileThatCannotBeReadIsSetAsideAndCostsNoWorkouts() throws {
        let library = LibraryStore(fileURL: file("library"))
        let saved = Workout(name: "Mine", plan: Workout.hiit2020.plan)
        library.update { $0.save(saved) }
        let damaged = Data("{\"version\": 1, \"records\": [{".utf8)
        try damaged.write(to: file("history"))

        let store = HistoryStore(fileURL: file("history"))

        XCTAssertEqual(store.history.records, [])
        XCTAssertNotNil(store.problem)
        let aside = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("history.corrupt-") }
        XCTAssertEqual(try aside.map { try Data(contentsOf: $0) }, [damaged], "the unreadable file is kept under another name")
        XCTAssertEqual(LibraryStore(fileURL: file("library")).library.workouts, [saved])

        let completed = record(worked: 840, .completed)
        store.record(completed)
        XCTAssertEqual(HistoryStore(fileURL: file("history")).history.records, [completed])
    }

    private func file(_ name: String) -> URL {
        folder.appendingPathComponent("\(name).json")
    }

    private func record(of workout: Workout = .hiit2020, worked: TimeInterval, _ outcome: WorkoutRecord.Outcome,
                        startedAt: Date = .now) -> WorkoutRecord {
        WorkoutRecord(startedAt: startedAt, workoutID: workout.id, name: workout.name, kind: workout.plan.kind,
                      worked: worked, planned: workout.totalDuration, outcome: outcome)
    }
}
