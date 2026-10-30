import Foundation
import Observation
import RecompSources

@MainActor @Observable
final class LibraryModel {
    private(set) var sources = [LibrarySource]()
    private(set) var imported: ImportedROM?
    private(set) var importedROMs = [ImportedROM]()
    private(set) var batchReport: BatchImportReport?
    private(set) var batchTitle = ""
    private(set) var isImporting = false
    private(set) var isPreparingGame = false
    private(set) var preparingTitle = ""
    private(set) var isRefreshingArtwork = false
    private(set) var artworkRefreshID = UUID()
    private(set) var importStatus = ""
    private(set) var importFraction: Double?
    /// SHA-256 identities of favorite ROMs. They survive clearing the cache, so a reimport is a favorite again.
    private(set) var favorites = Set(UserDefaults.standard.stringArray(forKey: LibraryModel.favoritesKey) ?? [])
    var error: String?
    @ObservationIgnored private var cache: ROMCache?
    @ObservationIgnored private var transfer: Task<Void, Never>?
    @ObservationIgnored private var importID = UUID()
    @ObservationIgnored private var verifying = false
    @ObservationIgnored private var batchIndex = 0
    @ObservationIgnored private let gamePreparation = GamePreparation()
    @ObservationIgnored private let artworkCache = try? ArtworkCache()
    private let settingsKey = "library.sources.v1"
    private static let favoritesKey = "library.favorites.v1"

    init(cache: ROMCache? = nil) {
        do {
            if let data = UserDefaults.standard.data(forKey: settingsKey) {
                sources = try JSONDecoder().decode([LibrarySource].self, from: data)
            }
            self.cache = try cache ?? ROMCache()
        } catch { self.error = error.localizedDescription }
    }

    func restoreCache() async {
        do {
            importedROMs = try await cache?.all() ?? []
            imported = importedROMs.last
        }
        catch { self.error = "The cached ROM could not be verified. Import it again from your server." }
    }

    func artworkData(at path: String, artwork: RomMArtwork, sourceID: UUID,
                     sourceOverride: LibrarySource? = nil) async -> Data? {
        guard let artworkCache else { return nil }
        var paths = [path]
        if path == artwork.coverSmall, let large = artwork.coverLarge, large != path { paths.append(large) }
        for candidate in paths {
            if let data = try? await artworkCache.image(at: candidate, artwork: artwork, sourceID: sourceID, provider: nil) {
                return data
            }
        }
        let source = sourceOverride ?? sources.first { $0.id == sourceID }
        let provider: (any LibraryProvider)?
        if let source, artwork.belongs(to: source) {
            provider = try? ProviderFactory.make(source: source, secret: CredentialStore.load(sourceID))
        } else { provider = nil }
        // A cached cover remains usable offline, even after removing a connection.
        for candidate in paths {
            guard !Task.isCancelled else { return nil }
            if let data = try? await artworkCache.image(at: candidate, artwork: artwork, sourceID: sourceID, provider: provider) {
                return data
            }
        }
        return nil
    }

    func refreshArtwork(force: Bool = false) async {
        guard !isRefreshingArtwork, !isPreparingGame, !isImporting, let cache else { return }
        isRefreshingArtwork = true
        defer { isRefreshingArtwork = false; artworkRefreshID = UUID() }
        for rom in importedROMs where force || rom.artwork == nil {
            guard !Task.isCancelled, !isPreparingGame, !isImporting else { return }
            guard let source = sources.first(where: { $0.id == rom.sourceID && $0.kind == .romm }),
                  rom.artwork == nil || rom.artwork?.belongs(to: source) == true else { continue }
            do {
                let provider = try ProviderFactory.make(source: source, secret: CredentialStore.load(source.id))
                if let artwork = try await provider.artwork(for: rom) {
                    try Task.checkCancellation()
                    guard !isPreparingGame, !isImporting else { return }
                    if let updated = try await cache.attachArtwork(artwork, to: rom),
                       let index = importedROMs.firstIndex(where: { $0.id == rom.id }) {
                        importedROMs[index] = updated
                        if imported?.id == rom.id { imported = updated }
                    }
                }
            } catch { /* Artwork is optional; offline play and ROM imports remain available. */ }
        }
    }

