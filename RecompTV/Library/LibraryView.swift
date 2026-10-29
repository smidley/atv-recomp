import SwiftUI
import RecompSources
import UIKit

@MainActor
struct LibraryView: View {
    @State private var library = LibraryModel()
    @State private var editing: LibrarySource?
    @State private var showingNotices = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Nativecade").font(.largeTitle.bold())
                    Text("Connect a server and import Ocarina of Time for Shipwright.")
                        .foregroundStyle(.secondary)
                    if !library.importedROMs.isEmpty {
                        Text(library.importedROMs.count == 1 ? "1 verified ROM saved locally" : "\(library.importedROMs.count) verified ROMs saved locally").font(.headline)
                    }
                    HStack(spacing: 24) {
                        Button("Add SMB share") { editing = LibrarySource(kind: .smb) }
                        Button("Add RomM") { editing = LibrarySource(kind: .romm) }
                        if !library.importedROMs.isEmpty {
                            Button("Clear ROM cache") { Task { await library.clearCache() } }
                            Button(library.isRefreshingArtwork ? "Refreshing artwork…" : "Refresh artwork") {
                                Task { await library.refreshArtwork(force: true) }
                            }
                            .disabled(library.isRefreshingArtwork || library.isImporting)
                        }
                    }
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
                    Text(GameRuntime.available ? "Connect a game controller, choose a game, and press Play. Your first launch prepares the game on this Apple TV." : "Use the Nativecade scheme to build the playable app.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(library.importedROMs) { rom in
                        VStack(alignment: .leading, spacing: 16) {
                            ROMResultView(rom: rom, library: library)
                            if GameRuntime.available {
                                Button("Play") { Task { await library.play(rom) } }
                                    .accessibilityLabel("Play \(rom.name)")
                                    .disabled(library.isImporting)
                            }
                        }
                    }
                    Button("Third-party notices") { showingNotices = true }
                }
                .padding(48)
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
            .task {
                await library.restoreCache()
                #if DEBUG && targetEnvironment(simulator) && NATIVECADE_RUNTIME
                // Explicit local smoke test. Uses only an already verified cache;
                // no game bytes, server addresses, or credentials enter the build.
                if ProcessInfo.processInfo.arguments.contains("--nativecade-play-cached-rom"),
                   let rom = library.importedROMs.first {
                    await library.play(rom)
                    if let error = library.error { print("Nativecade launch probe failed: \(error)") }
                }
                #endif
                await library.refreshArtwork()
            }
            .alert("Library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("OK") { library.error = nil }
            } message: { Text(library.error ?? "") }
        }
        .disabled(library.isPreparingGame)
        .overlay {
            if library.isPreparingGame {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 24) {
                        ProgressView()
                        Text("Preparing your game").font(.title)
                        Text(library.preparingTitle).font(.headline)
                        Text("The first launch can take a few minutes. Keep Nativecade open.")
                            .foregroundStyle(.secondary)
                    }.padding(64)
                }
            }
        }
    }
}

