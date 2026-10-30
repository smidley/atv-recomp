import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import RecompSources

@Test func artworkPathsStayOnTheServerAndPreserveProxyPrefixes() throws {
    let server = try RomMAddress("https://example.test/library/api/", allowHTTP: false)
    for path in ["/assets/romm/resources/roms/1/3/cover/small.png?ts=2026-10-28",
                 "/library/assets/romm/resources/roms/1/3/cover/small.png?ts=2026-10-28",
                 "https://example.test/library/assets/romm/resources/roms/1/3/cover/small.png?ts=2026-10-28"] {
        let result = try server.artworkURL(path)
        #expect(result.path == "/library/assets/romm/resources/roms/1/3/cover/small.png")
        #expect(result.host == "example.test")
        #expect(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems?.first?.name == "ts")
    }
    #expect(try server.artworkURL("/assets/platforms/n64.ico").path == "/library/assets/platforms/n64.ico")
    for path in ["https://outside.test/assets/romm/resources/a.png", "//outside.test/assets/romm/resources/a.png",
                 "/assets/platforms", "/assets/platforms/n64/../../../api/users/me", "/assets/platforms/%2e%2e",
                 "http://example.test/assets/romm/resources/a.png", "/api/users/me",
                 "https://secret@example.test/assets/romm/resources/a.png",
                 "/assets/romm/resources/%2e%2e/private.png", "/assets/romm/resources/%252e%252e/private.png",
                 "/assets/romm/resources/a.png?token=secret", "/assets/romm/resources/a.png#secret",
                 "/assets/romm/resources/a%2fb.png/../secret"] {
        #expect(throws: LibraryError.self) { try server.artworkURL(path) }
    }
}

private func imageFixture(width: Int = 80, height: Int = 40) throws -> Data {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func metadata() -> RomMArtwork {
    RomMArtwork(romID: 3, server: "https://example.test", title: "Fixture", coverSmall: "/assets/romm/resources/cover.png",
                coverLarge: nil, screenshots: [])
}

private actor ImageProvider: LibraryProvider {
    let bytes: Data
    let delay: Duration
    let started: AsyncStream<Void>.Continuation?
    private(set) var requests = 0
    init(_ bytes: Data, delay: Duration = .milliseconds(25), started: AsyncStream<Void>.Continuation? = nil) {
        self.bytes = bytes; self.delay = delay; self.started = started
    }
    func imageData(at path: String) async throws -> Data {
        requests += 1
        started?.yield(())
        try await Task.sleep(for: delay)
        return bytes
    }
    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage {
        LibraryPage(entries: [], nextOffset: nil)
    }
    func download(_ entry: LibraryEntry, to destination: URL, progress: @escaping ProgressHandler) async throws {
        try syntheticROM().write(to: destination)
    }
}

@Test func leavingTheLastArtworkConsumerCancelsItsDownload() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let (started, signal) = AsyncStream<Void>.makeStream()
    let provider = ImageProvider(try imageFixture(), delay: .seconds(30), started: signal)
    let cache = try ArtworkCache(root: root), art = metadata()
    let download = Task { try await cache.image(at: "slow", artwork: art, sourceID: UUID(), provider: provider) }
    for await _ in started { break }
    let before = ContinuousClock.now
    download.cancel()
    await #expect(throws: CancellationError.self) { try await download.value }
    #expect(ContinuousClock.now - before < .seconds(5))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    signal.finish()
}

@Test func artworkCacheCoalescesRequestsAndWorksOfflineWithoutCrossingSources() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = ImageProvider(try imageFixture())
    let cache = try ArtworkCache(root: root)
    let art = metadata(), source = UUID(), path = try #require(art.cover)
    async let first = cache.image(at: path, artwork: art, sourceID: source, provider: provider)
    async let second = cache.image(at: path, artwork: art, sourceID: source, provider: provider)
    let (a, b) = try await (first, second)
    #expect(a == b)
    #expect(await provider.requests == 1)
    let reopened = try ArtworkCache(root: root)
    #expect(try await reopened.image(at: path, artwork: art, sourceID: source, provider: nil) == a)
    await #expect(throws: LibraryError.self) {
        try await reopened.image(at: path, artwork: art, sourceID: UUID(), provider: nil)
    }
    await #expect(throws: LibraryError.self) {
        try await reopened.image(at: path + "?ts=changed", artwork: art, sourceID: source, provider: nil)
    }
}

@Test func artworkCacheBoundsStorageAndRejectsNonImages() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = try imageFixture(), art = metadata(), source = UUID()
    let capacity = try ArtworkCache.thumbnail(bytes).count + 10
    let cache = try ArtworkCache(root: root, capacity: capacity)
    let provider = ImageProvider(bytes)
    for index in 0..<4 {
        _ = try await cache.image(at: "image-\(index)", artwork: art, sourceID: source, provider: provider)
    }
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
    #expect(files.count == 1)
    let stored = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    #expect(stored <= capacity)
    await #expect(throws: LibraryError.self) {
        try await cache.image(at: "invalid", artwork: art, sourceID: source,
                              provider: ImageProvider(Data("<html>Login</html>".utf8)))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
}

@Test func artworkDecodingDownsamplesLargeImagesAndRejectsOversizedBodies() throws {
    let image = try ArtworkCache.thumbnail(imageFixture(width: 2400, height: 1600))
    let source = try #require(CGImageSourceCreateWithData(image as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1200)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 800)
    #expect(throws: LibraryError.self) { try ArtworkCache.thumbnail(Data(repeating: 0, count: Int(ArtworkCache.downloadLimit) + 1)) }
}

@Test func importedArtworkPersistsWithoutChangingTheROMAndLegacyRecordsStillDecode() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let romFile = root.appendingPathComponent("identity")
    try syntheticROM().write(to: romFile)
    let identity = try ROMIdentity.read(romFile)
    let cache = try ROMCache(root: root.appendingPathComponent("roms"), revisions: [identity.sha1: "Fixture"])
    let art = metadata()
    let entry = LibraryEntry(id: "file-11", name: "Fixture.z64", detail: "", size: identity.size,
                             target: .romFile(11, "Fixture.z64"), artwork: art)
    let imported = try await cache.acquire(entry, sourceID: UUID(), provider: ImageProvider(Data()), progress: { _ in })
    #expect(try await cache.all().first?.artwork == art)
    let refreshed = RomMArtwork(romID: art.romID, server: art.server, title: "Updated title",
        coverSmall: art.coverSmall, coverLarge: art.coverLarge, screenshots: art.screenshots)
    _ = try await cache.attachArtwork(refreshed, to: imported)
    // A cover refresh must not invalidate an already selected Play action.
    #expect(try Data(contentsOf: await cache.verifiedFileURL(for: imported)) == syntheticROM())
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(imported)) as? [String: Any])
    object.removeValue(forKey: "artwork")
    let legacy = try JSONDecoder().decode(ImportedROM.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(legacy.artwork == nil)
    #expect(legacy.sha256 == imported.sha256)
}
