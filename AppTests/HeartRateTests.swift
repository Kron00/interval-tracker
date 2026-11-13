import IntervalCore
import XCTest
@testable import IntervalTracker

/// Stands in for Bluetooth. It records what the app asks of it, and a test sends its events.
final class ScriptedHeartRateSource: HeartRateSource {
    var onEvent: (@MainActor (HeartRateEvent) -> Void)?
    private(set) var demands: [HeartRateDemand] = []

    func apply(_ demand: HeartRateDemand) {
        demands.append(demand)
    }

    @MainActor
    func send(_ event: HeartRateEvent) {
        onEvent?(event)
    }
}

extension HeartRateMonitor {
    /// A monitor whose settings last only as long as the test.
    @MainActor
    static func scripted(_ source: ScriptedHeartRateSource = ScriptedHeartRateSource()) -> HeartRateMonitor {
        let suite = "heart-rate-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return HeartRateMonitor(source: source, defaults: defaults)
    }
}

/// Byte arrays written from the Bluetooth SIG's Heart Rate Measurement characteristic.
final class HeartRateMeasurementTests: XCTestCase {
    func testAnEightBitHeartRate() {
        XCTAssertEqual(HeartRateMeasurement.bpm(from: Data([0x00, 0x48])), 72)
        XCTAssertEqual(HeartRateMeasurement.bpm(from: Data([0x06, 0xB4])), 180, "the bits for skin contact leave the value alone")
        XCTAssertEqual(HeartRateMeasurement.bpm(from: Data([0x18, 0x50, 0x10, 0x00, 0x20, 0x03])), 80,
                       "energy expended and an RR interval follow the value and are not read")
    }

    func testASixteenBitHeartRateIsLeastSignificantByteFirst() {
        XCTAssertEqual(HeartRateMeasurement.bpm(from: Data([0x01, 0x48, 0x00])), 72)
        XCTAssertEqual(HeartRateMeasurement.bpm(from: Data([0x01, 0x2C, 0x01])), 300)
        XCTAssertEqual(HeartRateMeasurement.bpm(from: Data([0x19, 0x8C, 0x00, 0x10, 0x00, 0x20, 0x03])), 140)
    }

    func testAValueTooShortForItsFlagsHasNoHeartRate() {
        XCTAssertNil(HeartRateMeasurement.bpm(from: Data()))
        XCTAssertNil(HeartRateMeasurement.bpm(from: Data([0x00])))
        XCTAssertNil(HeartRateMeasurement.bpm(from: Data([0x01, 0x48])))
    }
}

@MainActor
final class HeartRateMonitorTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testANumberShowsOnlyWhileTheLinkIsUpAndTheReadingIsFresh() throws {
        let reading = try XCTUnwrap(HeartRateReading(bpm: 150, at: now))
        func display(_ link: HeartRateLink, after seconds: TimeInterval) -> HeartRateDisplay {
            HeartRateMonitor.display(latest: reading, link: link, maxHeartRate: .standard, at: now + seconds)
        }
        XCTAssertEqual(display(.connected, after: 0), .live(bpm: 150, zone: .three))
        XCTAssertEqual(display(.connected, after: 5), .live(bpm: 150, zone: .three))
        XCTAssertEqual(display(.connected, after: 5.1), .noSignal, "a reading older than 5 seconds is not shown")
        XCTAssertEqual(display(.lost, after: 1), .noSignal, "nor is one from a link that has dropped")
        XCTAssertEqual(display(.connecting, after: 1), .connecting)
        XCTAssertEqual(HeartRateMonitor.display(latest: nil, link: .connected, maxHeartRate: .standard, at: now), .noSignal)
    }

    func testWithNoMonitorRememberedNothingShowsAndBluetoothIsLeftAlone() {
        let source = ScriptedHeartRateSource()
        let monitor = HeartRateMonitor.scripted(source)
        monitor.need(.run, true)
        monitor.need(.settings, true)
        XCTAssertNil(monitor.display(at: now))
        XCTAssertFalse(source.demands.contains { $0.needsBluetooth }, "\(source.demands)")
    }

    func testPickingAMonitorConnectsToItWhileSettingsIsOpenAndForgettingLetsItGo() {
        let source = ScriptedHeartRateSource()
        let monitor = HeartRateMonitor.scripted(source)
        monitor.need(.settings, true)
        monitor.scan(true)
        XCTAssertEqual(source.demands.last, HeartRateDemand(isScanning: true, monitor: nil, attempt: 0))

        let strap = FoundMonitor(id: UUID(), name: "Strap", rssi: -70)
        source.send(.found(strap))
        source.send(.found(StubHeartRateSource.monitor))
        XCTAssertEqual(monitor.found.map(\.name), ["Stand-in strap", "Strap"], "the strongest signal first")

        monitor.remember(strap)
        monitor.scan(false)
        XCTAssertEqual(source.demands.last, HeartRateDemand(isScanning: false, monitor: strap.id, attempt: 1))
        source.send(.link(.connected))
        source.send(.beat(bpm: 0))
        XCTAssertNil(monitor.latest, "0 is what a strap sends without skin contact")
        source.send(.beat(bpm: 96))
        XCTAssertEqual(monitor.display(at: .now), .live(bpm: 96, zone: .one))

        monitor.remember(strap)
        XCTAssertEqual(source.demands.last?.attempt, 2, "picking the same monitor again tries again after a refusal")

        monitor.forget()
        XCTAssertEqual(source.demands.last, HeartRateDemand(isScanning: false, monitor: nil, attempt: 2))
        XCTAssertNil(monitor.display(at: .now))
    }
}

