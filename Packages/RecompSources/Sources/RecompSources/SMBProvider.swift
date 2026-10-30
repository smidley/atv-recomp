import Foundation
import AMSMB2

struct SMBProvider: LibraryProvider {
    let address: SMBAddress
    let source: LibrarySource
    let password: String

    init(source: LibrarySource, password: String) throws {
        address = try SMBAddress(source.address)
        self.source = source; self.password = password
    }

    private func connect() async throws -> SMB2Manager {
        try Task.checkCancellation()
        let credential = URLCredential(user: source.username.isEmpty ? "guest" : source.username,
                                       password: password, persistence: .none)
        guard let manager = SMB2Manager(url: address.server, domain: source.domain, credential: credential) else {
            throw LibraryError.message("Could not configure the SMB connection.")
        }
        manager.timeout = 20
        do {
            try await manager.connectShare(name: address.share, encrypted: source.requireSMBEncryption)
            try Task.checkCancellation()
            return manager
        } catch {
            manager.disconnectShare(gracefully: true, completionHandler: nil)
            throw error
        }
    }

    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage {
        let path = try address.path(location)
        let manager = try await connect()
        defer { manager.disconnectShare(gracefully: true, completionHandler: nil) }
        // The callback API exposes Sendable values; the older async convenience returns Any.
        let rows: [[URLResourceKey: any Sendable]] = try await withCheckedThrowingContinuation { continuation in
            manager.contentsOfDirectory(atPath: path, recursive: false) { continuation.resume(with: $0) }
        }
        try Task.checkCancellation()
        var entries = [LibraryEntry]()
        for row in rows {
            guard let name = row[.nameKey] as? String, name != ".", name != "..",
                  !(row[.isSymbolicLinkKey] as? Bool ?? false) else { continue }
            let child = try address.child(name, in: path)
            let directory = row[.isDirectoryKey] as? Bool ?? false
            guard directory || LibraryEntry.isROMName(name) else { continue }
            if !FuzzyMatch.matches(search, name) { continue }
            let size = (row[.fileSizeKey] as? NSNumber)?.int64Value
            entries.append(LibraryEntry(id: child, name: name,
                                        detail: directory ? "Folder" : "Unverified N64 ROM", size: size,
                                        target: directory ? .folder(.directory(child)) : .smbFile(child)))
        }
        entries.sort {
            if ($0.folder != nil) != ($1.folder != nil) { return $0.folder != nil }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return LibraryPage(entries: entries, nextOffset: nil)
    }

    func download(_ entry: LibraryEntry, to destination: URL, progress: @escaping ProgressHandler) async throws {
        guard case .smbFile(let path) = entry.target, entry.isROM else {
            throw LibraryError.message("Select an uncompressed N64 ROM file.")
        }
        _ = try address.path(.directory(path))
        let manager = try await connect()
        defer { manager.disconnectShare(gracefully: true, completionHandler: nil) }
        let before = try await manager.attributesOfItem(atPath: path)
        let size = try fileSize(before)
        try TransferLimits.validateSize(size)
        guard entry.size == nil || entry.size == size else {
            throw LibraryError.message("The ROM changed. Refresh the folder and retry.")
        }
        let sink = try SMBFileSink(destination: destination, size: size, progress: progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                manager.contents(atPath: path, fetchedData: { offset, total, data in
                    sink.append(data, offset: offset, total: total)
                }, completionHandler: { error in
                    continuation.resume(with: sink.finish(error))
                })
            }
        } onCancel: {
            sink.cancel()
        }
        try Task.checkCancellation()
        let after = try await manager.attributesOfItem(atPath: path)
        guard try fileSize(after) == size,
              (before[.contentModificationDateKey] as? Date) == (after[.contentModificationDateKey] as? Date) else {
            throw LibraryError.message("The ROM changed during download. Retry after the server file is stable.")
        }
    }

    private func fileSize(_ attributes: [URLResourceKey: any Sendable]) throws -> Int64 {
        guard !(attributes[.isDirectoryKey] as? Bool ?? false),
              !(attributes[.isSymbolicLinkKey] as? Bool ?? false),
              let size = (attributes[.fileSizeKey] as? NSNumber)?.int64Value else {
            throw LibraryError.message("The selected item is not a regular ROM file.")
        }
        return size
    }
}

/// AMSMB2 invokes callbacks on its worker queue; cancellation can arrive concurrently.
/// All mutable state, including the file handle, is protected by this lock.
final class SMBFileSink: @unchecked Sendable {
    private let lock = NSLock()
    private let output: FileHandle
    private let size: Int64
    private let progress: ProgressHandler
    private var count: Int64 = 0
    private var lastReported: Int64 = 0
    private var failure: (any Error)?
    private var cancelled = false

    init(destination: URL, size: Int64, progress: @escaping ProgressHandler) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw LibraryError.message("Could not create the temporary download.")
        }
        output = try FileHandle(forWritingTo: destination)
        self.size = size; self.progress = progress
    }

    func cancel() { lock.withLock { cancelled = true } }

    func append(_ data: Data, offset: Int64, total: Int64) -> Bool {
        let update: TransferProgress? = lock.withLock {
            guard !cancelled, failure == nil else { return nil }
            guard offset == count, total == size, Int64(data.count) <= size - count else {
                failure = LibraryError.message("The ROM changed or exceeded its declared size during transfer.")
                return nil
            }
            do { try output.write(contentsOf: data) }
            catch { failure = error; return nil }
            count += Int64(data.count)
            return TransferProgress(bytes: count, total: size)
        }
        if let update {
            let report = lock.withLock {
                guard update.bytes - lastReported >= 256 * 1024 || update.bytes == size else { return false }
                lastReported = update.bytes
                return true
            }
            if report { progress(update) }
            return true
        }
        return false
    }

    func finish(_ error: (any Error)?) -> Result<Void, any Error> {
        lock.withLock {
            do { try output.close() } catch { failure = failure ?? error }
            if cancelled { return .failure(CancellationError()) }
            if let failure = failure ?? error { return .failure(failure) }
            guard count == size else { return .failure(LibraryError.message("The transfer was incomplete. Retry the download.")) }
            return .success(())
        }
    }
}
