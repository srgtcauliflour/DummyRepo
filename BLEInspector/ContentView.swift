import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var hexByCharacteristic: [String: String] = [:]
    @State private var writeError: String?

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
                    Text("Background BLE enabled. iOS may keep an existing BLE connection and deliver notifications while this app is backgrounded.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Nearby Devices") {
                    ForEach(bluetooth.devices) { device in
                        Button { bluetooth.connect(device.id) } label: {
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

                    if !bluetooth.writableCharacteristics.isEmpty {
                        Section("Writable Characteristics") {
                            Text("Experimental. Only send bytes you intentionally want to test.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(bluetooth.writableCharacteristics) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.characteristicUUID).font(.system(.caption, design: .monospaced)).bold()
                                    Text("Service: \(item.serviceUUID)").font(.caption2)
                                    Text(item.properties).font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        TextField("Hex: 01 FF 03", text: Binding(
                                            get: { hexByCharacteristic[item.id, default: ""] },
                                            set: { hexByCharacteristic[item.id] = $0 }
                                        ))
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                        .font(.system(.caption, design: .monospaced))
                                        Button("Send") {
                                            writeError = bluetooth.sendHex(hexByCharacteristic[item.id, default: ""], to: item.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section("GATT / Capture") {
                        ForEach(bluetooth.log.indices, id: \.self) { i in
                            Text(bluetooth.log[i]).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("BLE Inspector")
            .alert("Write", isPresented: Binding(get: { writeError != nil }, set: { if !$0 { writeError = nil } })) {
                Button("OK") { writeError = nil }
            } message: { Text(writeError ?? "") }
            .sheet(item: $bluetooth.exportItem) { item in ShareSheet(items: [item.url]) }
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
