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
        path.append(.games(SupportedPlatform.allCases[0], skipsPlatforms: true))
    }
}

/// A setup screen: the calm backdrop, step pills (none in Settings), content and the support ribbon.
struct SetupScreen<Content: View>: View {
    let stage: SetupStage?
    var skipsPlatforms = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let stage { StepPills(current: stage, skipsPlatforms: skipsPlatforms) }
            content
            Spacer(minLength: 0)
            SupportRibbon()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { CalmBackdrop() }
    }
}

private struct WelcomeView: View {
    let connect: (SourceKind) -> Void

    var body: some View {
        SetupScreen(stage: .connect) {
            Spacer(minLength: 0)
            Kicker(text: "Welcome")
            Text("Nativecade").font(.system(size: 110, weight: .heavy))
            Text("Play the games on your RomM server, natively on Apple TV. Setup takes three steps.")
                .frame(maxWidth: 1100, alignment: .leading)
            HStack(spacing: 28) {
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
            Kicker(text: kind == .smb ? "Step 1 of 2" : "Step 1 of 3")
            Text(kind == .romm ? "Connect RomM" : "Connect an SMB share").font(.title.bold())
            SourceEditorView(source: LibrarySource(kind: kind), library: library, setup: true, onSaved: connected)
        }
    }
}

/// "● Connected · romm.local" above a screen's title.
private struct ConnectedLine: View {
    let serverName: String
    var body: some View {
        HStack(spacing: 10) {
            Text("● Connected").bold().foregroundStyle(.green)
            Text("· \(serverName)").foregroundStyle(.secondary)
        }
        .font(.caption)
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
            ConnectedLine(serverName: source.serverName)
            Text("Find your platforms").font(.title.bold())
            Text("Nativecade checks which consoles your server has games for, and shows the ones it can play.")
                .frame(maxWidth: 1100, alignment: .leading)
            Button(detecting == nil ? "Detect platforms" : "Detecting…") { detect() }
                .disabled(detecting != nil)
            if let error { Text(error).foregroundStyle(.orange).font(.callout) }
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

/// One large card per supported platform, turned on or off, beside a card saying more are coming.
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
            if let serverName { ConnectedLine(serverName: serverName) }
            Text("Choose platforms").font(.title.bold())
            Text(summary(found: rows.count)).frame(maxWidth: 1200, alignment: .leading)
            HStack(spacing: 48) {
                ForEach(rows, id: \.platform) { card($0.platform, romCount: $0.romCount) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("More platforms are on the way").font(.title3.bold())
                    Text("They'll appear here when an update adds them.").font(.callout).foregroundStyle(.secondary)
                }
                .padding(32)
                .frame(width: 520, height: 325, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 3, dash: [12, 10])))
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, 24)
            if let onContinue {
                Button("Continue") { onContinue() }
                    .disabled(!rows.contains { library.setup.platforms.contains($0.platform) })
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
        guard let detection else { return "Turn on the platforms you want in your library." }
        guard let total = detection.serverPlatformCount else {
            return (found == 0 ? "Nativecade doesn't play any of your server's platforms yet."
                    : "Nativecade plays \(found) of your server's platforms so far.")
                + " Add platforms.read to your RomM token to see how many it has."
        }
        let server = total == 1 ? "Your server has 1 platform." : "Your server has \(total) platforms."
        return server + (found == 0 ? " Nativecade doesn't play any of them yet." : " Nativecade plays \(found) of them so far.")
    }

    private func card(_ platform: SupportedPlatform, romCount: Int?) -> some View {
        let on = library.setup.platforms.contains(platform)
        return Button { library.setPlatform(platform, enabled: !on) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(platform.title).font(.title2.bold())
                if let romCount { Text(romCount == 1 ? "1 game on your server" : "\(romCount) games on your server").font(.callout) }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Text(on ? "On" : "Off").font(.callout.bold())
                        .foregroundStyle(on ? .black : .white)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.2)), in: Capsule())
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 6)
            .padding(32)
            .frame(width: 520, height: 325, alignment: .topLeading)
            .background(LinearGradient(colors: platform.cardColors, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(platform.title), \(on ? "on" : "off")")
    }
}

extension SupportedPlatform {
    /// The colors of the platform's cards.
    var cardColors: [Color] {
        switch self {
        case .nintendo64: [Color(red: 0.9, green: 0.15, blue: 0.13), Color(red: 0.12, green: 0.62, blue: 0.26),
                           Color(red: 0.18, green: 0.49, blue: 0.96), Color(red: 0.97, green: 0.71, blue: 0)]
        }
    }
}

extension LibrarySource {
    /// The server's host name, such as romm.local, for "Connected" and a connection's default name.
    var serverName: String { URL(string: address)?.host() ?? (name.isEmpty ? kind.title : name) }
}
