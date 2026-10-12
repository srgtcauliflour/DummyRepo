import SwiftUI
import CoreBluetooth

final class AdvertisingProbe: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published var state = "Initialising…"
    @Published var status = "Not transmitting"
    @Published var transmitting = false
    private var manager: CBPeripheralManager!
    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn: state = "Bluetooth ready"
        case .poweredOff: state = "Bluetooth switched off"
        case .unauthorized: state = "Bluetooth permission denied"
        default: state = "Bluetooth unavailable (\(peripheral.state.rawValue))"
        }
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            transmitting = false
            status = "Advertising failed: \(error.localizedDescription)"
        } else {
            transmitting = true
            status = "Advertising requested successfully. This does NOT confirm reception by the toy."
        }
    }
    func startProbe() {
        guard manager.state == .poweredOn else { status = "Bluetooth not ready"; return }
        manager.stopAdvertising()
        transmitting = false
        status = "Starting AE8F service-only diagnostic advertisement…"
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "AE8F")]
        ])
    }
    func stop() {
        manager.stopAdvertising()
        transmitting = false
        status = "Local advertising stopped. This is not a verified toy STOP command."
    }
}

struct AdvertisingProbeView: View {
    @StateObject private var probe = AdvertisingProbe()
    var body: some View {
        List {
            Section("Bluetooth transmitter") {
                Text(probe.state)
                Text(probe.status).font(.caption).foregroundStyle(.secondary)
                Button("Start AE8F service probe") { probe.startProbe() }
                    .disabled(probe.state != "Bluetooth ready")
                Button("STOP TRANSMITTING") { probe.stop() }
                    .foregroundStyle(.red).fontWeight(.bold)
            }
            Section("Love Spouse B2946") {
                LabeledContent("Binding code", value: "49173118")
                Text("Binding code is a device registration value, not a confirmed BLE address.")
                Text("AE8F is an observed Android advertising service identifier. Sending an AE8F advertisement from iOS does not prove toy compatibility.")
                    .foregroundStyle(.secondary)
            }
            Section("Safety") {
                Text("Diagnostic advertisement only. This screen does not send intensity, movement, or motor-stop instructions. Keep the toy’s physical power control available.")
                    .font(.caption)
            }
        }
        .navigationTitle("Advertising Probe")
    }
}
