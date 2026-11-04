import SwiftUI
import RecompSources

enum SetupRoute: Hashable {
    case connect(SourceKind)
    case findPlatforms(LibrarySource)
    case choosePlatforms(LibrarySource, PlatformDetection)
    case games(SupportedPlatform, skipsPlatforms: Bool)
}

/// First launch: connect a server, choose its supported platforms, then scan for games.
/// The remote's Back steps back one screen.
@MainActor
struct SetupFlowView: View {
    let library: LibraryModel
    @State private var path: [SetupRoute]

    init(library: LibraryModel, path: [SetupRoute] = []) {
        self.library = library; _path = State(initialValue: path)
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.connect($0)) }
                .navigationDestination(for: SetupRoute.self) { route in
                    switch route {
                    case .connect(let kind):
                        ConnectView(kind: kind, library: library) { connected($0) }
                    case .findPlatforms(let source):
                        FindPlatformsView(source: source, library: library) { path.append(.choosePlatforms(source, $0)) }
                    case .choosePlatforms(let source, let detection):
                        ChoosePlatformsView(library: library, detection: detection, serverName: source.serverName) {
                            if let first = detection.platforms.map(\.platform).first(where: library.setup.platforms.contains) {
                                // Set up from here on, so a relaunch opens the library rather than the welcome.
                                library.completeSetup()
                                path.append(.games(first, skipsPlatforms: false))
                            }
                        }
                    case .games(let platform, let skipsPlatforms):
                        PlatformScanView(platform: platform, library: library, mode: .setup, skipsPlatforms: skipsPlatforms)
                    }
                }
        }
    }

    private func connected(_ source: LibrarySource) {
        if source.kind == .romm { path.append(.findPlatforms(source)); return }
        // ponytail: one platform today; SMB setups enable them all until shares get a platform step
        for platform in SupportedPlatform.allCases { library.setPlatform(platform, enabled: true) }
        library.completeSetup()
        path.append(.games(SupportedPlatform.allCases[0], skipsPlatforms: true))
    }
}

/// A setup screen: the plain page, the step row (none in Settings), content and the support ribbon.
struct SetupScreen<Content: View>: View {
    let stage: SetupStage?
    var skipsPlatforms = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let stage { SetupSteps(current: stage, skipsPlatforms: skipsPlatforms) }
            content
            Spacer(minLength: 0)
            SupportRibbon()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { PageBackground() }
    }
}

private struct WelcomeView: View {
    let connect: (SourceKind) -> Void

    var body: some View {
        SetupScreen(stage: .connect) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                // The wordmark in rounded type, after the logo's lettering; the headline is the brand's line.
                Text("Nativecade").font(.title3).fontWeight(.semibold).fontDesign(.rounded).foregroundStyle(Palette.coral)
                Text("Classic games, built for Apple TV").font(.title).fontWeight(.medium)
                Text("Play the games on your RomM server, natively on Apple TV. Setup takes three steps.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 1200, alignment: .leading)
            }
            HStack(spacing: 32) {
                Button("Connect RomM") { connect(.romm) }
                Button("Use an SMB share") { connect(.smb) }
            }
            .padding(.top, 16)
        }
    }
}

private struct ConnectView: View {
    let kind: SourceKind
    let library: LibraryModel
    let connected: (LibrarySource) -> Void

    var body: some View {
        SetupScreen(stage: .connect, skipsPlatforms: kind == .smb) {
            Text(kind == .romm ? "Connect RomM" : "Connect an SMB share").font(.title).fontWeight(.medium)
            // Coming back to setup reuses its saved connection rather than adding another.
            SourceEditorView(source: library.sources.last(where: { $0.kind == kind }) ?? LibrarySource(kind: kind),
                             library: library, setup: true, onSaved: connected)
        }
    }
}

/// "Connected to romm.local" above a screen's title.
private struct ConnectedLine: View {
    let serverName: String
    var body: some View {
        Text("Connected to \(serverName)").font(.callout).foregroundStyle(.secondary)
    }
}

