import SwiftUI

#if !NATIVECADE_RUNTIME
@main
struct RecompTVApp: App {
    var body: some Scene {
        WindowGroup { RecompTVRootView() }
    }
}
#endif

struct RecompTVRootView: View {
    @State private var selectedTab = 0
    var body: some View {
        Group {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--artwork-fixture-preview") {
                ArtworkFixturePreview()
            } else { tabs }
            #else
            tabs
            #endif
        }
        .preferredColorScheme(.dark)
        #if DEBUG && targetEnvironment(simulator)
        .task {
            await SourceSimulatorProbe.runIfRequested()
            await MarioKartSimulatorImport.runIfRequested()
        }
        #endif
    }
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }.tag(0)
            #if DEBUG
            FoundationView().tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }.tag(1)
            #endif
        }
    }
}
