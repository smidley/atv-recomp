import SwiftUI
import RecompSources
import UIKit

/// The library's root: a neutral loading screen until the ROM cache is restored, guided setup
/// on first launch, then the home. An existing library goes straight to the home.
@MainActor
struct LibraryView: View {
    @State private var library = LibraryModel()

    var body: some View {
        Group {
            if !library.restored {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background { CalmBackdrop() }
            } else if !library.setup.complete {
                SetupFlowView(library: library)
            } else {
                LibraryHomeView(library: library)
            }
        }
        .task {
            await library.restoreCache()
            #if DEBUG && targetEnvironment(simulator) && NATIVECADE_RUNTIME
            // Explicit local smoke tests. They use only an already verified cache;
            // no game bytes, server addresses, or credentials enter the build.
            if let game = SimulatorLaunchProbe.next(),
               let rom = library.importedROMs.first(where: { $0.game == game }) {
                await library.play(rom)
                if let error = library.error { print("Nativecade launch probe failed: \(error)") }
            }
            #endif
            await library.refreshArtwork()
        }
        .alert("Library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
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

/// Favorites in Cover Flow, then a shelf for each turned-on platform: its card, which opens the
/// platform's page, and its games. Search and Settings sit in the header.
@MainActor
struct LibraryHomeView: View {
    let library: LibraryModel
    @State private var favorite = 0

    var body: some View {
        let shelf = library.shelf
        let favorites = library.importedROMs.filter { library.favorites.contains($0.id) }
        let platforms = SupportedPlatform.allCases.filter(library.setup.platforms.contains)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 24) {
                        Text("Nativecade").font(.largeTitle.bold())
                        Spacer()
                        if !library.importedROMs.isEmpty {
                            NavigationLink { GameSearchView(library: library) } label: {
                                Label("Search", systemImage: "magnifyingglass")
                            }
                        }
                        NavigationLink { SettingsView(library: library) } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    if !favorites.isEmpty {
                        Text("Favorites").font(.title2.bold())
                        CoverFlow(roms: favorites, selected: $favorite, library: library, cover: CGSize(width: 400, height: 290))
                    }
                    if platforms.isEmpty {
                        Text("Turn on a platform in Settings.").foregroundStyle(.secondary)
                    }
                    ForEach(platforms) { platform in
                        let games = shelf.games[platform] ?? []
                        Text(platform.title).font(.title2.bold())
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 32) {
                                PlatformCard(platform: platform, count: games.count, library: library)
                                ForEach(games) { GameTile(rom: $0, library: library) }
                            }.padding(12)
                        }.scrollClipDisabled()
                    }
                    Text(GameRuntime.available ? "Connect a game controller, open a platform, choose a game, and press Play. Your first launch prepares the game on this Apple TV." : "Use the Nativecade scheme to build the playable app.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(48)
            }
            .background {
                if let rom = favorites[safe: favorite] { CoverBackdrop(rom: rom, library: library) } else { CalmBackdrop() }
            }
        }
    }
}

/// The first card on a platform's shelf, the size of a game's tile. It opens the platform's page.
@MainActor
private struct PlatformCard: View {
    let platform: SupportedPlatform
    let count: Int
    let library: LibraryModel

    var body: some View {
        let games = count == 0 ? "Scan for games" : count == 1 ? "1 game" : "\(count) games"
        NavigationLink { PlatformView(platform: platform, library: library) } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: platform.cardColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(platform.title).font(.title3.bold()).shadow(color: .black.opacity(0.5), radius: 6).padding(20)
                }
                .frame(width: 290, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(games).font(.headline).lineLimit(1).frame(width: 290, alignment: .leading)
            }
            .padding(20)
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(platform.title), \(games)")
    }
}

