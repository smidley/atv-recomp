import Foundation
import Observation
import RecompSources

@MainActor @Observable
final class LibraryModel {
    private(set) var sources = [LibrarySource]()
    private(set) var imported: ImportedROM?
    private(set) var isImporting = false
    private(set) var importStatus = ""
    private(set) var importFraction: Double?
    var error: String?
    @ObservationIgnored private var cache: ROMCache?
    @ObservationIgnored private var transfer: Task<Void, Never>?
    private let settingsKey = "library.sources.v1"

    init() {
        do {
            if let data = UserDefaults.standard.data(forKey: settingsKey) {
                sources = try JSONDecoder().decode([LibrarySource].self, from: data)
            }
            cache = try ROMCache()
        } catch { self.error = error.localizedDescription }
    }

    func restoreCache() async {
        do { imported = try await cache?.current() }
        catch { self.error = "The cached ROM could not be verified. Import it again from your server." }
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
        guard !isImporting, let cache else { return }
        isImporting = true; importStatus = "Connecting…"; importFraction = nil
        transfer = Task { [weak self] in
            guard let self else { return }
            defer { isImporting = false; transfer = nil }
            do {
                let provider = try ProviderFactory.make(source: source, secret: CredentialStore.load(source.id))
                let result = try await cache.acquire(entry, sourceID: source.id, provider: provider) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self, self.isImporting else { return }
                        switch event {
                        case .verifying: self.importStatus = "Verifying ROM…"; self.importFraction = nil
                        case .downloading(let value):
                            self.importStatus = "Downloading \(ByteCountFormatter.string(fromByteCount: value.bytes, countStyle: .file))"
                            self.importFraction = value.total.flatMap { $0 > 0 ? Double(value.bytes) / Double($0) : nil }
                        }
                    }
                }
                try Task.checkCancellation()
                imported = result
                importStatus = result.recognized ? "ROM verified. Game integration is still in progress." : "This ROM does not match a supported Shipwright revision. It was not cached."
            } catch {
                importStatus = Task.isCancelled ? "Import cancelled." : "Import failed."
                if !Task.isCancelled { self.error = userFacingNetworkError(error) }
            }
        }
    }

    func cancelImport() { transfer?.cancel(); importStatus = "Cancelling…" }

    func clearCache() async {
        do { try await cache?.clear(); imported = nil; importStatus = "" }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor @Observable
final class SourceBrowserModel {
    let source: LibrarySource
    private(set) var entries = [LibraryEntry]()
    private(set) var loading = false
    private(set) var nextOffset: Int?
    private(set) var location = LibraryLocation.root
    private(set) var title: String
    private(set) var history = [(LibraryLocation, String)]()
    var search = ""
    var error: String?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init(source: LibrarySource) { self.source = source; title = source.name }

    func open(_ entry: LibraryEntry) {
        guard let folder = entry.folder else { return }
        history.append((location, title)); location = folder; title = entry.name
        search = ""; refresh()
    }

    func back() {
        guard let previous = history.popLast() else { return }
        location = previous.0; title = previous.1; search = ""; refresh()
    }

    func cancel() { operation?.cancel(); generation = UUID(); loading = false }

    func refresh(more: Bool = false) {
        cancel()
        let generation = UUID(); self.generation = generation
        let offset = more ? (nextOffset ?? 0) : 0
        if !more { entries = []; nextOffset = nil }
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
                let known = Set(entries.map(\.id))
                entries.append(contentsOf: page.entries.filter { !known.contains($0.id) })
                nextOffset = page.nextOffset
            } catch {
                if !Task.isCancelled && self.generation == generation { self.error = userFacingNetworkError(error) }
            }
        }
    }
}

func userFacingNetworkError(_ error: any Error) -> String {
    if let error = error as? LibraryError { return error.localizedDescription }
    if let error = error as? URLError {
        switch error.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut:
            return "The server could not be reached. Check its address, network access and local-network permission, then retry."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed:
            return "The server's TLS connection could not be verified. Check its HTTPS certificate."
        default: return "The network transfer failed. Check the server and retry."
        }
    }
    // SMB and Foundation errors can contain server URLs. Do not expose raw provider diagnostics.
    return "The operation failed. Check the server, share name, account permissions and available storage, then retry."
}