@MainActor
private struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: LibrarySource
    @State private var secret = ""
    @State private var connecting = false
    @State private var error: String?
    @State private var connection: Task<Void, Never>?
    @State private var loadedCredential = false
    let library: LibraryModel

    // A sheet owns a single editing draft; changes are committed only after successful access.
    init(source: LibrarySource, library: LibraryModel) {
        _source = State(initialValue: source); self.library = library
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Connect \(source.kind.title)").font(.title.bold())
                TextField("Connection name", text: $source.name)
                TextField(source.kind == .smb ? "smb://server/share/folder" : "https://romm.example.com", text: $source.address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if source.kind == .smb {
                    TextField("Username (empty for guest)", text: $source.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $secret)
                    TextField("Domain (optional)", text: $source.domain)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Require SMB3 encryption", isOn: $source.requireSMBEncryption)
                    Text("Use an account with read access. Include the share name in the address; folders are optional.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    SecureField("Client API token", text: $secret)
                    Toggle("Allow HTTP for this server", isOn: $source.allowHTTP)
                    Text("In RomM, create a Client API token with roms.read permission. HTTP sends the token without encryption; use it only on a trusted network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.orange).font(.callout) }
                HStack(spacing: 24) {
                    Button(connecting ? "Connecting…" : "Connect and save") { connect() }
                        .disabled(connecting || !loadedCredential)
                    Button("Cancel") { connection?.cancel(); dismiss() }
                }
                if connecting { ProgressView() }
            }
            .padding(64)
            .frame(maxWidth: 1400)
        }
        .task {
            do { secret = try CredentialStore.load(source.id); loadedCredential = true }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { connection?.cancel(); secret = "" }
    }

    private func connect() {
        connection?.cancel(); error = nil; connecting = true
        let draft = source; let credential = secret
        connection = Task {
            defer { connecting = false }
            do {
                let provider = try ProviderFactory.make(source: draft, secret: credential)
                _ = try await provider.list(.root, search: "", offset: 0)
                try Task.checkCancellation()
                var saved = draft
                saved.address = saved.address.trimmingCharacters(in: .whitespacesAndNewlines)
                if saved.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { saved.name = saved.kind.title }
                try library.save(saved, secret: credential)
                dismiss()
            } catch { if !Task.isCancelled { self.error = userFacingNetworkError(error) } }
        }
    }
}

@MainActor
private struct SourceBrowserView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser: SourceBrowserModel
    @State private var showingBatchResults = false
    let library: LibraryModel

    init(source: LibrarySource, library: LibraryModel, location: LibraryLocation = .root) {
        _browser = State(initialValue: SourceBrowserModel(source: source, location: location)); self.library = library
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text(browser.title).font(.title.bold())
                if let artwork = browser.artwork {
                    GameScreenshotGallery(artwork: artwork, source: browser.source, library: library)
                }
                if browser.isPlatformList {
                    Text("Choose a platform").font(.headline).foregroundStyle(.secondary)
                } else if browser.source.kind == .smb && browser.history.isEmpty {
                    Text("Open a platform folder, or import all ROMs from this folder.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    if !browser.history.isEmpty { Button("Up one level") { browser.back() } }
                    TextField(browser.searchPrompt, text: $browser.search)
                        .onSubmit { browser.refresh() }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Search") { browser.refresh() }
                    Button("Refresh") { browser.refresh() }
                }
                .disabled(library.isImporting)
                if let location = browser.batchLocation {
                    HStack(spacing: 24) {
                        Button("Verify and import all ROMs") {
                            library.acquireAll(in: location, title: browser.title, source: browser.source)
                        }
                        .disabled(library.isImporting || browser.loading)
                        Text("Includes every page and subfolder, even when search is active.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Supported Ocarina of Time revisions are saved. Other games and compressed files appear in the results.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if library.isImporting {
                    HStack(spacing: 24) {
                        ProgressView(value: library.importFraction)
                            .frame(width: 300)
                        Text(library.importStatus).font(.callout)
                        Button("Cancel import") { library.cancelImport() }
                    }
                } else if !library.importStatus.isEmpty {
                    Text(library.importStatus).font(.callout)
                }
                if let report = library.batchReport {
                    HStack(spacing: 24) {
                        Text("\(report.results.count) of \(report.total) items processed").font(.callout)
                        Button("View import results") { showingBatchResults = true }
                    }
                    if let failure = report.failure { Text(failure).foregroundStyle(.orange) }
                } else if !browser.isPlatformList, !library.importStatus.isEmpty, let imported = library.imported {
                    ROMResultView(rom: imported, library: library)
                }
                if browser.loading { ProgressView("Loading library…") }
                if browser.isGameList {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 430), spacing: 32)],
                              alignment: .leading, spacing: 36) {
                        ForEach(browser.entries) { entry in
                            Button { browser.open(entry) } label: {
                                VStack(alignment: .leading, spacing: 16) {
                                    GameArtworkView(path: entry.artwork?.cover, artwork: entry.artwork,
                                        sourceID: browser.source.id, source: browser.source, library: library,
                                        width: 290, height: 220)
                                    Text(entry.name).font(.headline).lineLimit(2)
                                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                        .frame(width: 290, height: 88, alignment: .topLeading)
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.card)
                            .accessibilityLabel("\(entry.name), browse ROM files")
                            .disabled(library.isImporting || browser.loading)
                        }
                    }
                } else { ForEach(browser.entries) { entry in
                    Button {
                        if entry.folder != nil { browser.open(entry) }
                        else { library.acquire(entry, source: browser.source) }
                    } label: {
                        HStack(spacing: 20) {
                            if let artwork = entry.artwork {
                                GameArtworkView(path: artwork.cover, artwork: artwork,
                                    sourceID: browser.source.id, source: browser.source, library: library, width: 120, height: 110)
                            } else { Image(systemName: entry.folder != nil ? "folder" : "doc") }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.name)
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let size = entry.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption) }
                            Text(entry.folder != nil ? "Browse" : "Import and verify").font(.callout)
                        }
                    }
                    .disabled(library.isImporting || browser.loading || (entry.folder == nil && !entry.isROM))
                } }
                if browser.entries.isEmpty && !browser.loading {
                    Text(browser.isPlatformList ? "No matching platforms." : "No matching ROMs in this platform or folder.")
                        .foregroundStyle(.secondary)
                }
                if browser.nextOffset != nil {
                    Button("Load more") { browser.refresh(more: true) }.disabled(browser.loading || library.isImporting)
                }
            }
            .padding(48)
        }
        .sheet(isPresented: $showingBatchResults) {
            BatchResultsView(library: library)
        }
        .onAppear { if !library.isImporting { browser.refresh() } }
        .onDisappear {
            if !showingBatchResults { browser.cancel(); if library.isImporting { library.cancelImport() } }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { browser.cancel(); if library.isImporting { library.cancelImport() } }
        }
        .alert("Connection", isPresented: Binding(get: { browser.error != nil || library.error != nil }, set: {
            if !$0 { browser.error = nil; library.error = nil }
        })) {
            Button("OK") { browser.error = nil; library.error = nil }
        } message: { Text(browser.error ?? library.error ?? "") }
    }
}

