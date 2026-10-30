import Foundation
import Testing
@testable import RecompSources

private struct PageKey: Hashable, Sendable {
    let location: LibraryLocation
    let offset: Int
    init(_ location: LibraryLocation, _ offset: Int = 0) { self.location = location; self.offset = offset }
}

private func file(_ id: String, _ name: String = "Fixture.z64") -> LibraryEntry {
    LibraryEntry(id: id, name: name, detail: "", size: 256 * 1024, target: .smbFile(id))
}

private func folder(_ id: Int) -> LibraryEntry {
    LibraryEntry(id: "rom-\(id)", name: "Game \(id)", detail: "", size: nil, target: .folder(.rom(id)))
}

private actor BatchFixtureProvider: LibraryProvider {
    let pages: [PageKey: LibraryPage]
    let bytes: [String: Data]
    let slowID: String?
    let started: AsyncStream<Void>.Continuation?
    private(set) var requests = [PageKey]()
    private(set) var searches = [String]()
    private(set) var downloads = [String]()
    private(set) var maxConcurrentDownloads = 0
    private var activeDownloads = 0

    init(pages: [PageKey: LibraryPage], bytes: [String: Data], slowID: String? = nil,
         started: AsyncStream<Void>.Continuation? = nil) {
        self.pages = pages; self.bytes = bytes; self.slowID = slowID; self.started = started
    }

    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage {
        requests.append(PageKey(location, offset)); searches.append(search)
        guard let page = pages[PageKey(location, offset)] else { throw URLError(.cannotConnectToHost) }
        return page
    }

    func download(_ entry: LibraryEntry, to destination: URL, progress: @escaping ProgressHandler) async throws {
        downloads.append(entry.id); activeDownloads += 1
        maxConcurrentDownloads = max(maxConcurrentDownloads, activeDownloads)
        defer { activeDownloads -= 1 }
        if entry.id == slowID {
            try Data([1, 2, 3]).write(to: destination)
            started?.yield(())
            try await Task.sleep(for: .seconds(30))
        }
        guard let bytes = bytes[entry.id] else { throw URLError(.networkConnectionLost) }
        try bytes.write(to: destination)
        progress(TransferProgress(bytes: Int64(bytes.count), total: Int64(bytes.count)))
    }
}

private func acceptedCache(in root: URL, bytes: [Data]) throws -> ROMCache {
    var revisions = [String: String]()
    for (index, data) in bytes.enumerated() {
        let path = root.appendingPathComponent("identity-\(index)")
        try data.write(to: path)
        revisions[try ROMIdentity.read(path).sha1] = "Synthetic \(index)"
    }
    return try ROMCache(root: root.appendingPathComponent("cache"), revisions: revisions)
}

@Test func batchImportsAllPagesDeduplicatesAndContinuesAfterFailures() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = syntheticROM()
    var second = first; second[20] ^= 1
    var unknown = first; unknown[24] ^= 1
    let cache = try acceptedCache(in: root, bytes: [first, second])
    let provider = BatchFixtureProvider(pages: [
        PageKey(.platform(1)): LibraryPage(entries: [folder(1)], nextOffset: 1),
        PageKey(.platform(1), 1): LibraryPage(entries: [folder(1), folder(2), folder(3)], nextOffset: nil),
        PageKey(.rom(1)): LibraryPage(entries: [file("first"), file("first"), file("archive", "Game.zip")], nextOffset: nil),
        PageKey(.rom(2)): LibraryPage(entries: [file("second"), file("unknown"), file("broken")], nextOffset: nil),
        // Game 3 deliberately cannot be listed; the other games must still import.
    ], bytes: ["first": first, "second": second, "unknown": unknown])
    let report = await ROMBatchImporter.run(location: .platform(1), sourceID: UUID(), provider: provider,
                                            cache: cache, progress: { _ in })
    #expect(report.discoveryComplete)
    #expect(report.failure == nil)
    #expect(report.total == 6)
    #expect(report.count(.imported) == 2)
    #expect(report.count(.unsupported) == 1)
    #expect(report.count(.skipped) == 1)
    #expect(report.count(.failed) == 2)
    #expect(try await cache.all().count == 2)
    #expect(await provider.downloads.count == 4)
    #expect(await provider.maxConcurrentDownloads == 1)
    #expect(await provider.searches.allSatisfy(\.isEmpty))
    #expect(await provider.requests.filter { $0.location == .rom(1) }.count == 1)
}