    func toggleFavorite(_ rom: ImportedROM) {
        if favorites.remove(rom.id) == nil { favorites.insert(rom.id) }
        UserDefaults.standard.set(favorites.sorted(), forKey: Self.favoritesKey)
    }

    func save(_ source: LibrarySource, secret: String) throws {
        try source.validate()
        var next = sources.filter { $0.id != source.id }
        next.append(source)
        let data = try JSONEncoder().encode(next)
        try CredentialStore.save(secret, for: source.id)
        UserDefaults.standard.set(data, forKey: settingsKey)
        sources = next
    }

    func remove(_ source: LibrarySource) {
        do {
            let next = sources.filter { $0.id != source.id }
            let data = try JSONEncoder().encode(next)
            try CredentialStore.remove(source.id)
            UserDefaults.standard.set(data, forKey: settingsKey)
            sources = next
        } catch { self.error = error.localizedDescription }
    }

    func acquire(_ entry: LibraryEntry, source: LibrarySource) {
        guard !isImporting, !isPreparingGame, let cache else { return }
        isImporting = true; importStatus = "Connecting…"; importFraction = nil
        batchReport = nil
        let generation = UUID(); importID = generation; verifying = false
        transfer = Task { [weak self] in
            guard let self else { return }
            defer { isImporting = false; transfer = nil }
            do {
                let provider = try ProviderFactory.make(source: source, secret: CredentialStore.load(source.id))
                let result = try await cache.acquire(entry, sourceID: source.id, provider: provider) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self, self.isImporting, self.importID == generation else { return }
                        switch event {
                        case .verifying: self.verifying = true; self.importStatus = "Verifying ROM…"; self.importFraction = nil
                        case .downloading(let value):
                            guard !self.verifying else { return }
                            self.importStatus = "Downloading \(ByteCountFormatter.string(fromByteCount: value.bytes, countStyle: .file))"
                            self.importFraction = value.total.flatMap { $0 > 0 ? Double(value.bytes) / Double($0) : nil }
                        }
                    }
                }
                try Task.checkCancellation()
                imported = result
                if result.recognized { retain(result) }
                importStatus = result.recognized ? "ROM verified and saved to your library." : "This ROM does not match a supported Shipwright revision. It was not cached."
            } catch {
                importStatus = Task.isCancelled ? "Import cancelled." : "Import failed."
                if !Task.isCancelled { self.error = userFacingNetworkError(error) }
            }
        }
    }

    func acquireAll(in location: LibraryLocation, title: String, source: LibrarySource) {
        guard !isImporting, !isPreparingGame, let cache else { return }
        isImporting = true; importStatus = "Finding ROMs…"; importFraction = nil
        batchReport = BatchImportReport(); batchTitle = title; batchIndex = 0; verifying = false
        let generation = UUID(); importID = generation
        transfer = Task { [weak self] in
            guard let self else { return }
            defer { isImporting = false; transfer = nil }
            do {
                let provider = try ProviderFactory.make(source: source, secret: CredentialStore.load(source.id))
                let report = await ROMBatchImporter.run(location: location, sourceID: source.id,
                                                       provider: provider, cache: cache) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self, self.isImporting, self.importID == generation else { return }
                        self.updateBatch(event)
                    }
                }
                batchReport = report
                for result in report.results { if let rom = result.rom { retain(rom) } }
                importStatus = report.summary
                importFraction = nil
            } catch {
                importStatus = Task.isCancelled ? "Import cancelled." : "Import failed."
                if !Task.isCancelled { self.error = userFacingNetworkError(error) }
            }
        }
    }

    private func retain(_ rom: ImportedROM) {
        importedROMs.removeAll { $0.id == rom.id }
        importedROMs.append(rom)
        imported = rom
    }

    private func updateBatch(_ event: BatchImportProgress) {
        switch event {
        case .scanning(let found):
            guard batchIndex == 0 else { return }
            importStatus = "Finding ROMs… \(found) files found"
            let total = found + (batchReport?.results.count ?? 0)
            batchReport?.total = total
        case .importing(let index, let total, let entry, let progress):
            guard index >= batchIndex else { return }
            if index > batchIndex { batchIndex = index; verifying = false; importFraction = nil }
            batchReport?.total = total
            let prefix = "\(index) of \(total) · \(entry.name)"
            switch progress {
            case .none:
                guard !verifying else { return }
                importStatus = "\(prefix) · Connecting…"
            case .verifying:
                verifying = true; importStatus = "\(prefix) · Verifying…"; importFraction = nil
            case .downloading(let value):
                guard !verifying else { return }
                importStatus = "\(prefix) · \(ByteCountFormatter.string(fromByteCount: value.bytes, countStyle: .file))"
                importFraction = value.total.flatMap { $0 > 0 ? Double(value.bytes) / Double($0) : nil }
            }
        case .completed(let result):
            if batchReport?.results.contains(where: { $0.id == result.id }) == false {
                batchReport?.results.append(result)
            }
            if let rom = result.rom { retain(rom) }
        }
    }

    func cancelImport() {
        guard isImporting else { return }
        importID = UUID(); transfer?.cancel(); importStatus = "Cancelling…"
    }

    func clearCache() async {
        guard !isPreparingGame else { return }
        do { try await cache?.clear(); imported = nil; importedROMs = []; batchReport = nil; importStatus = "" }
        catch { self.error = error.localizedDescription }
    }

    func play(_ rom: ImportedROM) async {
        guard GameRuntime.available, !isPreparingGame, !isImporting, let cache else { return }
        isPreparingGame = true; preparingTitle = rom.name; error = nil
        defer { isPreparingGame = false }
        do {
            try await gamePreparation.prepare(rom, cache: cache)
            try Task.checkCancellation()
            try GamePreparation.launch()
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor @Observable
final class SourceBrowserModel {
    let source: LibrarySource
    private(set) var entries = [LibraryEntry]()
    private(set) var loading = false
    private(set) var nextOffset: Int?
    // Each folder opens as its own navigation screen, so tvOS keeps focus and Back working.
    let location: LibraryLocation
    let title: String
    private(set) var artwork: RomMArtwork?
    var search = ""
    var error: String?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init(source: LibrarySource, location: LibraryLocation = .root, title: String? = nil) {
        self.source = source; self.location = location; self.title = title ?? source.name
    }

    var isPlatformList: Bool { source.kind == .romm && location == .root }
    var isGameList: Bool { if case .platform = location { true } else { false } }
    var batchLocation: LibraryLocation? {
        if case .platform = location { return location }
        if source.kind == .smb { return location }
        return nil
    }
    var searchPrompt: String {
        isPlatformList ? "Find a platform" : source.kind == .romm ? "Search this platform" : "Filter this folder"
    }

    func cancel() { operation?.cancel(); generation = UUID(); loading = false }

    func refresh(more: Bool = false) {
        cancel()
        let generation = UUID(); self.generation = generation
        let offset = more ? (nextOffset ?? 0) : 0
        if !more { entries = []; nextOffset = nil; artwork = nil }
        loading = true
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { loading = false; operation = nil } }
            do {
                let provider = try ProviderFactory.make(source: source, secret: CredentialStore.load(source.id))
                let page = try await provider.list(location, search: search, offset: offset)
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                // A changing server catalog can repeat entries across pages; keep stable identities.
                var known = Set(entries.map(\.id))
                entries.append(contentsOf: page.entries.filter { known.insert($0.id).inserted })
                nextOffset = page.nextOffset
                if !more { artwork = page.artwork }
            } catch {
                if !Task.isCancelled && self.generation == generation { self.error = userFacingNetworkError(error) }
            }
        }
    }
}
