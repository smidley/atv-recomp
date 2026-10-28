import Foundation
import Testing
@testable import RecompSources

@Suite(.enabled(if: ProcessInfo.processInfo.environment["RECOMPTV_NETWORK_FIXTURES"] == "1"), .serialized)
struct NetworkTests {
    private func romm(_ prefix: String = "") throws -> RomMProvider {
        try RomMProvider(source: LibrarySource(kind: .romm, address: "http://127.0.0.1:18080\(prefix)", allowHTTP: true), token: "fixture-token")
    }

    @Test func rommBrowsePaginationAndIndividualFileDownload() async throws {
        let provider = try romm()
        let first = try await provider.list(.root, search: "Ocarina & Zelda", offset: 0)
        #expect(first.entries.count == 1)
        #expect(first.nextOffset == 1)
        let next = try await provider.list(.root, search: "", offset: 1)
        #expect(next.nextOffset == nil)
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
