import Foundation

struct RomMProvider: LibraryProvider {
    private let address: RomMAddress
    private let token: String
    // A factory keeps URLSessionConfiguration from crossing concurrency boundaries.
    private let configuration: @Sendable () -> URLSessionConfiguration

    init(source: LibrarySource, token: String,
         configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) throws {
        address = try RomMAddress(source.address, allowHTTP: source.allowHTTP)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LibraryError.message("Enter a RomM Client API token with roms.read permission.")
        }
        self.token = token; self.configuration = configuration
    }

    private func request(_ path: [String], query: [URLQueryItem] = []) throws -> URLRequest {
        var request = URLRequest(url: try address.endpoint(path, query: query))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, path: [String], query: [URLQueryItem] = []) async throws -> T {
        let data = try await HTTPTransfer(limit: TransferLimits.catalogBytes)
            .run(request(path, query: query), configuration: configuration())
        try Task.checkCancellation()
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw LibraryError.message("The server did not return the expected RomM API response. Check the instance URL and version.") }
    }

    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage {
        switch location {
        case .root:
            guard offset >= 0 else { throw LibraryError.message("Invalid page offset.") }
            let query = [
                URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "search_term", value: search),
                URLQueryItem(name: "with_char_index", value: "false"),
                URLQueryItem(name: "with_filter_values", value: "false"),
                URLQueryItem(name: "with_rom_id_index", value: "false"),
                URLQueryItem(name: "order_by", value: "name"),
            ]
            let page = try await decode(RomMPage.self, path: ["roms"], query: query)
            guard page.offset == offset, page.items.count <= 50,
                  page.items.allSatisfy({ $0.id > 0 }), Set(page.items.map(\.id)).count == page.items.count else {
                throw LibraryError.message("RomM returned an invalid catalog page.")
            }
            let entries = page.items.map { rom in
                LibraryEntry(id: "rom-\(rom.id)", name: rom.name ?? rom.fs_name,
                             detail: rom.platform_display_name ?? "Open to choose a ROM file",
                             size: nil, target: .folder(.rom(rom.id)))
            }
            let next = offset + page.items.count
            return LibraryPage(entries: entries, nextOffset: !entries.isEmpty && next < page.total ? next : nil)
        case .rom(let id):
            guard id > 0 else { throw LibraryError.message("Invalid RomM item.") }
            let rom = try await decode(RomMDetail.self, path: ["roms", String(id)])
            guard rom.id == id, Set(rom.files.map(\.id)).count == rom.files.count else {
                throw LibraryError.message("RomM returned inconsistent file metadata. Refresh the catalog.")
            }
            let entries = try rom.files.map { file in
                try validateComponent(file.file_name)
                guard file.id > 0, file.file_size_bytes >= 0 else {
                    throw LibraryError.message("RomM returned invalid file metadata.")
                }
                return LibraryEntry(id: "file-\(file.id)", name: file.file_name,
                                    detail: LibraryEntry.isROMName(file.file_name) ? "Unverified N64 ROM" : "Uncompressed N64 ROM required",
                                    size: file.file_size_bytes, target: .romFile(file.id, file.file_name))
            }
            return LibraryPage(entries: entries, nextOffset: nil)
        case .directory: throw LibraryError.message("This location does not belong to RomM.")
        }
    }

    func download(_ entry: LibraryEntry, to destination: URL, progress: @escaping ProgressHandler) async throws {
        guard case .romFile(let id, let filename) = entry.target, id > 0, entry.isROM, let size = entry.size else {
            throw LibraryError.message("Select an uncompressed N64 ROM file.")
        }
        try TransferLimits.validateSize(size)
        // This endpoint takes a FILE id, not the catalog ROM id, and never implicitly zips siblings.
        _ = try await HTTPTransfer(limit: size, destination: destination, progress: progress)
            .run(request(["roms", String(id), "files", "content", filename]), configuration: configuration())
        try Task.checkCancellation()
        let actual = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard actual.map(Int64.init) == size else {
            throw LibraryError.message("The ROM size changed. Refresh the catalog and retry.")
        }
    }
}

private struct RomMPage: Decodable {
    let items: [RomMItem]
    let total: Int
    let offset: Int
}
private struct RomMItem: Decodable {
    let id: Int
    let name: String?
    let fs_name: String
    let platform_display_name: String?
}
private struct RomMDetail: Decodable {
    let id: Int
    let files: [RomMFile]
}
private struct RomMFile: Decodable {
    let id: Int
    let file_name: String
    let file_size_bytes: Int64
}