@MainActor
final class RunHeartRateTests: XCTestCase {
    private var reports: [WorkoutRecord] = []

    func testARunKeepsReadingsOnlyWhileItRunsAndPutsTheirSummaryOnItsRecord() throws {
        let source = ScriptedHeartRateSource()
        let monitor = HeartRateMonitor.scripted(source)
        monitor.remember(StubHeartRateSource.monitor)
        monitor.maxHeartRate = try XCTUnwrap(MaxHeartRate(200))
        let run = makeRun(monitor)
        XCTAssertNil(source.demands.last?.monitor, "nothing connects before a workout")

        source.send(.link(.connected))
        source.send(.beat(bpm: 180))
        run.start(.norwegian4x4, cues: CuePreferences())
        XCTAssertEqual(source.demands.last?.monitor, StubHeartRateSource.monitor.id, "a workout connects to the remembered monitor")

        source.send(.beat(bpm: 100))
        source.send(.beat(bpm: 120))
        run.pause()
        source.send(.beat(bpm: 190))
        run.resume()
        source.send(.beat(bpm: 143))
        run.end()
        source.send(.beat(bpm: 170))
        XCTAssertNil(source.demands.last?.monitor, "the monitor is let go when the workout ends")

        XCTAssertEqual(reports.count, 1)
        let heartRate = try XCTUnwrap(reports.first?.heartRate)
        XCTAssertEqual(heartRate.average, 121, "100, 120 and 143. Before the start, while paused and after the end are not kept")
        XCTAssertEqual(heartRate.maximum, 143)
        XCTAssertEqual(heartRate.maxHeartRate.value, 200)
        XCTAssertEqual(heartRate.trace.map(\.bpm), [121], "all three came in the first five seconds")

        run.start(.norwegian4x4, cues: CuePreferences())
        run.end()
        XCTAssertEqual(reports.count, 2)
        XCTAssertNil(reports.last?.heartRate, "a run with no reading has no heart rate")
    }

    /// Undo of Start puts the run's clock back to the wait. The seconds read since then are run again,
    /// so they must not also count as time in a zone.
    func testUndoOfStartDropsTheReadingsItTookBack() async throws {
        let source = ScriptedHeartRateSource()
        let monitor = HeartRateMonitor.scripted(source)
        monitor.remember(StubHeartRateSource.monitor)
        monitor.maxHeartRate = try XCTUnwrap(MaxHeartRate(200))
        let run = makeRun(monitor)
        source.send(.link(.connected))

        run.start(.dailyStretch, cues: CuePreferences())
        run.handle(.play)
        guard case .active(let waiting)? = run.session?.snapshot(at: .now), waiting.isWaiting else {
            return XCTFail("Next on Cat-Cow should leave the run waiting for Start")
        }
        run.handle(.play)
        source.send(.beat(bpm: 150))
        try await Task.sleep(for: .milliseconds(1500))
        source.send(.beat(bpm: 150))
        run.undoLast()
        source.send(.beat(bpm: 110))
        run.end()

        let heartRate = try XCTUnwrap(reports.first?.heartRate)
        XCTAssertLessThan(heartRate.secondsInZone.reduce(0, +), 0.5,
                          "the second and a half before Undo is not time in a zone")
    }

