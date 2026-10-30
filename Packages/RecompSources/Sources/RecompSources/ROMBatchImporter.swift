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
}

public enum BatchImportProgress: Sendable {
    case scanning(found: Int)
    case importing(index: Int, total: Int, entry: LibraryEntry, progress: ImportProgress?)
    case completed(BatchImportResult)
}

/// Visits every page and nested file list in one platform/folder, then transfers
/// one file at a time. No search term is carried in from the visible browser.
public enum ROMBatchImporter {
    public static func run(location: LibraryLocation, sourceID: UUID, provider: any LibraryProvider,
                           cache: ROMCache,
                           progress: @escaping @Sendable (BatchImportProgress) -> Void) async -> BatchImportReport {
        var report = BatchImportReport()
        var files = [LibraryEntry]()
        var pending = [(location, "Selected platform")]
        var visited = Set<LibraryLocation>()
        var seenFiles = Set<String>()
        var pages = 0
        do {
            while let (folder, title) = pending.popLast() {
                try Task.checkCancellation()
                guard visited.insert(folder).inserted else { continue }
                var offset = 0
                do {
                    while true {
                        try Task.checkCancellation()
                        pages += 1
                        guard pages <= 100_000, files.count + pending.count <= 100_000 else {
                            throw LibraryError.message("The scan reached its size limit. Import a smaller folder.")
                        }
                        let page = try await provider.list(folder, search: "", offset: offset)
                        try Task.checkCancellation()
                        for entry in page.entries {
                            if let child = entry.folder { pending.append((child, entry.name)) }
                            else if seenFiles.insert(entry.id).inserted { files.append(entry) }
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
                    if folder == location || pages > 100_000 { throw error }
                    let result = BatchImportResult(id: "browse-\(String(describing: folder))", name: title,
                        outcome: .failed, message: "Could not list ROM files. " + userFacingNetworkError(error), rom: nil)
                    report.results.append(result)
                    progress(.completed(result))
                }
            }
            report.discoveryComplete = true
            report.total = files.count + report.results.count
            for entry in files {
                try Task.checkCancellation()
                let index = report.results.count + 1
                let total = report.total
                progress(.importing(index: index, total: total, entry: entry, progress: nil))
                let result: BatchImportResult
                if !entry.isROM {
                    result = BatchImportResult(id: entry.id, name: entry.name, outcome: .skipped,
                        message: "Requires an uncompressed .z64, .v64 or .n64 ROM. Extract archives on the server first.", rom: nil)
                } else {
                    do {
                        let rom = try await cache.acquire(entry, sourceID: sourceID, provider: provider) {
                            progress(.importing(index: index, total: total, entry: entry, progress: $0))
                        }
                        result = BatchImportResult(id: entry.id, name: entry.name,
                            outcome: rom.recognized ? .imported : .unsupported,
                            message: rom.revision ?? "Does not match a supported game revision. Not cached.",
                            rom: rom.recognized ? rom : nil)
                    } catch {
                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                        result = BatchImportResult(id: entry.id, name: entry.name, outcome: .failed,
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
