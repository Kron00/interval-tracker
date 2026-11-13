import Foundation
import IntervalCore
import Observation

/// The monitor the user picked. It is kept between launches.
struct RememberedMonitor: Codable, Equatable {
    let id: UUID
    let name: String
}

/// What the screens show for the heart rate now.
enum HeartRateDisplay: Equatable {
    case live(bpm: Int, zone: HeartRateZone)
    /// A dash, while the app looks for the monitor or waits for it to answer.
    case connecting
    /// A dash, because the last reading is too old or the link is down.
    case noSignal
}

/// The heart-rate monitor as the app sees it: which one is remembered, how the link stands, and the
/// latest reading. The run screen's readout and Settings observe it. `RunModel` takes its readings.
@MainActor @Observable
final class HeartRateMonitor {
    /// What asks for the monitor to be connected. Bluetooth is left alone while nothing does.
    enum Need {
        case run, settings
    }

    private(set) var remembered: RememberedMonitor?
    private(set) var link = HeartRateLink.idle
    private(set) var latest: HeartRateReading?
    /// What the scan in progress has found, strongest signal first.
    private(set) var found: [FoundMonitor] = []
    var maxHeartRate: MaxHeartRate {
        didSet { defaults.set(maxHeartRate.value, forKey: Key.maxHeartRate) }
    }

    /// Receives every reading that the monitor sends.
    @ObservationIgnored var onReading: ((HeartRateReading) -> Void)?
    @ObservationIgnored private let source: any HeartRateSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var needs: Set<Need> = []
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var applied: HeartRateDemand?

    private enum Key {
        static let monitor = "heartRateMonitor"
        static let maxHeartRate = "maxHeartRate"
    }

    init(source: any HeartRateSource, defaults: UserDefaults) {
        self.source = source
        self.defaults = defaults
        remembered = defaults.data(forKey: Key.monitor).flatMap { try? JSONDecoder().decode(RememberedMonitor.self, from: $0) }
        maxHeartRate = MaxHeartRate(defaults.integer(forKey: Key.maxHeartRate)) ?? .standard
        source.onEvent = { [weak self] in self?.handle($0) }
    }

    /// Bluetooth, unless this is a test. A launch with `-hrStub new` or `-hrStub remembered` gets the
    /// stand-in and settings that last as long as the app runs, with or without its monitor
    /// remembered. UI tests and the app that hosts the app tests get the stand-in too, so no test
    /// touches Bluetooth.
    static func forThisLaunch() -> HeartRateMonitor {
        let process = ProcessInfo.processInfo
        let isTest = process.environment["XCTestConfigurationFilePath"] != nil
            || process.arguments.contains("-uiTesting") || process.arguments.contains("-uiTestingKeepLibrary")
        guard let stub = UserDefaults.standard.string(forKey: "hrStub") ?? (isTest ? "new" : nil) else {
            return HeartRateMonitor(source: BluetoothHeartRateSource(), defaults: .standard)
        }
        let suite = "hrStub"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let monitor = HeartRateMonitor(source: StubHeartRateSource(), defaults: UserDefaults(suiteName: suite) ?? .standard)
        if stub == "remembered" { monitor.remember(StubHeartRateSource.monitor) }
        return monitor
    }

    func need(_ need: Need, _ isNeeded: Bool) {
        if isNeeded { needs.insert(need) } else { needs.remove(need) }
        reconcile()
    }

    func scan(_ isOn: Bool) {
        isScanning = isOn
        if isOn { found = [] }
        reconcile()
    }

    func remember(_ monitor: FoundMonitor) {
        remembered = RememberedMonitor(id: monitor.id, name: monitor.name)
        defaults.set(try? JSONEncoder().encode(remembered), forKey: Key.monitor)
        latest = nil
        attempt += 1
        reconcile()
    }

    func forget() {
        remembered = nil
        defaults.removeObject(forKey: Key.monitor)
        latest = nil
        reconcile()
    }

    /// nil while no monitor is remembered, and then nothing about heart rate shows.
    func display(at now: Date) -> HeartRateDisplay? {
        remembered == nil ? nil : Self.display(latest: latest, link: link, maxHeartRate: maxHeartRate, at: now)
    }

    /// A number shows only while the link is up and the reading is fresh. A stale number is never
    /// shown as if it were live.
    static func display(latest: HeartRateReading?, link: HeartRateLink, maxHeartRate: MaxHeartRate, at now: Date) -> HeartRateDisplay {
        if link == .connected, let latest, latest.isFresh(at: now) {
            return .live(bpm: latest.bpm, zone: maxHeartRate.zone(of: latest.bpm))
        }
        return link == .connecting || link == .searching ? .connecting : .noSignal
    }

    private func handle(_ event: HeartRateEvent) {
        switch event {
        case .link(let link):
            self.link = link
        case .found(let monitor):
            guard isScanning else { return }
            found = (found.filter { $0.id != monitor.id } + [monitor]).sorted { $0.rssi > $1.rssi }
        case .beat(let bpm):
            guard remembered != nil, let reading = HeartRateReading(bpm: bpm, at: .now) else { return }
            latest = reading
            onReading?(reading)
        }
    }

    private func reconcile() {
        let demand = HeartRateDemand(isScanning: isScanning, monitor: needs.isEmpty ? nil : remembered?.id, attempt: attempt)
        guard demand != applied else { return }
        applied = demand
        source.apply(demand)
    }
}

extension RunActivityAttributes.HeartRate {
    init(_ display: HeartRateDisplay) {
        self = if case .live(let bpm, let zone) = display { .reading(bpm: bpm, zone: ZoneTone(zone)) } else { .dash }
    }
}

extension ZoneTone {
    init(_ zone: HeartRateZone) {
        self = switch zone {
        case .belowOne: .below
        case .one: .one
        case .two: .two
        case .three: .three
        case .four: .four
        case .five: .five
        }
    }
}
