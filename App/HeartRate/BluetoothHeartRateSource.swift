import CoreBluetooth
import Foundation

/// A client of the Bluetooth SIG's Heart Rate Service, which chest straps, armbands and a Fitbit
/// Air with Share heart rate turned on all offer. The only file in the app that imports CoreBluetooth.
///
/// Every CoreBluetooth call and callback runs on one serial queue, so none blocks the main thread
/// and the state below needs no lock. Events reach the main thread in order.
final class BluetoothHeartRateSource: NSObject, HeartRateSource, @unchecked Sendable {
    var onEvent: (@MainActor (HeartRateEvent) -> Void)?

    private static let service = CBUUID(string: "180D")
    private static let measurement = CBUUID(string: "2A37")
    private static let retryDelay: TimeInterval = 2

    private let queue = DispatchQueue(label: "heart-rate.bluetooth")
    /// Made on the first demand that needs Bluetooth, because making it is what shows the
    /// permission prompt. The app never asks at launch.
    private var central: CBCentralManager?
    private var demand = HeartRateDemand()
    private var peripheral: CBPeripheral?
    /// iOS did not know the remembered monitor by its identifier, so a scan looks for it.
    private var isLookingForMonitor = false
    /// The monitor that refused. It is not asked again until the demand names it anew or makes a new attempt.
    private var refused: UUID?
    private var lastLink: HeartRateLink?

    func apply(_ demand: HeartRateDemand) {
        queue.async { [self] in
            if demand.monitor != self.demand.monitor || demand.attempt != self.demand.attempt { refused = nil }
            self.demand = demand
            if central == nil, demand.needsBluetooth {
                // No alert to turn Bluetooth on: one could appear over a workout as it starts.
                central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            }
            update()
        }
    }

    private func update() {
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            break
        case .unauthorized:
            return emit(.link(demand.needsBluetooth ? .unauthorized : .idle))
        case .poweredOff, .unsupported:
            return emit(.link(demand.needsBluetooth ? .off : .idle))
        default:
            return
        }

        let target = demand.monitor == refused ? nil : demand.monitor
        if let peripheral, peripheral.identifier != target {
            central.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
        }
        if target == nil { isLookingForMonitor = false }
        if let target, peripheral == nil, !isLookingForMonitor {
            if let known = central.retrievePeripherals(withIdentifiers: [target]).first {
                connect(known)
            } else {
                isLookingForMonitor = true
            }
        }

        let wantsScan = demand.isScanning || isLookingForMonitor
        if wantsScan, !central.isScanning {
            central.scanForPeripherals(withServices: [Self.service])
        } else if !wantsScan, central.isScanning {
            central.stopScan()
        }

        if demand.monitor != nil, demand.monitor == refused {
            emit(.link(.refused))
        } else if isLookingForMonitor || (demand.isScanning && peripheral == nil) {
            emit(.link(.searching))
        } else if peripheral == nil {
            emit(.link(.idle))
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        // A connect never times out. iOS keeps it pending until the monitor is in range.
        central?.connect(peripheral)
        emit(.link(.connecting))
    }

    private func refuse(_ peripheral: CBPeripheral) {
        refused = peripheral.identifier
        self.peripheral = nil
        central?.cancelPeripheralConnection(peripheral)
        update()
    }

    private func emit(_ event: HeartRateEvent) {
        if case .link(let link) = event {
            guard link != lastLink else { return }
            lastLink = link
        }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { onEvent?(event) }
        }
    }
}

extension BluetoothHeartRateSource: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            // Connections end when Bluetooth goes off. Connect afresh when it comes back.
            peripheral = nil
            isLookingForMonitor = false
        }
        update()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        if isLookingForMonitor, peripheral.identifier == demand.monitor, peripheral.identifier != refused {
            isLookingForMonitor = false
            connect(peripheral)
            update()
        }
        guard demand.isScanning else { return }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        emit(.found(FoundMonitor(id: peripheral.identifier, name: name ?? "Heart rate monitor", rssi: rssi.intValue)))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == self.peripheral else { return }
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        guard peripheral == self.peripheral else { return }
        emit(.link(.lost))
        queue.asyncAfter(deadline: .now() + Self.retryDelay) { [self] in
            if peripheral == self.peripheral { central.connect(peripheral) }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard peripheral == self.peripheral else { return }
        emit(.link(.lost))
        central.connect(peripheral)
    }
}

extension BluetoothHeartRateSource: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard peripheral == self.peripheral else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            return refuse(peripheral)
        }
        peripheral.discoverCharacteristics([Self.measurement], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard peripheral == self.peripheral else { return }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.measurement }) else {
            return refuse(peripheral)
        }
        // A monitor that needs pairing makes iOS ask the user here.
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard peripheral == self.peripheral, characteristic.uuid == Self.measurement else { return }
        if error != nil || !characteristic.isNotifying {
            refuse(peripheral)
        } else {
            emit(.link(.connected))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard peripheral == self.peripheral, characteristic.uuid == Self.measurement, error == nil,
              let value = characteristic.value, let bpm = HeartRateMeasurement.bpm(from: value) else { return }
        emit(.beat(bpm: bpm))
    }
}
