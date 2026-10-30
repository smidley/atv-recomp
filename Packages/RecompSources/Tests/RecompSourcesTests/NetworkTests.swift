import Foundation
import Testing
@testable import RecompSources

@Suite(.enabled(if: ProcessInfo.processInfo.environment["RECOMPTV_NETWORK_FIXTURES"] == "1"), .serialized)
struct NetworkTests {
    private func romm(_ prefix: String = "") throws -> RomMProvider {
        try RomMProvider(source: LibrarySource(kind: .romm, address: "http://127.0.0.1:18080\(prefix)", allowHTTP: true), token: "fixture-token")
    }

    @Test func rommBrowsesOnlyPlayableGamesAcrossPagesAndDownloadsIndividualFiles() async throws {
        let provider = try romm()
        // The fixture serves one ROM per page. The 3DS title, the other N64 game, the second
        // Ocarina record and the Mario Kart record whose file is gone all stay hidden.
        let platforms = try await provider.list(.root, search: "", offset: 0)
        #expect(platforms.entries.map(\.name) == ["Nintendo 64"])
        #expect(platforms.entries.first?.detail == "2 games")
        #expect(platforms.entries.first?.folder == .platform(1))
        #expect(platforms.entries.first?.artwork?.cover == "/assets/platforms/n64.ico")
        #expect(try await provider.list(.root, search: "3ds", offset: 0).entries.isEmpty)
        let games = try await provider.list(.platform(1), search: "", offset: 0)
        #expect(games.entries.map(\.name) == ["Mario Kart 64 fixture", "Synthetic Ocarina of Time fixture"])
        #expect(games.nextOffset == nil)
        #expect(try await provider.list(.platform(1), search: "kart", offset: 0).entries.map(\.folder) == [.rom(4)])
        let files = try await provider.list(.rom(3), search: "", offset: 0)
        let rom = try #require(files.entries.first { $0.isROM })
        #expect(rom.target == .romFile(11, "Fixture.z64"))
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let downloaded = folder.appendingPathComponent("download")
        try await provider.download(rom, to: downloaded, progress: { _ in })
        #expect(try Data(contentsOf: downloaded) == syntheticROM())
        let archive = try #require(files.entries.first { !$0.isROM })
        await #expect(throws: (any Error).self) { try await provider.download(archive, to: downloaded, progress: { _ in }) }
    }

    @Test func rommArtworkUsesAuthenticatedResourcesAndSurvivesOffline() async throws {
        let provider = try romm("/art-proxy")
        let page = try await provider.list(.platform(1), search: "", offset: 0)
        let art = try #require(page.entries.first { $0.folder == .rom(3) }?.artwork)
        #expect(art.romID == 3)
        #expect(art.screenshots.count == 1) // A third-party URL must never receive the token.
        let files = try await provider.list(.rom(3), search: "", offset: 0)
        #expect(files.artwork?.title == "Synthetic Ocarina of Time fixture")
        #expect(files.entries.first?.artwork == files.artwork)
        let path = try #require(art.cover)
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try ArtworkCache(root: root), id = UUID()
        let image = try await cache.image(at: path, artwork: art, sourceID: id, provider: provider)
        #expect(!image.isEmpty)
        #expect(try await cache.image(at: path, artwork: art, sourceID: id, provider: nil) == image)
        let icon = try #require(try await provider.list(.root, search: "", offset: 0).entries.first?.artwork)
        let decoded = try await cache.image(at: try #require(icon.cover), artwork: icon, sourceID: id, provider: provider)
        #expect(decoded.starts(with: [0x89, 0x50, 0x4e, 0x47])) // The .ico was decoded and stored as PNG.
        await #expect(throws: LibraryError.self) {
            try await provider.imageData(at: "/assets/romm/resources/redirect.png")
        }
        await #expect(throws: LibraryError.self) {
            try await cache.image(at: "/assets/romm/resources/login.png", artwork: art, sourceID: id, provider: provider)
        }
        let legacy = ImportedROM(name: "Fixture.z64", revision: "Fixture", sha1: "", sha256: "", size: 256 * 1024, sourceID: id)
        #expect(try await provider.artwork(for: legacy)?.romID == 3)
    }

    @Test func platformBatchVisitsEveryCatalogPageAndSkipsArchives() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = await ROMBatchImporter.run(location: .platform(1), sourceID: UUID(),
            provider: try romm(), cache: try ROMCache(root: folder), progress: { _ in })
        #expect(report.failure == nil)
        #expect(report.discoveryComplete)
        #expect(report.total == 3)
        #expect(report.count(.unsupported) == 2)
        #expect(report.count(.skipped) == 1)
        #expect(!report.results.contains { ["Other.3ds", "Third.z64"].contains($0.name) })
    }

    @Test func deniedAccessAndRedirectsFailWithoutForwardingToken() async throws {
        for prefix in ["/unauthorized", "/redirect"] {
            let provider = try romm(prefix)
            await #expect(throws: LibraryError.self) { try await provider.list(.root, search: "", offset: 0) }
        }
        let url = try #require(URL(string: "http://127.0.0.1:18080/trap-count"))
        let (data, _) = try await URLSession.shared.data(from: url)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Int])
        #expect(payload["hits"] == 0)
    }

    @Test func oversizedAndChunkedBodiesAreBoundedAndTransferCancels() async throws {
        func request(_ path: String) throws -> URLRequest {
            var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:18080/\(path)")))
            request.setValue("Bearer fixture-token", forHTTPHeaderField: "Authorization")
            return request
        }
        for path in ["oversized", "chunked"] {
            let request = try request(path)
            await #expect(throws: LibraryError.self) { try await HTTPTransfer(limit: 128).run(request) }
        }
        let slow = try request("slow")
        let download = Task { try await HTTPTransfer(limit: TransferLimits.romBytes).run(slow) }
        try await Task.sleep(for: .milliseconds(100))
        download.cancel()
        await #expect(throws: (any Error).self) { try await download.value }
    }

    @Test func smbAuthenticatesBrowsesFoldersAndStreamsROM() async throws {
        let source = LibrarySource(address: "smb://127.0.0.1:1445/GAMES", username: "player")
        let provider = try SMBProvider(source: source, password: "fixture-password")
        let page = try await provider.list(.root, search: "", offset: 0)
        #expect(page.entries.count == 2)
        let folderEntry = try #require(page.entries.first { $0.folder != nil })
        let folderLocation = try #require(folderEntry.folder)
        let nested = try await provider.list(folderLocation, search: "", offset: 0)
        #expect(nested.entries.map(\.name) == ["Fixture.v64"])
        let entry = try #require(page.entries.first { $0.isROM })
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("download")
        try await provider.download(entry, to: file, progress: { _ in })
        #expect(try Data(contentsOf: file) == syntheticROM())
        let wrong = try SMBProvider(source: source, password: "wrong")
        await #expect(throws: (any Error).self) { try await wrong.list(.root, search: "", offset: 0) }
    }
}
