import Foundation
import CoreBluetooth
import UIKit

struct BLEDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
}

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

final class BluetoothManager: NSObject, ObservableObject {
    @Published var devices: [BLEDevice] = []
    @Published var stateText = "Starting…"
    @Published var isScanning = false
    @Published var connectedName: String?
    @Published var isRecording = false
    @Published var log: [String] = []
    @Published var exportItem: ExportItem?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var events: [[String: Any]] = []
    private var recordingStart: Date?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        devices.removeAll()
        peripherals.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        append("Scanning…")
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        stopScan()
        central.connect(p)
        append("Connecting to \(p.name ?? id.uuidString)…")
    }

    func startRecording() {
        events.removeAll()
        recordingStart = Date()
        isRecording = true
        append("Recording started")
    }

    func stopRecording() {
        isRecording = false
        append("Recording stopped")
    }

    func exportCapture() {
        var root: [String: Any] = [
            "created": ISO8601DateFormatter().string(from: Date()),
            "events": events
        ]
        if let p = connected {
            root["device"] = ["name": p.name ?? "Unknown", "identifier": p.identifier.uuidString]
        }
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BLE-Capture-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url)
        exportItem = ExportItem(url: url)
    }

    private func append(_ text: String) {
        log.append(text)
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
    }

    private func record(type: String, service: CBUUID? = nil, characteristic: CBUUID? = nil, data: Data? = nil, extra: [String: Any] = [:]) {
        guard isRecording else { return }
        var e: [String: Any] = [
            "type": type,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let start = recordingStart { e["elapsed"] = Date().timeIntervalSince(start) }
        if let service { e["service"] = service.uuidString }
        if let characteristic { e["characteristic"] = characteristic.uuidString }
        if let data { e["hex"] = data.map { String(format: "%02X", $0) }.joined() }
        extra.forEach { e[$0.key] = $0.value }
        events.append(e)
    }

    private func properties(_ p: CBCharacteristicProperties) -> [String] {
        var a: [String] = []
        if p.contains(.read) { a.append("read") }
        if p.contains(.write) { a.append("write") }
        if p.contains(.writeWithoutResponse) { a.append("writeWithoutResponse") }
        if p.contains(.notify) { a.append("notify") }
        if p.contains(.indicate) { a.append("indicate") }
        if p.contains(.broadcast) { a.append("broadcast") }
        if p.contains(.authenticatedSignedWrites) { a.append("authenticatedSignedWrites") }
        if p.contains(.extendedProperties) { a.append("extendedProperties") }
        return a
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: stateText = "Bluetooth On"
        case .poweredOff: stateText = "Bluetooth Off"
        case .unauthorized: stateText = "Bluetooth Unauthorized"
        case .unsupported: stateText = "Bluetooth Unsupported"
        case .resetting: stateText = "Bluetooth Resetting"
        default: stateText = "Bluetooth Unknown"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        let d = BLEDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d } else { devices.append(d) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected = peripheral
        connectedName = peripheral.name ?? "Unknown"
        peripheral.delegate = self
        append("Connected: \(connectedName ?? "")")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        append("Connect failed: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        append("Disconnected")
        connected = nil
        connectedName = nil
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { append("Service discovery error: \(error.localizedDescription)"); return }
        for service in peripheral.services ?? [] {
            append("Service \(service.uuid.uuidString)")
            record(type: "service", service: service.uuid)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { append("Characteristic discovery error: \(error.localizedDescription)"); return }
        for c in service.characteristics ?? [] {
            let props = properties(c.properties)
            append("  Char \(c.uuid.uuidString) [\(props.joined(separator: ","))]")
            record(type: "characteristic", service: service.uuid, characteristic: c.uuid, extra: ["properties": props])
            peripheral.discoverDescriptors(for: c)
            if c.properties.contains(.read) { peripheral.readValue(for: c) }
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { append("Value error \(characteristic.uuid): \(error!.localizedDescription)"); return }
        let data = characteristic.value ?? Data()
        let hex = data.map { String(format: "%02X", $0) }.joined()
        append("← \(characteristic.uuid.uuidString): \(hex)")
        record(type: "value", service: characteristic.service?.uuid, characteristic: characteristic.uuid, data: data)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        for d in characteristic.descriptors ?? [] {
            append("    Descriptor \(d.uuid.uuidString)")
            record(type: "descriptor", service: characteristic.service?.uuid, characteristic: characteristic.uuid,
                   extra: ["descriptor": d.uuid.uuidString])
            peripheral.readValue(for: d)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        append("    Descriptor value \(descriptor.uuid.uuidString): \(String(describing: descriptor.value))")
    }
}
