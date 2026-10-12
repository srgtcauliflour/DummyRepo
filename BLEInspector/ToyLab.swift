import SwiftUI
import CoreBluetooth

struct LabDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var services: String
    var manufacturerHex: String
    var lastSeen: Date
    var samples: Int
}

final class ToyLabBluetooth: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var state = "Starting Bluetooth..."
    @Published var scanning = false
    @Published var devices: [LabDevice] = []
    @Published var connected = "None"
    @Published var timeline: [String] = []
    @Published var captureURL: URL?
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var current: CBPeripheral?
    private var observations: [[String: Any]] = []
    private let iso = ISO8601DateFormatter()
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: state = "Ready to scan"
        case .poweredOff: state = "Bluetooth turned off"
        case .unauthorized: state = "Bluetooth permission denied"
        case .unsupported: state = "BLE unavailable"
        default: state = "Bluetooth not ready"
        }
    }

    func scan() {
        guard central.state == .poweredOn else { note("Bluetooth not ready"); return }
        devices.removeAll()
        observations.removeAll()
        peripherals.removeAll()
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        scanning = true
        note("Scanning for GATT and advertisement-based toys")
    }
    func stopScan() {
        central.stopScan()
        scanning = false
        note("Scan stopped")
    }
    func connect(_ id: UUID) {
        guard let peripheral = peripherals[id] else { return }
        stopScan()
        central.connect(peripheral)
        note("Connecting to \(peripheral.name ?? id.uuidString)")
    }
    func emergencyLocalStop() {
        // No manufacturer-specific STOP packets are sent until protocol/profile is verified.
        central.stopScan()
        scanning = false
        if let current { central.cancelPeripheralConnection(current) }
        note("LOCAL STOP: scan and local connection ended. Physical toy STOP not yet verified.")
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "Unnamed peripheral"
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString).joined(separator: ",")
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data())
            .map { String(format: "%02X", $0) }.joined()
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[i].rssi = RSSI.intValue
            devices[i].lastSeen = Date()
            devices[i].samples += 1
            if !uuids.isEmpty { devices[i].services = uuids }
            if !manufacturer.isEmpty { devices[i].manufacturerHex = manufacturer }
        } else {
            devices.append(LabDevice(id: peripheral.identifier, name: name,
                                     rssi: RSSI.intValue, services: uuids,
                                     manufacturerHex: manufacturer, lastSeen: Date(), samples: 1))
            note("Found \(name), RSSI \(RSSI)")
        }
        if observations.count < 3000 {
            observations.append([
                "time": iso.string(from: Date()), "id": peripheral.identifier.uuidString,
                "name": name, "rssi": RSSI.intValue, "services": uuids,
                "manufacturer": manufacturer
            ])
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        current = peripheral
        connected = peripheral.name ?? peripheral.identifier.uuidString
        peripheral.delegate = self
        note("Connected \(connected); discovering GATT services")
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        note("Connection failed: \(error?.localizedDescription ?? "unknown")")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = "None"
        current = nil
        note("Disconnected \(peripheral.name ?? "")")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { note("Service error: \(error.localizedDescription)"); return }
        for s in peripheral.services ?? [] {
            note("GATT service: \(s.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
        if peripheral.services?.isEmpty == true {
            note("No GATT services returned; device might use advertising-only control")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { note("Characteristic error: \(error.localizedDescription)"); return }
        for characteristic in service.characteristics ?? [] {
            note("Characteristic: \(service.uuid.uuidString)/\(characteristic.uuid.uuidString), properties=\(characteristic.properties.rawValue)")
            if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { note("Read failed: \(error!.localizedDescription)"); return }
        let value = (characteristic.value ?? Data()).map { String(format: "%02X", $0) }.joined()
        note("Read \(characteristic.uuid.uuidString): \(value)")
    }
    func export() -> URL? {
        let object: [String: Any] = [
            "created": iso.string(from: Date()), "observations": observations,
            "diagnostics": timeline, "note": "Device identifiers are local to this iPhone; redact before sharing publicly."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ToyLab-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url)
        return url
    }
    private func note(_ line: String) {
        timeline.append("\(iso.string(from: Date()))  \(line)")
        if timeline.count > 300 { timeline.removeFirst(timeline.count - 300) }
    }
}

struct ToyLabView: View {
    @StateObject private var ble = ToyLabBluetooth()
    @State private var exported: ExportItem?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(ble.state)
                    HStack {
                        Button(ble.scanning ? "End scan" : "Scan toys") {
                            if ble.scanning { ble.stopScan() } else { ble.scan() }
                        }
                        Spacer()
                        Button("Export results") {
                            if let url = ble.export() { exported = ExportItem(url: url) }
                        }
                    }
                    Text("Connected: \(ble.connected)").font(.caption)
                } header: { Text("Bluetooth") }
                Section {
                    Button(action: { ble.emergencyLocalStop() }) {
                        Text("STOP LOCAL TEST").bold().frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                    Text("This stops scanning and disconnects locally. It cannot guarantee the physical toy stops until its STOP command is verified.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Safety") }
                Section("Detected devices (\(ble.devices.count))") {
                    ForEach(ble.devices.sorted { $0.rssi > $1.rssi }) { device in
                        Button { ble.connect(device.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).font(.headline)
                                Text("RSSI \(device.rssi) dBm • \(device.samples) advertisements")
                                Text("UUIDs: \(device.services.isEmpty ? "none" : device.services)")
                                Text("Manufacturer: \(device.manufacturerHex.isEmpty ? "none" : device.manufacturerHex)")
                                Text(device.id.uuidString).font(.caption2)
                            }
                            .font(.caption).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Section("Diagnostics") {
                    ForEach(Array(ble.timeline.suffix(60).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Toy Lab")
            .sheet(item: $exported) { item in ShareSheet(items: [item.url]) }
        }
    }
}