@MainActor
private struct BatchResultsView: View {
    @Environment(\.dismiss) private var dismiss
    let library: LibraryModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Button("Done") { dismiss() }
                Text(library.batchTitle).font(.title.bold())
                if let report = library.batchReport {
                    Text(library.isImporting ? library.importStatus : report.summary).font(.headline)
                    if report.cancelled { Text("Completed imports were kept. Run the batch again to check the remaining files.") }
                    if let failure = report.failure { Text(failure).foregroundStyle(.orange) }
                    if report.results.isEmpty { Text(library.isImporting ? "Scanning for ROM files…" : "No files were processed.") }
                    ForEach(report.results) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(result.name, systemImage: result.outcome == .imported ? "checkmark.seal" : "info.circle")
                                .font(.headline)
                            Text("\(result.outcome.rawValue.capitalized) · \(result.message)").font(.callout)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        .focusable()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(64)
        }
        .frame(minWidth: 1100, idealWidth: 1400, minHeight: 650, idealHeight: 850)
    }
}

private struct ROMResultView: View {
    let rom: ImportedROM
    let library: LibraryModel
    var body: some View {
        HStack(spacing: 28) {
            GameArtworkView(path: rom.artwork?.cover, artwork: rom.artwork,
                sourceID: rom.sourceID, library: library, width: 220, height: 180)
        VStack(alignment: .leading, spacing: 10) {
            Label(rom.recognized ? "Ocarina of Time ROM verified" : "ROM revision not supported",
                  systemImage: rom.recognized ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.headline)
            Text(rom.artwork?.title ?? rom.name).font(.callout)
            if rom.artwork != nil { Text(rom.name).font(.caption).foregroundStyle(.secondary) }
            if let revision = rom.revision {
                Text(revision)
            } else { Text("These bytes do not match Shipwright's accepted ROM revisions. The file was not cached.") }
            Text("SHA-1: \(rom.sha1)").font(.caption.monospaced())
        }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

@MainActor
private struct GameArtworkView: View {
    let path: String?
    let artwork: RomMArtwork?
    let sourceID: UUID
    var source: LibrarySource? = nil
    let library: LibraryModel
    let width: CGFloat
    let height: CGFloat
    @State private var image: UIImage?
    @State private var loading = false

    private struct Request: Hashable {
        let path: String?
        let artwork: RomMArtwork?
        let sourceID: UUID
        let refresh: UUID
    }

    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "gamecontroller").font(.title)
                    Text(loading ? "Loading artwork…" : "No artwork").font(.caption2)
                }.foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
        .task(id: Request(path: path, artwork: artwork, sourceID: sourceID, refresh: library.artworkRefreshID)) {
            image = nil
            loading = true
            defer { loading = false }
            guard let path, let artwork,
                  let bytes = await library.artworkData(at: path, artwork: artwork, sourceID: sourceID, sourceOverride: source),
                  !Task.isCancelled else { return }
            image = UIImage(data: bytes)
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit visual fixture: a fixed loopback server and a public test credential.
/// It never changes saved sources, imports a ROM, or accepts secrets in launch arguments.
struct ArtworkFixturePreview: View {
    @State private var library = LibraryModel()
    @State private var ready = false
    private let source = LibrarySource(id: UUID(uuidString: "B36968FC-8A85-4B71-BD10-3F00A950A865") ?? UUID(),
        name: "Artwork fixture · Nintendo 64", kind: .romm, address: "http://127.0.0.1:18080", allowHTTP: true)
    var body: some View {
        Group {
            if ready {
                SourceBrowserView(source: source, library: library,
                    location: ProcessInfo.processInfo.arguments.contains("--artwork-fixture-detail") ? .rom(3) : .platform(1))
            }
            else { ProgressView("Loading artwork fixture…") }
        }
        .task {
            do { try CredentialStore.save("fixture-token", for: source.id); ready = true }
            catch { ready = false }
        }
        .onDisappear { try? CredentialStore.remove(source.id) }
    }
}
#endif

@MainActor
private struct GameScreenshotGallery: View {
    let artwork: RomMArtwork
    let source: LibrarySource
    let library: LibraryModel
    @State private var selected: Screenshot?
    private struct Screenshot: Identifiable { let id: String }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            GameArtworkView(path: artwork.coverLarge ?? artwork.cover, artwork: artwork,
                sourceID: source.id, source: source, library: library, width: 260, height: 240)
            if !artwork.screenshots.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Screenshots").font(.headline)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 28) {
                            ForEach(artwork.screenshots, id: \.self) { path in
                                Button { selected = Screenshot(id: path) } label: {
                                    GameArtworkView(path: path, artwork: artwork, sourceID: source.id,
                                        source: source, library: library, width: 340, height: 190)
                                }
                                .buttonStyle(.card)
                                .accessibilityLabel("View screenshot of \(artwork.title)")
                            }
                        }.padding(12)
                    }
                }
            }
        }
        .sheet(item: $selected) { screenshot in
            VStack(spacing: 28) {
                Button("Done") { selected = nil }
                GameArtworkView(path: screenshot.id, artwork: artwork, sourceID: source.id,
                    source: source, library: library, width: 1200, height: 650)
            }.padding(48)
        }
    }
}
