import SwiftUI
import RecompSources

/// Everything that isn't the library: connections, platforms, cache tools, notices and the game log.
@MainActor
struct SettingsView: View {
    let library: LibraryModel
    @State private var editing: LibrarySource?
    @State private var showingNotices = false
    @State private var gameLog: [String]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings").font(.title.bold())
                Text("Connections").font(.title2.bold())
                Text("Open a connection to browse it and import one particular file.").foregroundStyle(.secondary)
                ForEach(library.sources) { source in
                    HStack(spacing: 24) {
                        NavigationLink {
                            SourceBrowserView(source: source, library: library)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(source.name, systemImage: source.kind == .smb ? "externaldrive.connected.to.line.below" : "server.rack")
                                Text(source.address).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Edit") { editing = source }
                            .accessibilityLabel("Edit \(source.name)")
                        Button("Remove") { library.remove(source) }
                            .accessibilityLabel("Remove \(source.name)")
                    }
                }
                HStack(spacing: 24) {
                    Button("Add RomM") { editing = LibrarySource(kind: .romm) }
                    Button("Add SMB share") { editing = LibrarySource(kind: .smb) }
                }
                Text("Library").font(.title2.bold())
                HStack(spacing: 24) {
                    NavigationLink("Platforms") {
                        ChoosePlatformsView(library: library, detection: nil, serverName: nil, onContinue: nil)
                    }
                    if !library.importedROMs.isEmpty {
                        Button("Clear ROM cache") { Task { await library.clearCache() } }
                        Button(library.isRefreshingArtwork ? "Refreshing artwork…" : "Refresh artwork") {
                            Task { await library.refreshArtwork(force: true) }
                        }
                        .disabled(library.isRefreshingArtwork || library.isImporting)
                    }
                }
                Text("About").font(.title2.bold())
                HStack(spacing: 24) {
                    Button("Third-party notices") { showingNotices = true }
                    Button("Last game log") { gameLog = GameLogView.load() }
                }
            }
            .padding(48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { CalmBackdrop() }
        .fullScreenCover(isPresented: Binding(get: { gameLog != nil }, set: { if !$0 { gameLog = nil } })) {
            GameLogView(lines: gameLog ?? [])
        }
        .sheet(item: $editing) { source in SourceEditorView(source: source, library: library) }
        .sheet(isPresented: $showingNotices) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button("Done") { showingNotices = false }
                    Text(SourceNotices.license).font(.caption)
                    if let notices = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt", subdirectory: "NativecadeGame"),
                       let text = try? String(contentsOf: notices, encoding: .utf8) {
                        Text(text).font(.caption)
                    }
                }.padding(64)
            }
        }
    }
}
