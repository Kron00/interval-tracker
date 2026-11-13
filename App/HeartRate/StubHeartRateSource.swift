import Foundation

/// Stands in for Bluetooth when the app is launched with `-hrStub`, and in every test. A scan finds
/// one monitor at once. Once connected, it sends one heart rate a second in a known pattern.
final class StubHeartRateSource: HeartRateSource {
    static let monitor = FoundMonitor(
        id: UUID(uuidString: "48525354-5542-4000-8000-000000000001") ?? UUID(), name: "Stand-in strap", rssi: -52)

    var onEvent: (@MainActor (HeartRateEvent) -> Void)?

    private var demand = HeartRateDemand()
    /// Raised when the scan or the monitor changes, so a delayed step of an older demand does nothing.
    private var scans = 0
    private var links = 0
    private var beats: Timer?

    /// Climbs from 100 to 187 in 30 seconds and falls back, so a run of half a minute passes
    /// through every zone of the standard maximum of 190.
    static func bpm(afterBeats count: Int) -> Int {
        let step = count % 60
        return step < 30 ? 100 + 3 * step : 190 - 3 * (step - 30)
    }

    func apply(_ demand: HeartRateDemand) {
        let before = self.demand
        self.demand = demand
        if demand.isScanning != before.isScanning {
            scans += 1
            let scan = scans
            if demand.isScanning {
                later(0.3) { source in
                    if source.scans == scan { source.emit(.found(Self.monitor)) }
                }
            }
            if demand.monitor == nil { emit(.link(demand.isScanning ? .searching : .idle)) }
        }
        guard demand.monitor != before.monitor || demand.attempt != before.attempt else { return }
        links += 1
        let link = links
        beats?.invalidate()
        beats = nil
        guard let monitor = demand.monitor else {
            return emit(.link(demand.isScanning ? .searching : .idle))
        }
        emit(.link(.connecting))
        // A monitor this stand-in does not know is never in range, as with a real connect.
        guard monitor == Self.monitor.id else { return }
        later(0.5) { source in
            guard source.links == link else { return }
            source.emit(.link(.connected))
            var count = 0
            source.emit(.beat(bpm: Self.bpm(afterBeats: count)))
            let timer = Timer(timeInterval: 1, repeats: true) { [weak source] _ in
                count += 1
                source?.emit(.beat(bpm: Self.bpm(afterBeats: count)))
            }
            RunLoop.main.add(timer, forMode: .common)
            source.beats = timer
        }
    }

    private func later(_ delay: TimeInterval, _ step: @escaping (StubHeartRateSource) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if let self { step(self) }
        }
    }

    private func emit(_ event: HeartRateEvent) {
        MainActor.assumeIsolated { onEvent?(event) }
    }
}