@MainActor
struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: LibrarySource
    @State private var secret = ""
    @State private var connecting = false
    @State private var error: String?
    @State private var connection: Task<Void, Never>?
    @State private var loadedCredential = false
    let library: LibraryModel
    /// Guided setup's Connect step: no name field or Cancel, just what setup needs.
    let setup: Bool
    let onSaved: ((LibrarySource) -> Void)?

    // A sheet owns a single editing draft; changes are committed only after successful access.
    init(source: LibrarySource, library: LibraryModel, setup: Bool = false, onSaved: ((LibrarySource) -> Void)? = nil) {
        _source = State(initialValue: source); self.library = library; self.setup = setup; self.onSaved = onSaved
    }

    var body: some View {
        // Plain HTTP stays an explicit choice for each connection; setup offers it once the address asks for it.
        let http = source.address.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://")
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !setup {
                    Text("Connect \(source.kind.title)").font(.title.bold())
                    TextField("Connection name", text: $source.name)
                }
                TextField(source.kind == .smb ? "smb://server/share/folder"
                          : setup ? "Server, such as https://romm.example.com" : "https://romm.example.com", text: $source.address)
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
                    SecureField(setup ? "RomM API token" : "Client API token", text: $secret)
                    if !setup || http { Toggle("Allow HTTP for this server", isOn: $source.allowHTTP) }
                    Text((setup ? "Give the token the roms.read and platforms.read permissions."
                          : "In RomM, create a Client API token with roms.read and platforms.read permissions.")
                         + (!setup || http ? " HTTP sends the token without encryption; use it only on a trusted network." : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.orange).font(.callout) }
                HStack(spacing: 24) {
                    Button(connecting ? "Connecting…" : setup ? "Connect" : "Connect and save") { connect() }
                        .disabled(connecting || !loadedCredential)
                    if !setup { Button("Cancel") { connection?.cancel(); dismiss() } }
                }
                if connecting { ProgressView() }
            }
            .padding(setup ? 0 : 64)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: setup ? .leading : .center)
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
                if saved.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    saved.name = setup ? saved.serverName : saved.kind.title
                }
                try library.save(saved, secret: credential)
                if let onSaved { onSaved(saved) } else { dismiss() }
            } catch { if !Task.isCancelled { self.error = userFacingNetworkError(error) } }
        }
    }
}