    func testTheLiveActivityCarriesTheHeartRateOfARunWithAMonitor() async throws {
        let source = ScriptedHeartRateSource()
        let monitor = HeartRateMonitor.scripted(source)
        monitor.remember(StubHeartRateSource.monitor)
        let display = RecordingDisplay()
        let card = LiveActivityController(display: display, log: AudioLog())
        let log = AudioLog()
        let run = RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log),
                           liveActivity: card, heartRate: monitor)
        defer { run.end() }

        run.start(.norwegian4x4, cues: CuePreferences())
        await card.settle()
        XCTAssertEqual(display.shown.last?.state.heartRate, .dash, "no reading yet")

        source.send(.link(.connected))
        source.send(.beat(bpm: 150))
        run.pause()
        await card.settle()
        XCTAssertEqual(display.shown.last?.state.heartRate, .reading(bpm: 150, zone: .three))
    }

    private func makeRun(_ monitor: HeartRateMonitor) -> RunModel {
        let log = AudioLog()
        let run = RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log),
                           liveActivity: LiveActivityController(display: RecordingDisplay(), log: log), heartRate: monitor)
        run.onRunOver = { [unowned self] in reports.append($0) }
        addTeardownBlock { @MainActor in run.end() }
        return run
    }
}

@MainActor
final class LiveActivityHeartRateTests: XCTestCase {
    private typealias HeartRate = RunActivityAttributes.HeartRate
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// iOS ends the card of a finished workout. A change sent to it would start a new one.
    func testAFinishedWorkoutsCardTakesNoHeartRate() async throws {
        let source = ScriptedHeartRateSource()
        let monitor = HeartRateMonitor.scripted(source)
        monitor.remember(StubHeartRateSource.monitor)
        let display = RecordingDisplay()
        let card = LiveActivityController(display: display, log: AudioLog())
        let log = AudioLog()
        let run = RunModel(player: CuePlayer(bank: SoundBank(log: log), log: log), remote: HeadphoneRemote(log: log),
                           liveActivity: card, heartRate: monitor)
        defer { run.end() }
        source.send(.link(.connected))
        source.send(.beat(bpm: 150))

        run.start(.hiit2020, cues: CuePreferences())
        for _ in 0..<40 {
            guard case .active(let progress)? = run.session?.snapshot(at: .now) else { break }
            run.skip(progress.segment)
        }
        guard case .finished? = run.session?.snapshot(at: .now) else { return XCTFail("the skips did not finish the workout") }
        try await Task.sleep(for: .milliseconds(300))
        await card.settle()
        let finished = display.shown.count
        guard case .finished = display.shown.last?.state.clock else { return XCTFail("the card does not show the finish") }
        XCTAssertNil(display.shown.last?.state.heartRate)

        source.send(.beat(bpm: 100))
        source.send(.beat(bpm: 185))
        try await Task.sleep(for: .milliseconds(300))
        await card.settle()
        XCTAssertEqual(display.shown.count, finished, "heart rate changes after the finish send nothing")
    }

    func testTheHeartRateAloneIsSentAtMostEveryFiveSecondsAndAChangeOfZoneAtOnce() async {
        let display = RecordingDisplay()
        let controller = LiveActivityController(display: display, log: AudioLog())
        await controller.settle()
        var session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        var expected: [HeartRate?] = []
        func reconcile(_ second: TimeInterval, _ heartRate: HeartRate, sent: Bool) async {
            controller.reconcile(session, at: start + second, heartRate: heartRate)
            await controller.settle()
            if sent { expected.append(heartRate) }
        }

        await reconcile(0, .reading(bpm: 120, zone: .two), sent: true)
        await reconcile(1, .reading(bpm: 121, zone: .two), sent: false)
        await reconcile(4.9, .reading(bpm: 125, zone: .two), sent: false)
        await reconcile(5, .reading(bpm: 126, zone: .two), sent: true)
        await reconcile(6, .reading(bpm: 140, zone: .three), sent: true)
        await reconcile(7, .reading(bpm: 141, zone: .three), sent: false)
        await reconcile(8, .dash, sent: true)
        await reconcile(9, .reading(bpm: 141, zone: .three), sent: true)
        await reconcile(10, .reading(bpm: 142, zone: .three), sent: false)
        await reconcile(14, .reading(bpm: 143, zone: .three), sent: true)
        await reconcile(15, .reading(bpm: 144, zone: .three), sent: false)
        session.pause(at: start + 16)
        await reconcile(16, .reading(bpm: 145, zone: .three), sent: true)

        XCTAssertEqual(display.shown.map(\.state.heartRate), expected)
        XCTAssertEqual(display.shown.last?.state.clock, .paused("4:44"), "a change of state goes out at once, with the heart rate of the moment")
    }

    func testARunWithNoMonitorSendsWhatItSentBefore() async {
        let display = RecordingDisplay()
        let controller = LiveActivityController(display: display, log: AudioLog())
        let session = Session(.norwegian4x4, cues: CuePreferences(), startingAt: start)
        for tick in 0..<30 {
            controller.reconcile(session, at: start + Double(tick) / 2)
            await controller.settle()
        }
        XCTAssertEqual(display.shown, [RunActivityCard(name: "Norwegian 4x4", state: .init(session, at: start))])
        XCTAssertNil(display.shown.first?.state.heartRate)
    }
}