@Test func cancellingBatchKeepsCompletedROMsAndRemovesPartialDownloads() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = syntheticROM()
    let cache = try acceptedCache(in: root, bytes: [bytes])
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let provider = BatchFixtureProvider(pages: [
        PageKey(.directory("N64")): LibraryPage(entries: [file("first"), file("slow"), file("later")], nextOffset: nil),
    ], bytes: ["first": bytes, "slow": bytes, "later": bytes], slowID: "slow", started: continuation)
    let task = Task {
        await ROMBatchImporter.run(location: .directory("N64"), sourceID: UUID(), provider: provider,
                                  cache: cache, progress: { _ in })
    }
    for await _ in stream { break }
    task.cancel()
    let report = await task.value
    continuation.finish()
    #expect(report.cancelled)
    #expect(report.results.count == 1)
    #expect(report.total == 3)
    #expect(report.count(.imported) == 1)
    #expect(try await cache.all().count == 1)
    #expect(await provider.downloads == ["first", "slow"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("cache").path)
        .allSatisfy { !$0.hasSuffix(".partial") })
}

@Test func repeatedPaginationDoesNotPretendBatchCompleted() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = BatchFixtureProvider(pages: [
        PageKey(.platform(1)): LibraryPage(entries: [folder(1)], nextOffset: 0),
    ], bytes: [:])
    let report = await ROMBatchImporter.run(location: .platform(1), sourceID: UUID(), provider: provider,
                                            cache: try ROMCache(root: root), progress: { _ in })
    #expect(report.failure != nil)
    #expect(!report.discoveryComplete)
    #expect(await provider.downloads.isEmpty)
}

@Test func multiROMCacheMigratesLegacyRecordAndPreservesOtherIdentities() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = syntheticROM()
    var other = bytes; other[44] ^= 1
    let cache = try acceptedCache(in: root, bytes: [bytes, other])
    let provider = BatchFixtureProvider(pages: [:], bytes: ["first": bytes, "second": other])
    let first = try await cache.acquire(file("first"), sourceID: UUID(), provider: provider, progress: { _ in })
    let cacheRoot = root.appendingPathComponent("cache")
    try JSONEncoder().encode(first).write(to: cacheRoot.appendingPathComponent("current.json"))
    try FileManager.default.removeItem(at: cacheRoot.appendingPathComponent("library.json"))
    #expect(try await cache.current() == first)
    let second = try await cache.acquire(file("second"), sourceID: UUID(), provider: provider, progress: { _ in })
    #expect(try await cache.all() == [first, second])
    _ = try await cache.acquire(file("first"), sourceID: first.sourceID, provider: provider, progress: { _ in })
    #expect(try await cache.all().count == 2)
    #expect(try FileManager.default.contentsOfDirectory(atPath: cacheRoot.path).filter { $0.hasSuffix(".romdata") }.count == 2)
    try Data([1, 2, 3]).write(to: cacheRoot.appendingPathComponent(second.sha256 + ".romdata"))
    #expect(try await cache.all() == [first])
}

@Test func gameHandoffRevalidatesCachedBytesAndRequiresIndexedRecord() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = syntheticROM()
    let cache = try acceptedCache(in: root, bytes: [bytes])
    let provider = BatchFixtureProvider(pages: [:], bytes: ["first": bytes])
    let rom = try await cache.acquire(file("first"), sourceID: UUID(), provider: provider, progress: { _ in })
    let url = try await cache.verifiedFileURL(for: rom)
    #expect(try Data(contentsOf: url) == bytes)
    var damaged = bytes; damaged[48] ^= 1
    try damaged.write(to: url)
    await #expect(throws: (any Error).self) { try await cache.verifiedFileURL(for: rom) }
    try bytes.write(to: url)
    try Data("[]".utf8).write(to: root.appendingPathComponent("cache/library.json"))
    await #expect(throws: (any Error).self) { try await cache.verifiedFileURL(for: rom) }
    try FileManager.default.removeItem(at: url)
    await #expect(throws: (any Error).self) { try await cache.verifiedFileURL(for: rom) }
}
