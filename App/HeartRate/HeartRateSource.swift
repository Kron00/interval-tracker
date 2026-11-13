import Foundation

/// How the link to the monitor stands. `idle` while nothing asks for the monitor.
enum HeartRateLink: Equatable {
    case idle
    /// Bluetooth is off, or the phone has none.
    case off
    /// The user has not let Intervals use Bluetooth.
    case unauthorized
    /// Looking for monitors nearby, or for the remembered one when iOS no longer knows it.
    case searching
    case connecting
    case connected
    /// The link dropped. The source is connecting again.
    case lost
    /// The monitor would not send its heart rate, which is what a declined pairing looks like.
    /// The source does not try again until it is asked again, so a declined prompt does not come back mid-workout.
    case refused
}

/// A monitor that a scan found.
struct FoundMonitor: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// Signal strength in dBm, as iOS reported it when it first saw the monitor.
    let rssi: Int
}

/// What the app wants from Bluetooth now. The source makes it so and keeps it so, the way
/// `CuePlayer.reconcile` keeps the audio as the run needs it.
struct HeartRateDemand: Equatable {
    var isScanning = false
    /// The monitor to stay connected to.
    var monitor: UUID?
    /// Raised when the user picks a monitor, so one that refused is asked again.
    var attempt = 0

    var needsBluetooth: Bool { isScanning || monitor != nil }
}

enum HeartRateEvent: Equatable {
    case link(HeartRateLink)
    case found(FoundMonitor)
    case beat(bpm: Int)
}

/// Where heart rates come from. CoreBluetooth on a phone, a stand-in in tests.
protocol HeartRateSource: AnyObject {
    /// Called on the main thread, in the order the events happened.
    var onEvent: (@MainActor (HeartRateEvent) -> Void)? { get set }
    /// Returns at once. The work happens away from the main thread.
    func apply(_ demand: HeartRateDemand)
}
