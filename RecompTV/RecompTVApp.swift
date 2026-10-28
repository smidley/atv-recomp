import SwiftUI

@main
struct RecompTVApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
                FoundationView().tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            }
            .preferredColorScheme(.dark)
            #if DEBUG && targetEnvironment(simulator)
            .task { await SourceSimulatorProbe.runIfRequested() }
            #endif
        }
    }
}
