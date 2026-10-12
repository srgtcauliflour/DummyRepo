import SwiftUI

@main
struct BLEInspectorApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ToyLabView()
                    .tabItem { Label("Toy Lab", systemImage: "waveform.path") }
                ContentView()
                    .tabItem { Label("GATT Inspector", systemImage: "antenna.radiowaves.left.and.right") }
            }
        }
    }
}
