import Foundation

public struct BatchImportResult: Identifiable, Sendable, Equatable {
    public enum Outcome: String, Sendable { case imported, unsupported, skipped, failed }
    public let id: String
    public let name: String
    public let outcome: Outcome
    public let message: String
    public let rom: ImportedROM?
}

public struct BatchImportReport: Sendable {
    public var results = [BatchImportResult]()
    public var total = 0
    public var cancelled = false
    public var discoveryComplete = false
    public var failure: String?
    public init() {}
    public func count(_ outcome: BatchImportResult.Outcome) -> Int {
        results.filter { $0.outcome == outcome }.count
    }
    public var summary: String {
        let state = cancelled ? "Cancelled" : failure != nil ? "Stopped" : "Finished"
        return "\(state): \(count(.imported)) imported, \(count(.unsupported)) unsupported, \(count(.skipped)) skipped, \(count(.failed)) failed."
    }
    /// What Add all did, in words: "9 added · 1 is a different version".
    public var addedLine: String {
        let parts: [(BatchImportResult.Outcome, String, String)] = [
            (.imported, "added", "added"), (.unsupported, "is a different version", "are a different version"),
            (.skipped, "is compressed", "are compressed"), (.failed, "couldn't be downloaded", "couldn't be downloaded"),
        ]
        let line = parts.compactMap { outcome, one, many -> String? in
            let number = count(outcome)
            return number == 0 ? nil : "\(number) \(number == 1 ? one : many)"
        }.joined(separator: " · ")
        return (cancelled ? "Cancelled · " : "") + (line.isEmpty ? "Nothing was added" : line)
    }
}

public enum BatchImportProgress: Sendable {
    case scanning(found: Int)
    case importing(index: Int, total: Int, entry: LibraryEntry, progress: ImportProgress?)
    case completed(BatchImportResult)
}

/// One thing to import: a file, or a folder (such as a RomM game) whose files are imported.
public struct ImportItem: Sendable {
    public let entry: LibraryEntry
    public let sourceID: UUID
    public let provider: any LibraryProvider
    public init(entry: LibraryEntry, sourceID: UUID, provider: any LibraryProvider) {
        self.entry = entry; self.sourceID = sourceID; self.provider = provider
    }
}

/// Visits every page and nested file list in one platform/folder, then transfers
/// one file at a time. No search term is carried in from the visible browser.
public enum ROMBatchImporter {
    public static func run(location: LibraryLocation, sourceID: UUID, provider: any LibraryProvider,
                           cache: ROMCache,
                           progress: @escaping @Sendable (BatchImportProgress) -> Void) async -> BatchImportReport {
        let folder = LibraryEntry(id: "", name: "Selected platform", detail: "", size: nil, target: .folder(location))
        return await run([ImportItem(entry: folder, sourceID: sourceID, provider: provider)],
                         stopOnUnlistedItem: true, cache: cache, progress: progress)
    }

    /// Items from several connections in one batch, imported in item order. A folder that
    /// can't be listed is reported, and the other items still import.
    public static func run(items: [ImportItem], cache: ROMCache,
                           progress: @escaping @Sendable (BatchImportProgress) -> Void) async -> BatchImportReport {
        await run(items, stopOnUnlistedItem: false, cache: cache, progress: progress)
    }

    private static func run(_ items: [ImportItem], stopOnUnlistedItem: Bool, cache: ROMCache,
                            progress: @escaping @Sendable (BatchImportProgress) -> Void) async -> BatchImportReport {
        var report = BatchImportReport()
        var files = [ImportItem]()
        // Two connections can use the same locations and entry IDs, so both sets include the source.
        var visited = Set<String>()
        var seenFiles = Set<String>()
        var pages = 0
        do {
            for item in items {
                guard let location = item.entry.folder else {
                    if seenFiles.insert("\(item.sourceID)/\(item.entry.id)").inserted { files.append(item) }
                    continue
                }
                var pending = [(location, item.entry.name)]
                while let (folder, title) = pending.popLast() {
                    try Task.checkCancellation()
                    guard visited.insert("\(item.sourceID)/\(folder)").inserted else { continue }
                    var offset = 0
                    do {
                        while true {
                            try Task.checkCancellation()
                            pages += 1
                            guard pages <= 100_000, files.count + pending.count <= 100_000 else {
                                throw LibraryError.message("The scan reached its size limit. Import a smaller folder.")
                            }
                            let page = try await item.provider.list(folder, search: "", offset: offset)
                            try Task.checkCancellation()
                            for entry in page.entries {
                                if let child = entry.folder { pending.append((child, entry.name)) }
                                else if seenFiles.insert("\(item.sourceID)/\(entry.id)").inserted {
                                    files.append(ImportItem(entry: entry, sourceID: item.sourceID, provider: item.provider))
                                }
                            }
                            report.total = files.count + report.results.count
                            progress(.scanning(found: files.count))
                            guard let next = page.nextOffset else { break }
                            guard next > offset, !page.entries.isEmpty else {
                                throw LibraryError.message("The server repeated a catalog page. Refresh and retry.")
                            }
                            offset = next
                        }
                    } catch {
                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                        if (stopOnUnlistedItem && folder == location) || pages > 100_000 { throw error }
                        let result = BatchImportResult(id: "browse-\(item.sourceID)/\(String(describing: folder))", name: title,
                            outcome: .failed, message: "Could not list ROM files. " + userFacingNetworkError(error), rom: nil)
                        report.results.append(result)
                        progress(.completed(result))
                    }
                }
            }
            report.discoveryComplete = true
            report.total = files.count + report.results.count
            for file in files {
                try Task.checkCancellation()
                let entry = file.entry, id = "\(file.sourceID)/\(entry.id)"
                let index = report.results.count + 1
                let total = report.total
                progress(.importing(index: index, total: total, entry: entry, progress: nil))
                let result: BatchImportResult
                if !entry.isROM {
                    result = BatchImportResult(id: id, name: entry.name, outcome: .skipped,
                        message: "Requires an uncompressed .z64, .v64 or .n64 ROM. Extract archives on the server first.", rom: nil)
                } else {
                    do {
                        let rom = try await cache.acquire(entry, sourceID: file.sourceID, provider: file.provider) {
                            progress(.importing(index: index, total: total, entry: entry, progress: $0))
                        }
                        result = BatchImportResult(id: id, name: entry.name,
                            outcome: rom.recognized ? .imported : .unsupported,
                            message: rom.revision ?? "Does not match a supported game revision. Not cached.",
                            rom: rom.recognized ? rom : nil)
                    } catch {
                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                        result = BatchImportResult(id: id, name: entry.name, outcome: .failed,
                            message: userFacingNetworkError(error), rom: nil)
                    }
                }
                report.results.append(result)
                progress(.completed(result))
            }
        } catch {
            if Task.isCancelled || error is CancellationError { report.cancelled = true }
            else { report.failure = userFacingNetworkError(error) }
        }
        return report
    }
}
