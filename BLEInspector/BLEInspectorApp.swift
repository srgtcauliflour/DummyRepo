import SwiftUI

@main
struct BLEInspectorApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ToyLabView()
                    .tabItem { Label("Toy Lab", systemImage: "waveform.path") }
                AdvertisingProbeView()
                    .tabItem { Label("Transmit", systemImage: "antenna.radiowaves.left.and.right") }
            }
        }
    }
}
