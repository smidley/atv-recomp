import Foundation
import Testing
@testable import RecompSources

@Test func addressesPreserveProxyAndShareRoots() throws {
    let romm = try RomMAddress("https://example.test/games/api/", allowHTTP: false)
    let endpoint = try romm.endpoint(["roms", "7", "files", "content", "Zelda (USA) #1.z64"])
    #expect(endpoint.path == "/games/api/roms/7/files/content/Zelda (USA) #1.z64")
    #expect(endpoint.fragment == nil)
    let smb = try SMBAddress("smb://nas.local:1445/Games/N64%20ROMs")
    #expect(smb.share == "Games")
    #expect(smb.root == "N64 ROMs")
    #expect(smb.server.port == 1445)
    #expect(try smb.path(.root) == "N64 ROMs")
    #expect(throws: (any Error).self) { try smb.path(.directory("Other/file.z64")) }
    #expect(throws: (any Error).self) { try smb.child("../file.z64", in: smb.root) }
}

@Test(arguments: ["smb://host", "smb://user:password@host/share", "smb://host/share/../outside",
                  "smb://host/share/%2e%2e/outside", "smb://host/share?token=secret", "file:///share"])
func badShareAddressesFail(_ input: String) {
    #expect(throws: (any Error).self) { try SMBAddress(input) }
}

@Test func httpRequiresExplicitChoiceAndSecretsAreNotMetadata() throws {
    #expect(throws: (any Error).self) { try RomMAddress("http://nas:8080", allowHTTP: false) }
    _ = try RomMAddress("http://nas:8080", allowHTTP: true)
    #expect(throws: (any Error).self) { try RomMAddress("https://u:p@host", allowHTTP: false) }
    let source = LibrarySource(name: "NAS", address: "smb://nas/games", username: "player")
    let encoded = try JSONEncoder().encode(source)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["password"] == nil)
    #expect(object["token"] == nil)
    #expect(object["secret"] == nil)
}

func temporaryFolder() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func syntheticROM() -> Data {
    var bytes = [UInt8](repeating: 0, count: 256 * 1024)
    for index in bytes.indices { bytes[index] = UInt8(index % 251) }
    bytes.replaceSubrange(0..<4, with: [0x80, 0x37, 0x12, 0x40])
    return Data(bytes)
}

@Test func allByteOrdersHaveTheSameIdentityAndCanonicalOutput() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let canonical = syntheticROM()
    var identities = [ROMIdentity]()
    for width in [1, 2, 4] {
        var bytes = [UInt8](canonical)
        if width > 1 {
            for index in stride(from: 0, to: bytes.count, by: width) {
                bytes.replaceSubrange(index..<(index + width), with: bytes[index..<(index + width)].reversed())
            }
        }
        let input = folder.appendingPathComponent("input-\(width)")
        let output = folder.appendingPathComponent("output-\(width)")
        try Data(bytes).write(to: input)
        identities.append(try ROMIdentity.read(input, normalizedOutput: output))
        #expect(try Data(contentsOf: output) == canonical)
    }
    #expect(identities[0] == identities[1])
    #expect(identities[0] == identities[2])
}

@Test func malformedROMsAndCancellationFail() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("input")
    for data in [Data("<html>login page</html>".utf8), Data(repeating: 0, count: 64), syntheticROM().dropLast()] {
        try data.write(to: file)
        #expect(throws: (any Error).self) { try ROMIdentity.read(file) }
    }
}

private struct FixtureProvider: LibraryProvider {
    let bytes: Data
    var fail = false
    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage {
        LibraryPage(entries: [], nextOffset: nil)
    }
    func download(_ entry: LibraryEntry, to destination: URL, progress: @escaping ProgressHandler) async throws {
        try bytes.write(to: destination)
        if fail { throw CancellationError() }
    }
}

@Test func cachePromotesOnlyAcceptedCompleteTransfersAndDetectsCorruption() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let fixture = folder.appendingPathComponent("fixture")
    let bytes = syntheticROM()
    try bytes.write(to: fixture)
    let identity = try ROMIdentity.read(fixture)
    let cacheFolder = folder.appendingPathComponent("cache")
    let cache = try ROMCache(root: cacheFolder, revisions: [identity.sha1: "Synthetic fixture"])
    let entry = LibraryEntry(id: "test", name: "Test.z64", detail: "", size: Int64(bytes.count), target: .smbFile("Test.z64"))
    let id = UUID()
    let result = try await cache.acquire(entry, sourceID: id, provider: FixtureProvider(bytes: bytes), progress: { _ in })
    #expect(result.recognized)
    #expect(!result.launchable)
    #expect(try await cache.current() == result)
    await #expect(throws: CancellationError.self) {
        try await cache.acquire(entry, sourceID: id, provider: FixtureProvider(bytes: bytes, fail: true), progress: { _ in })
    }
    #expect(try await cache.current() == result)
    var unknown = bytes; unknown[12] ^= 1
    let rejected = try await cache.acquire(entry, sourceID: id, provider: FixtureProvider(bytes: unknown), progress: { _ in })
    #expect(!rejected.recognized)
    #expect(try await cache.current() == result)
    #expect(try FileManager.default.contentsOfDirectory(atPath: cacheFolder.path).filter { $0.hasSuffix(".partial") }.isEmpty)
    try unknown.write(to: cacheFolder.appendingPathComponent(result.sha256 + ".romdata"))
    #expect(try await cache.current() == nil)
    try await cache.clear()
    #expect(try await cache.current() == nil)
}

@Test func smbSinkRejectsSizeChangesAndShortTransfers() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sink = try SMBFileSink(destination: folder.appendingPathComponent("partial"), size: 64, progress: { _ in })
    #expect(!sink.append(Data(repeating: 0, count: 65), offset: 0, total: 65))
    #expect(throws: (any Error).self) { try sink.finish(nil).get() }
    let short = try SMBFileSink(destination: folder.appendingPathComponent("short"), size: 64, progress: { _ in })
    #expect(short.append(Data(repeating: 0, count: 32), offset: 0, total: 64))
    #expect(throws: (any Error).self) { try short.finish(nil).get() }
    let cancelled = try SMBFileSink(destination: folder.appendingPathComponent("cancelled"), size: 64, progress: { _ in })
    cancelled.cancel()
    #expect(!cancelled.append(Data(repeating: 0, count: 64), offset: 0, total: 64))
    #expect(throws: CancellationError.self) { try cancelled.finish(nil).get() }
}
