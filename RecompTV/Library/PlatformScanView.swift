import SwiftUI
import RecompSources

/// A platform's games on the saved connections: what's ready to play, what isn't supported yet,
/// and one button that adds the new ones. Setup's last step waits for Scan for games; a
/// platform's page opens it to scan straight away.
@MainActor
struct PlatformScanView: View {
    enum Mode { case setup, library }
    let platform: SupportedPlatform
    let library: LibraryModel
    let mode: Mode
    /// An SMB setup, which has no platform step.
    var skipsPlatforms = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var report: ScanReport?
    @State private var scanning: Task<Void, Never>?
    @State private var scanID = UUID()
    @State private var importing = false
    @State private var offered: ScanCandidate?
    @State private var showingResults = false

    var body: some View {
        let candidates = report?.scan.candidates ?? []
        let owned = library.ownedGames
        let new = candidates.filter { !owned.contains($0.game) }
        let added = importing && !library.isImporting ? library.batchReport?.count(.imported) ?? 0 : 0
        VStack(alignment: .leading, spacing: 32) {
            if mode == .setup { SetupSteps(current: .games, skipsPlatforms: skipsPlatforms) }
            if let report {
                VStack(alignment: .leading, spacing: 8) {
                    Text(platform.title).font(.title).fontWeight(.medium).padding(.bottom, 8)
                    readyLine(report.scan.candidates.count)
                    ForEach(otherLines(report, owned: candidates.count - new.count), id: \.self) {
                        Text($0).foregroundStyle(.secondary)
                    }
                    ForEach(report.failures, id: \.self) { Text($0).foregroundStyle(Palette.negative).font(.callout) }
                }
                HStack(spacing: 32) {
                    ForEach(report.scan.actions(owned: owned, setup: mode == .setup,
                                                importFinished: importing && !library.isImporting, added: added),
                            id: \.self) { button($0, candidates: candidates) }
                }
                if importing { importProgress }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text(platform.title).font(.title).fontWeight(.medium)
                    Text("Nativecade looks on your connections for the games it can play").foregroundStyle(.secondary)
                }
                if scanning != nil { ProgressView("Looking for games on your connections…") }
                else { Button("Scan for games") { scan() } }
            }
            Spacer(minLength: 0)
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ready to play").font(.headline).fontWeight(.medium)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 32) { ForEach(candidates) { cover($0) } }.padding(.vertical, 24)
                    }
                    .scrollClipDisabled()
                }
            }
            SupportRibbon()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            // The first game with real cover art, shown big: the screen's one bright thing.
            if let featured = candidates.first(where: { $0.artwork?.cover != nil }) {
                GameArtworkView(path: featured.artwork?.coverLarge ?? featured.artwork?.cover, artwork: featured.artwork,
                    sourceID: featured.sourceID, library: library, width: 600, height: 448, title: featured.game.title)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                    .padding(.top, 96).padding(.trailing, 64)
            }
        }
        .background { PageBackground() }
        .confirmationDialog("Add \(offered?.game.title ?? "this game")?",
                            isPresented: Binding(get: { offered != nil }, set: { if !$0 { offered = nil } }),
                            presenting: offered) { candidate in
            Button("Add this game") { importing = true; library.addAll([candidate], title: platform.title) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingResults) { BatchResultsView(library: library) }
        .onAppear { if mode == .library && report == nil && scanning == nil { scan() } }
        // Like the connection browser: leaving the screen or the app stops the import.
        .onDisappear {
            if !showingResults { scanning?.cancel(); if library.isImporting { library.cancelImport() } }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { scanning?.cancel(); if library.isImporting { library.cancelImport() } }
            // Back in the app, a platform page finishes the scan the background stopped.
            else if scenePhase == .active && mode == .library && report == nil && scanning == nil { scan() }
        }
    }

    /// Counts, never lists. The number of games ready to play is the screen's one coral figure.
    @ViewBuilder private func readyLine(_ ready: Int) -> some View {
        if ready == 0 {
            Text("None of the games Nativecade plays are on your connections yet")
        } else {
            Text("\(Text(String(ready)).foregroundStyle(Palette.coral)) \(ready == 1 ? "game is" : "games are") ready to play")
        }
    }

    /// What's already in the library and what isn't supported yet.
    private func otherLines(_ report: ScanReport, owned: Int) -> [String] {
        var lines = [String]()
        if owned > 0 { lines.append(owned == 1 ? "1 is already in your library" : "\(owned) are already in your library") }
        if let more = report.scan.unsupportedCount, more > 0 {
            lines.append(more == 1 ? "1 more isn't supported yet" : "\(more) more aren't supported yet")
        }
        return lines
    }

    @ViewBuilder private func button(_ action: ScanPageAction, candidates: [ScanCandidate]) -> some View {
        switch action {
        case .startPlaying: Button("Start playing") { library.finishSetup() }.disabled(library.isImporting)
        case .done: Button("Done") { dismiss() }
        case .addAll(let count):
            Button(count == 1 ? "Add 1 game" : "Add all \(count)") { importing = true; library.addAll(candidates, title: platform.title) }
                .disabled(library.isImporting)
        case .scanAgain: Button("Scan again") { scan() }.disabled(library.isImporting || scanning != nil)
        case .goToLibrary: Button("Go to library") { library.finishSetup() }.disabled(library.isImporting)
        }
    }

    @ViewBuilder private var importProgress: some View {
        if library.isImporting {
            HStack(spacing: 24) {
                ProgressView(value: library.importFraction).tint(Palette.coral).frame(width: 300)
                Text(library.importStatus).font(.callout).monospacedDigit()
                Button("Cancel import") { library.cancelImport() }
            }
        } else if let batch = library.batchReport {
            HStack(spacing: 24) {
                Text(batch.addedLine).font(.callout)
                Button("View import results") { showingResults = true }
            }
            if let failure = batch.failure { Text(failure).foregroundStyle(Palette.negative).font(.callout) }
        }
    }

    /// A game already in the library opens its page and carries the mint play triangle; any other
    /// offers Add this game.
    @ViewBuilder private func cover(_ candidate: ScanCandidate) -> some View {
        let owned = library.importedROMs.first(where: { $0.game == candidate.game })
        let label = VStack(alignment: .leading, spacing: 12) {
            GameArtworkView(path: candidate.artwork?.cover, artwork: candidate.artwork, sourceID: candidate.sourceID,
                library: library, width: 260, height: 196, title: candidate.game.title)
            HStack(spacing: 8) {
                if owned != nil { PlaysNowMark() }
                Text(candidate.game.title).lineLimit(1)
            }
            .font(.caption)
            .frame(width: 260, alignment: .leading)
        }
        .padding(20)
        if let rom = owned {
            NavigationLink { GameView(rom: rom, library: library) } label: { label }
            .buttonStyle(.card)
            .disabled(library.isImporting)
            .accessibilityLabel("\(candidate.game.title), in your library")
        } else {
            Button { offered = candidate } label: { label }
                .buttonStyle(.card)
                .disabled(library.isImporting)
                .accessibilityLabel("\(candidate.game.title), add this game")
        }
    }

    private func scan() {
        scanning?.cancel()
        importing = false
        let id = UUID(); scanID = id
        scanning = Task {
            let result = await library.scan(platform)
            // A newer scan replaces this one; a cancelled one leaves the screen as it was.
            guard scanID == id else { return }
            if !Task.isCancelled { report = result }
            scanning = nil
        }
    }
}