@MainActor
struct SourceBrowserView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser: SourceBrowserModel
    @State private var showingBatchResults = false
    let library: LibraryModel

    init(source: LibrarySource, library: LibraryModel, location: LibraryLocation = .root, title: String? = nil) {
        _browser = State(initialValue: SourceBrowserModel(source: source, location: location, title: title))
        self.library = library
    }

    private func browse(_ entry: LibraryEntry, in folder: LibraryLocation) -> some View {
        SourceBrowserView(source: browser.source, library: library, location: folder, title: entry.name)
    }

    private func row(_ entry: LibraryEntry) -> some View {
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text(browser.title).font(.title.bold())
                if let artwork = browser.artwork {
                    if GameRuntime.available {
                        // A RomM game that is already imported can start from its own page.
                        ForEach(library.importedROMs.filter { $0.artwork?.romID == artwork.romID && $0.artwork?.server == artwork.server }) { rom in
                            Button { Task { await library.play(rom) } } label: {
                                Label("Play \(rom.revision ?? rom.title)", systemImage: "play.fill")
                            }
                            .disabled(library.isImporting)
                        }
                    }
                    GameScreenshotGallery(artwork: artwork, sourceID: browser.source.id, source: browser.source, library: library)
                }
                if browser.isPlatformList {
                    Text("Choose a platform").font(.headline).foregroundStyle(.secondary)
                } else if browser.source.kind == .smb && browser.location == .root {
                    Text("Open a platform folder, or import all ROMs from this folder.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
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
                    Text("Supported Ocarina of Time, Mario Kart 64 (USA), Star Fox 64 (USA), Super Mario 64 (USA), Banjo-Kazooie, Shadows of the Empire (USA Rev 2), Episode I: Racer (USA), Super Smash Bros. (USA), Cruis'n USA (USA Rev 2) and Cruis'n World (USA) ROMs are saved. Other games and compressed files appear in the results.")
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
                        ForEach(browser.entries) { entry in if let folder = entry.folder {
                            NavigationLink { browse(entry, in: folder) } label: {
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
                            .disabled(library.isImporting)
                        } }
                    }
                } else { ForEach(browser.entries) { entry in
                    if let folder = entry.folder {
                        NavigationLink { browse(entry, in: folder) } label: { row(entry) }
                            .disabled(library.isImporting)
                    } else {
                        Button { library.acquire(entry, source: browser.source) } label: { row(entry) }
                            .disabled(library.isImporting || browser.loading || !entry.isROM)
                    }
                } }
                if browser.entries.isEmpty && !browser.loading {
                    Text(browser.source.kind == .romm ? "No Ocarina of Time, Mario Kart 64, Star Fox 64, Super Mario 64, Banjo-Kazooie, Shadows of the Empire, Episode I: Racer, Super Smash Bros., Cruis'n USA or Cruis'n World ROMs found here."
                         : "No matching ROMs in this folder.")
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
        // Returning from a folder keeps this screen's list, scroll position and focus.
        .onAppear { if !library.isImporting && browser.entries.isEmpty { browser.refresh() } }
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
struct BatchResultsView: View {
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
            Label(rom.recognized ? "\(rom.game?.title ?? "Game") ROM verified" : "ROM revision not supported",
                  systemImage: rom.recognized ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.headline)
            Text(rom.artwork?.title ?? rom.name).font(.callout)
            if rom.artwork != nil { Text(rom.name).font(.caption).foregroundStyle(.secondary) }
            if let revision = rom.revision {
                Text(revision)
            } else { Text("These bytes do not match a supported game revision. The file was not cached.") }
            Text("SHA-1: \(rom.sha1)").font(.caption.monospaced())
        }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

@MainActor
private struct PlatformView: View {
    let platform: SupportedPlatform
    let library: LibraryModel
    @State private var selected = 0

    var body: some View {
        let roms = library.shelf.games[platform] ?? []
        VStack(alignment: .leading, spacing: 40) {
            Text(platform.title).font(.title.bold())
            if roms.isEmpty { Text("No games yet.").foregroundStyle(.secondary) }
            else { CoverFlow(roms: roms, selected: $selected, library: library) }
            Spacer(minLength: 0)
            // Below the Cover Flow, so the covers keep the screen's first focus.
            NavigationLink("Scan for games") { PlatformScanView(platform: platform, library: library, mode: .library) }
                .disabled(library.isImporting)
            SupportRibbon()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if let rom = roms[safe: selected] { CoverBackdrop(rom: rom, library: library) } else { CalmBackdrop() }
        }
    }
}

/// A game's cover, blurred, tinting the whole screen.
@MainActor
struct CoverBackdrop: View {
    let artwork: RomMArtwork?
    let sourceID: UUID
    let title: String
    let library: LibraryModel

    init(artwork: RomMArtwork?, sourceID: UUID, title: String, library: LibraryModel) {
        self.artwork = artwork; self.sourceID = sourceID; self.title = title; self.library = library
    }

    init(rom: ImportedROM, library: LibraryModel) {
        self.init(artwork: rom.artwork, sourceID: rom.sourceID, title: rom.title, library: library)
    }

    var body: some View {
        GameArtworkView(path: artwork?.coverLarge ?? artwork?.cover, artwork: artwork,
            sourceID: sourceID, library: library, width: 1920, height: 1080, title: title, fill: true)
            .blur(radius: 60).opacity(0.4).ignoresSafeArea()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Cover Flow: the selected game faces the viewer, and its neighbors fan out to each side, turned
/// toward it. Left and right on the remote move the selection; select opens the game's page.
@MainActor
private struct CoverFlow: View {
    let roms: [ImportedROM]
    @Binding var selected: Int
    let library: LibraryModel
    var cover = CGSize(width: 520, height: 380)
    @FocusState private var focused: Bool

    var body: some View {
        let index = min(max(selected, 0), roms.count - 1)
        let rom = roms[index]
        // Fast swipes send several moves before the next redraw, so each move starts from the binding.
        let move = { (step: Int) in
            let current = min(max(selected, 0), roms.count - 1)
            selected = min(max(current + step, 0), roms.count - 1)
        }
        VStack(spacing: 24) {
            NavigationLink { GameView(rom: rom, library: library) } label: {
                ZStack {
                    // Only the covers near the selection exist, however large the library.
                    ForEach(max(index - 5, 0)...min(index + 5, roms.count - 1), id: \.self) { position in
                        let distance = position - index, side = Double(distance.signum())
                        CoverFlowCover(rom: roms[position], library: library, size: cover, highlighted: distance == 0 && focused)
                            .rotation3DEffect(.degrees(side * -55), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                            .scaleEffect(distance == 0 ? 1 : 0.8)
                            .offset(x: side * (cover.width * 0.6 + Double(abs(distance) - 1) * cover.width * 0.2))
                            .brightness(distance == 0 ? 0 : -0.3)
                            .zIndex(-Double(abs(distance)))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: cover.height * 1.35, alignment: .top)
            }
            .buttonStyle(CoverFlowButtonStyle())
            .focused($focused)
            .onMoveCommand { direction in
                if direction == .left { move(-1) } else if direction == .right { move(1) }
            }
            .accessibilityLabel(rom.title)
            .accessibilityAdjustableAction { direction in
                if direction == .decrement { move(-1) } else if direction == .increment { move(1) }
            }
            VStack(spacing: 8) {
                Text(rom.title).font(.title2.bold()).lineLimit(1)
                Text(rom.revision ?? " ").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
    }
}

/// No system focus effect: the cover flow highlights its selected cover instead.
private struct CoverFlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// One cover above a fading reflection.
@MainActor
private struct CoverFlowCover: View {
    let rom: ImportedROM
    let library: LibraryModel
    let size: CGSize
    let highlighted: Bool

    var body: some View {
        let art = GameArtworkView(path: rom.artwork?.coverLarge ?? rom.artwork?.cover, artwork: rom.artwork,
            sourceID: rom.sourceID, library: library, width: size.width, height: size.height, title: rom.title)
        VStack(spacing: 6) {
            art
                .shadow(color: highlighted ? .white.opacity(0.45) : .black.opacity(0.5), radius: highlighted ? 28 : 14)
                .scaleEffect(highlighted ? 1.06 : 1)
            art.scaleEffect(y: -1)
                .frame(height: size.height * 0.3, alignment: .top)
                .clipped()
                .mask { LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom) }
        }
    }
}

/// Cover art for a game without artwork: its title on a color chosen from the title.
private struct TitleArt: View {
    let title: String

    var body: some View {
        // String's hashValue changes per launch; this keeps each game's color stable.
        let hue = Double(title.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.6),
                                    Color(hue: hue, saturation: 0.8, brightness: 0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                .minimumScaleFactor(0.5).padding(28)
        }
    }
}

@MainActor
struct GameView: View {
    let rom: ImportedROM
    let library: LibraryModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(rom.title).font(.title.bold())
                HStack(spacing: 24) {
                    if GameRuntime.available {
                        Button { Task { await library.play(rom) } } label: { Label("Play", systemImage: "play.fill") }
                            .disabled(library.isImporting)
                    }
                    let favorite = library.favorites.contains(rom.id)
                    Button { library.toggleFavorite(rom) } label: {
                        Label(favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: favorite ? "star.fill" : "star")
                    }
                }
                if let artwork = rom.artwork {
                    GameScreenshotGallery(artwork: artwork, sourceID: rom.sourceID, library: library)
                } else {
                    GameArtworkView(path: nil, artwork: nil, sourceID: rom.sourceID, library: library, width: 260, height: 240,
                        title: rom.title)
                }
                if let revision = rom.revision { Text(revision).font(.headline) }
                Text(rom.name).font(.caption).foregroundStyle(.secondary)
            }
            .padding(48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { CoverBackdrop(rom: rom, library: library) }
    }
}

/// Searches every imported game as you type, best match first (FuzzyMatch).
@MainActor
private struct GameSearchView: View {
    let library: LibraryModel
    @State private var query = ""

    var body: some View {
        let results = library.shelf.search.rank(query)
        ScrollView {
            if results.isEmpty {
                Text("No games match “\(query)”.").foregroundStyle(.secondary).padding(48)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 430), spacing: 32)],
                      alignment: .leading, spacing: 36) {
                ForEach(results) { rom in GameTile(rom: rom, library: library) }
            }
            .padding(48)
        }
        .searchable(text: $query, prompt: "Game title")
    }
}

@MainActor
private struct GameTile: View {
    let rom: ImportedROM
    let library: LibraryModel

    var body: some View {
        NavigationLink { GameView(rom: rom, library: library) } label: {
            VStack(alignment: .leading, spacing: 12) {
                GameArtworkView(path: rom.artwork?.cover, artwork: rom.artwork, sourceID: rom.sourceID,
                    library: library, width: 290, height: 220, title: rom.title)
                Text(rom.title).font(.headline).lineLimit(2).frame(width: 290, alignment: .leading)
            }
            .padding(20)
        }
        .buttonStyle(.card)
        .accessibilityLabel(rom.title)
    }
}

@MainActor
struct GameArtworkView: View {
    let path: String?
    let artwork: RomMArtwork?
    let sourceID: UUID
    var source: LibrarySource? = nil
    let library: LibraryModel
    let width: CGFloat
    let height: CGFloat
    /// Shown as generated cover art when there is no image.
    var title: String? = nil
    /// Fills the frame, cropping the image, instead of fitting it.
    var fill = false
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
                Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else if let title {
                TitleArt(title: title)
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
            // Decode off the main thread, so covers appearing during a swipe don't stall it.
            image = await UIImage(data: bytes)?.byPreparingForDisplay()
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
                NavigationStack {
                    SourceBrowserView(source: source, library: library,
                        location: ProcessInfo.processInfo.arguments.contains("--artwork-fixture-detail") ? .rom(3) : .root)
                }
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

/// Guided setup screens on fixture data for simulator screenshots: `--setup-fixture-step results`.
/// Its own settings suite and an empty temporary ROM cache keep the real library untouched;
/// `NATIVECADE_SYNTHETIC_LIBRARY` adds games that count as already imported.
struct SetupFixturePreview: View {
    let step: String
    @State private var library: LibraryModel?
    @State private var detection: PlatformDetection?
    private let source = LibrarySource(id: UUID(uuidString: "5E7C1F8A-3B2D-4C6E-9A1F-2D3E4F5A6B7C") ?? UUID(),
        name: "Fixture RomM", kind: .romm, address: "http://127.0.0.1:18080", allowHTTP: true)

    static var requestedStep: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--setup-fixture-step"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    var body: some View {
        Group {
            if let library {
                switch step {
                case "welcome": SetupFlowView(library: library)
                case "connect": SetupFlowView(library: library, path: [.connect(.romm)])
                case "detect": SetupFlowView(library: library, path: [.connect(.romm), .findPlatforms(source)])
                case "platforms":
                    if let detection {
                        SetupFlowView(library: library, path: [.connect(.romm), .findPlatforms(source),
                                                               .choosePlatforms(source, detection)])
                    } else { Text("The fixture server didn't answer Detect platforms.") }
                case "games": NavigationStack { PlatformScanView(platform: .nintendo64, library: library, mode: .setup) }
                case "results": NavigationStack { PlatformScanView(platform: .nintendo64, library: library, mode: .library) }
                // The fixture connection makes this library one from before guided setup, so it's set up.
                case "home": LibraryHomeView(library: library)
                case "settings": NavigationStack { SettingsView(library: library) }
                default: Text("Unknown setup step “\(step)”.")
                }
            } else { ProgressView("Loading setup fixture…") }
        }
        .task {
            let suite = "nativecade.setup-fixture"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("setup-fixture-\(UUID().uuidString)")
            guard let defaults = UserDefaults(suiteName: suite), let cache = try? ROMCache(root: root) else { return }
            let model = LibraryModel(cache: cache, defaults: defaults)
            if step != "welcome" { try? model.save(source, secret: "fixture-token") }
            await model.restoreCache()
            if step == "platforms" { detection = try? await model.detectPlatforms(source) }
            library = model
        }
        .onDisappear { try? CredentialStore.remove(source.id) }
    }
}

/// Games the simulator smoke tests start, one each time the library appears. A game that
/// quits brings the library back, so NATIVECADE_RESTART_PROBE (such as "oot,fox,kart,oot")
/// checks that games restart in one session; the runtime ends each one after 30 seconds.
@MainActor enum SimulatorLaunchProbe {
    private static var games: [SupportedGame]?
    private static var started = 0

    static func next() -> SupportedGame? {
        let restart = ProcessInfo.processInfo.environment["NATIVECADE_RESTART_PROBE"]
        if games == nil {
            let arguments = ProcessInfo.processInfo.arguments
            games = restart.map { $0.split(separator: ",").map {
                switch $0 {
                case "kart": SupportedGame.marioKart64
                case "fox": .starFox64
                case "mario": .superMario64
                case "banjo": .banjoKazooie
                case "sote": .shadowsOfTheEmpire
                case "racer": .episodeOneRacer
                case "smash": .superSmashBros
                case "cruisnusa": .cruisnUSA
                case "cruisnworld": .cruisnWorld
                default: .ocarinaOfTime
                }
            } }
                ?? (arguments.contains("--nativecade-play-mario-kart") ? [.marioKart64]
                    : arguments.contains("--nativecade-play-cached-rom") ? [.ocarinaOfTime] : [])
        }
        guard let game = games?.first else {
            if restart != nil && started > 0 { NSLog("[RestartProbe] PASS: %d games started in one session", started) }
            started = 0
            return nil
        }
        games?.removeFirst()
        started += 1
        if restart != nil { NSLog("[RestartProbe] starting %@ (%d)", game.title, started) }
        return game
    }
}
#endif

@MainActor
private struct GameScreenshotGallery: View {
    let artwork: RomMArtwork
    let sourceID: UUID
    var source: LibrarySource? = nil
    let library: LibraryModel
    @State private var selected: Screenshot?
    private struct Screenshot: Identifiable { let id: String }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            GameArtworkView(path: artwork.coverLarge ?? artwork.cover, artwork: artwork,
                sourceID: sourceID, source: source, library: library, width: 260, height: 240)
            if !artwork.screenshots.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Screenshots").font(.headline)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 28) {
                            ForEach(artwork.screenshots, id: \.self) { path in
                                Button { selected = Screenshot(id: path) } label: {
                                    GameArtworkView(path: path, artwork: artwork, sourceID: sourceID,
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
                GameArtworkView(path: screenshot.id, artwork: artwork, sourceID: sourceID,
                    source: source, library: library, width: 1200, height: 650)
            }.padding(48)
        }
    }
}