private struct FindPlatformsView: View {
    let source: LibrarySource
    let library: LibraryModel
    let found: (PlatformDetection) -> Void
    @State private var detecting: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        SetupScreen(stage: .platforms) {
            VStack(alignment: .leading, spacing: 16) {
                ConnectedLine(serverName: source.serverName)
                Text("Find your platforms").font(.title).fontWeight(.medium)
                Text("Nativecade checks which consoles your server has games for, and shows the ones it can play")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 1200, alignment: .leading)
            }
            Button(detecting == nil ? "Detect platforms" : "Detecting…") { detect() }
                .disabled(detecting != nil)
            if let error { Text(error).foregroundStyle(Palette.negative).font(.callout) }
        }
        .onDisappear { detecting?.cancel() }
    }

    private func detect() {
        error = nil
        detecting = Task {
            defer { detecting = nil }
            do {
                let detection = try await library.detectPlatforms(source)
                try Task.checkCancellation()
                found(detection)
            } catch { if !Task.isCancelled { self.error = userFacingNetworkError(error) } }
        }
    }
}

/// A cartridge per supported platform, turned on or off, beside a note that more are coming.
/// Without a detection it's the Settings version: every supported platform, no counts.
struct ChoosePlatformsView: View {
    let library: LibraryModel
    let detection: PlatformDetection?
    let serverName: String?
    let onContinue: (() -> Void)?

    private var rows: [(platform: SupportedPlatform, romCount: Int?)] {
        detection.map { $0.platforms.map { ($0.platform, $0.romCount) } } ?? SupportedPlatform.allCases.map { ($0, nil) }
    }

    var body: some View {
        let rows = rows
        SetupScreen(stage: detection == nil ? nil : .platforms) {
            VStack(alignment: .leading, spacing: 16) {
                if let serverName { ConnectedLine(serverName: serverName) }
                Text("Choose platforms").font(.title).fontWeight(.medium)
                Text(summary(found: rows.count)).foregroundStyle(.secondary).frame(maxWidth: 1200, alignment: .leading)
            }
            HStack(alignment: .center, spacing: 48) {
                ForEach(rows, id: \.platform) { card($0.platform, romCount: $0.romCount) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("More platforms are on the way").font(.headline).fontWeight(.medium)
                    Text("They'll appear here when an update adds them").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            if let onContinue {
                if rows.isEmpty {
                    // Nothing here to turn on; setup still leads into the library and its Settings.
                    Button("Go to library") { library.finishSetup() }
                } else {
                    Button("Continue") { onContinue() }
                        .disabled(!rows.contains { library.setup.platforms.contains($0.platform) })
                }
            }
        }
        .onAppear {
            // Every platform found starts on.
            if detection != nil, !rows.contains(where: { library.setup.platforms.contains($0.platform) }) {
                for row in rows { library.setPlatform(row.platform, enabled: true) }
            }
        }
    }

    private func summary(found: Int) -> String {
        guard let detection else { return "Turn on the platforms you want in your library" }
        guard let total = detection.serverPlatformCount else {
            return (found == 0 ? "Nativecade doesn't play any of your server's platforms yet."
                    : "Nativecade plays \(found) of your server's platforms so far.")
                + " Add platforms.read to your RomM token to see how many it has."
        }
        let server = total == 1 ? "Your server has 1 platform." : "Your server has \(total) platforms."
        return server + (found == 0 ? " Nativecade doesn't play any of them yet." : " Nativecade plays \(found) of them so far.")
    }

    /// The platform's cartridge, and under it whether it's on: the mint play triangle when it is.
    private func card(_ platform: SupportedPlatform, romCount: Int?) -> some View {
        let on = library.setup.platforms.contains(platform)
        return Button { library.setPlatform(platform, enabled: !on) } label: {
            VStack(alignment: .leading, spacing: 12) {
                Cartridge(title: platform.title,
                          detail: romCount.map { $0 == 1 ? "1 game on your server" : "\($0) games on your server" })
                HStack(spacing: 12) {
                    if on { PlaysNowMark(); Text("On") } else { Text("Off").foregroundStyle(.tertiary) }
                }
                .font(.callout)
            }
            .padding(20)
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(platform.title), \(on ? "on" : "off")")
    }
}

extension LibrarySource {
    /// The server's host name, such as romm.local, for "Connected" and a connection's default name.
    var serverName: String { URL(string: address)?.host() ?? (name.isEmpty ? kind.title : name) }
}
