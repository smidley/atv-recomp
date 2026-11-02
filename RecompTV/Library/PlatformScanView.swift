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
        VStack(alignment: .leading, spacing: 24) {
            if mode == .setup {
                StepPills(current: .games, skipsPlatforms: skipsPlatforms)
                Kicker(text: skipsPlatforms ? "Step 2 of 2" : "Step 3 of 3")
            }
            Text(platform.title).font(.title.bold())
            if let report {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines(report, owned: candidates.count - new.count), id: \.self) { Text($0) }
                    ForEach(report.failures, id: \.self) { Text($0).foregroundStyle(.orange).font(.callout) }
                }
                HStack(spacing: 28) {
                    if added > 0 {
                        Button(mode == .setup ? "Start playing" : "Done") {
                            if mode == .setup { library.completeSetup() } else { dismiss() }
                        }
                    } else if !new.isEmpty {
                        Button("Add all \(new.count)") { importing = true; library.addAll(candidates, title: platform.title) }
                            .disabled(library.isImporting)
                    }
                    Button("Scan again") { scan() }.disabled(library.isImporting || scanning != nil)
                }
                if importing { importProgress }
            } else if scanning != nil {
                ProgressView("Looking for games on your connections…")
            } else {
                Text("Nativecade looks on your connections for the games it can play.")
                Button("Scan for games") { scan() }
            }
            Spacer(minLength: 0)
            if !candidates.isEmpty {
                Text("Ready to play").font(.headline)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 40) { ForEach(candidates) { cover($0) } }.padding(.vertical, 24)
                }
                .scrollClipDisabled()
            }
            SupportRibbon()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if let featured = candidates.first {
                GameArtworkView(path: featured.artwork?.coverLarge ?? featured.artwork?.cover, artwork: featured.artwork,
                    sourceID: featured.sourceID, library: library, width: 600, height: 450, title: featured.game.title)
                    .rotationEffect(.degrees(-3))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
                    .padding(.top, 100).padding(.trailing, 60)
            }
        }
        .background {
            if let featured = candidates.first {
                CoverBackdrop(artwork: featured.artwork, sourceID: featured.sourceID, title: featured.game.title, library: library)
            } else { CalmBackdrop() }
        }
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

    /// Counts, never lists: what's ready, what's already here and what isn't supported yet.
    private func lines(_ report: ScanReport, owned: Int) -> [String] {
        let ready = report.scan.candidates.count
        var lines = [ready == 0 ? "None of the games Nativecade plays are on your connections yet."
                     : ready == 1 ? "1 game is ready to play." : "\(ready) games are ready to play."]
        if owned > 0 { lines.append(owned == 1 ? "1 is already in your library." : "\(owned) are already in your library.") }
        if let more = report.scan.unsupportedCount, more > 0 {
            lines.append(more == 1 ? "1 more isn't supported yet." : "\(more) more aren't supported yet.")
        }
        return lines
    }

    @ViewBuilder private var importProgress: some View {
        if library.isImporting {
            HStack(spacing: 24) {
                ProgressView(value: library.importFraction).frame(width: 300)
                Text(library.importStatus).font(.callout)
                Button("Cancel import") { library.cancelImport() }
            }
        } else if let batch = library.batchReport {
            HStack(spacing: 24) {
                Text(batch.addedLine).font(.callout)
                Button("View import results") { showingResults = true }
            }
            if let failure = batch.failure { Text(failure).foregroundStyle(.orange).font(.callout) }
        }
    }

    /// A game already in the library opens its page; any other offers Add this game.
    @ViewBuilder private func cover(_ candidate: ScanCandidate) -> some View {
        let label = VStack(alignment: .leading, spacing: 12) {
            GameArtworkView(path: candidate.artwork?.cover, artwork: candidate.artwork, sourceID: candidate.sourceID,
                library: library, width: 260, height: 195, title: candidate.game.title)
            Text(candidate.game.title).font(.caption).lineLimit(1).frame(width: 260, alignment: .leading)
        }
        if let rom = library.importedROMs.first(where: { $0.game == candidate.game }) {
            NavigationLink { GameView(rom: rom, library: library) } label: {
                label.overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark.circle.fill").font(.title2)
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .green).padding(10)
                }
            }
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
