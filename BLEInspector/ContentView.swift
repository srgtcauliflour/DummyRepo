import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    HStack {
                        Text(bluetooth.stateText)
                        Spacer()
                        Button(bluetooth.isScanning ? "Stop Scan" : "Scan") {
                            bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                        }
                    }
                }

                Section("Nearby Devices") {
                    ForEach(bluetooth.devices) { device in
                        Button {
                            bluetooth.connect(device.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).font(.headline)
                                Text(device.id.uuidString).font(.caption).foregroundStyle(.secondary)
                                Text("RSSI: \(device.rssi)").font(.caption)
                            }
                        }
                    }
                }

                if bluetooth.connectedName != nil {
                    Section("Connected") {
                        Text(bluetooth.connectedName ?? "")
                        Button(bluetooth.isRecording ? "Stop Recording" : "Record") {
                            bluetooth.isRecording ? bluetooth.stopRecording() : bluetooth.startRecording()
                        }
                        Button("Export JSON") { bluetooth.exportCapture() }
                    }

                    Section("GATT / Capture") {
                        ForEach(bluetooth.log.indices, id: \.self) { i in
                            Text(bluetooth.log[i]).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("BLE Inspector")
            .sheet(item: $bluetooth.exportItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
