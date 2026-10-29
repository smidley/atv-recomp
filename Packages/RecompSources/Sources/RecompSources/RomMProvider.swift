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
            guard offset == 0 else { throw LibraryError.message("Invalid platform page.") }
            let platforms = try await platforms()
            let entries = platforms.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .map { platform in
                    LibraryEntry(id: "platform-\(platform.id)", name: platform.title,
                                 detail: platform.rom_count == 1 ? "1 ROM" : "\(platform.rom_count) ROMs", size: nil,
                                 target: .folder(.platform(platform.id)))
                }
            return LibraryPage(entries: entries, nextOffset: nil)
        case .platform(let id):
            guard id > 0 else { throw LibraryError.message("Invalid RomM platform.") }
            let page = try await catalog(platformID: id, search: search, offset: offset)
            let entries = page.items.map { rom in
                LibraryEntry(id: "rom-\(rom.id)", name: rom.name ?? rom.fs_name,
                             detail: "Open to choose a ROM file", size: nil, target: .folder(.rom(rom.id)),
                             artwork: artwork(id: rom.id, title: rom.name ?? rom.fs_name, media: rom.media))
            }
            return LibraryPage(entries: entries, nextOffset: page.nextOffset)
        case .rom(let id):
            guard id > 0 else { throw LibraryError.message("Invalid RomM item.") }
            let rom = try await decode(RomMDetail.self, path: ["roms", String(id)])
            guard rom.id == id, Set(rom.files.map(\.id)).count == rom.files.count else {
                throw LibraryError.message("RomM returned inconsistent file metadata. Refresh the catalog.")
            }
            let artwork = artwork(id: id, title: rom.name ?? rom.files.first?.file_name ?? "Game", media: rom.media)
            let entries = try rom.files.map { file in
                try validateComponent(file.file_name)
                guard file.id > 0, file.file_size_bytes >= 0 else {
                    throw LibraryError.message("RomM returned invalid file metadata.")
                }
                return LibraryEntry(id: "file-\(file.id)", name: file.file_name,
                                    detail: LibraryEntry.isROMName(file.file_name) ? "Unverified N64 ROM" : "Uncompressed N64 ROM required",
                                    size: file.file_size_bytes, target: .romFile(file.id, file.file_name), artwork: artwork)
            }
            return LibraryPage(entries: entries, nextOffset: nil, artwork: artwork)
        case .directory: throw LibraryError.message("This location does not belong to RomM.")
        }
    }

    private func artwork(id: Int, title: String, media: RomMMedia) -> RomMArtwork {
        func safe(_ value: String?) -> String? {
            guard let value, !value.isEmpty, (try? address.artworkURL(value)) != nil else { return nil }
            return value
        }
        var seen = Set<String>()
        return RomMArtwork(romID: id, server: address.base.absoluteString, title: title,
                           coverSmall: safe(media.small), coverLarge: safe(media.large),
                           screenshots: media.screenshots.compactMap(safe).filter { seen.insert($0).inserted }.prefix(12).map { $0 })
    }

    func imageData(at path: String) async throws -> Data {
        var request = URLRequest(url: try address.artworkURL(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await HTTPTransfer(limit: ArtworkCache.downloadLimit, resourceTimeout: 15)
            .run(request, configuration: configuration())
    }

    func artwork(for rom: ImportedROM) async throws -> RomMArtwork? {
        if let existing = rom.artwork, existing.server == address.base.absoluteString {
            return try await list(.rom(existing.romID), search: "", offset: 0).artwork
        }
        // Older cache records predate ROM IDs. Match one exact filename and size,
        // rather than guessing a cover from a similar game title. Ambiguity is left alone.
        let search = (rom.name as NSString).deletingPathExtension
        var candidates = [RomMItem]()
        var offset = 0
        repeat {
            let page = try await catalog(platformID: nil, search: search, offset: offset)
            candidates.append(contentsOf: page.items)
            guard let next = page.nextOffset else { break }
            guard next < 150 else { return nil }
            offset = next
        } while true
        var matches = [RomMArtwork]()
        for candidate in candidates {
            try Task.checkCancellation()
            // RomM 5.4.1 lists files only with with_files=true and otherwise sends an
            // empty list; older servers omit the field. Both fall back to the detail endpoint.
            let files: [RomMFile]
            if let included = candidate.files, !included.isEmpty { files = included }
            else {
                files = try await decode(RomMDetail.self, path: ["roms", String(candidate.id)]).files
            }
            if files.contains(where: { $0.file_name == rom.name && $0.file_size_bytes == rom.size }) {
                matches.append(artwork(id: candidate.id, title: candidate.name ?? candidate.fs_name, media: candidate.media))
                if matches.count > 1 { return nil }
            }
        }
        return matches.first
    }

    private func catalog(platformID: Int?, search: String, offset: Int) async throws -> RomMPage {
        guard offset >= 0 else { throw LibraryError.message("Invalid page offset.") }
        var query = [
            URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "search_term", value: search),
            URLQueryItem(name: "with_char_index", value: "false"),
            URLQueryItem(name: "with_filter_values", value: "false"),
            URLQueryItem(name: "with_rom_id_index", value: "false"),
            URLQueryItem(name: "group_by_meta_id", value: "false"),
            URLQueryItem(name: "order_by", value: "name"),
        ]
        if let platformID { query.append(URLQueryItem(name: "platform_ids", value: String(platformID))) }
        let page = try await decode(RomMPage.self, path: ["roms"], query: query)
        guard page.offset == offset, page.total >= 0, page.items.count <= 50,
              page.items.allSatisfy({ $0.id > 0 && $0.platform_id > 0 && (platformID == nil || $0.platform_id == platformID) }),
              Set(page.items.map(\.id)).count == page.items.count,
              !page.items.isEmpty || offset >= page.total else {
            throw LibraryError.message("RomM returned an invalid catalog page. Refresh the library.")
        }
        return page
    }

    private func platforms() async throws -> [RomMPlatform] {
        do {
            let platforms = try await decode([RomMPlatform].self, path: ["platforms"])
            guard platforms.allSatisfy({ $0.id > 0 && $0.rom_count >= 0 }),
                  Set(platforms.map(\.id)).count == platforms.count else {
                throw LibraryError.message("RomM returned an invalid platform list.")
            }
            return platforms
        } catch LibraryError.httpStatus(let code) where code == 403 || code == 404 {
            // Existing roms.read-only tokens remain usable. Group every metadata page
            // when the optional platforms.read endpoint is unavailable.
            var groups = [Int: RomMPlatform]()
            var seen = Set<Int>()
            var offset = 0
            while true {
                try Task.checkCancellation()
                let page = try await catalog(platformID: nil, search: "", offset: offset)
                for rom in page.items where seen.insert(rom.id).inserted {
                    var group = groups[rom.platform_id] ?? RomMPlatform(
                        id: rom.platform_id, name: rom.platform_display_name ?? "Platform \(rom.platform_id)",
                        display_name: nil, custom_name: nil, rom_count: 0)
                    group.rom_count += 1
                    groups[rom.platform_id] = group
                }
                guard let next = page.nextOffset else { return Array(groups.values) }
                guard next > offset, next <= 100_000 else {
                    throw LibraryError.message("The platform catalog is too large to scan. Enable platforms.read on the token.")
                }
                offset = next
            }
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
    var nextOffset: Int? {
        let next = offset + items.count
        return !items.isEmpty && next < total ? next : nil
    }
}
private struct RomMItem: Decodable {
    let id: Int
    let name: String?
    let fs_name: String
    let platform_id: Int
    let platform_display_name: String?
    let files: [RomMFile]?
    let media: RomMMedia

    enum CodingKeys: CodingKey { case id, name, fs_name, platform_id, platform_display_name, files }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        fs_name = try values.decode(String.self, forKey: .fs_name)
        platform_id = try values.decode(Int.self, forKey: .platform_id)
        platform_display_name = try values.decodeIfPresent(String.self, forKey: .platform_display_name)
        files = try values.decodeIfPresent([RomMFile].self, forKey: .files)
        media = try RomMMedia(from: decoder)
    }
}
private struct RomMDetail: Decodable {
    let id: Int
    let name: String?
    let files: [RomMFile]
    let media: RomMMedia
    enum CodingKeys: CodingKey { case id, name, files }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        files = try values.decode([RomMFile].self, forKey: .files)
        media = try RomMMedia(from: decoder)
    }
}
private struct RomMMedia: Decodable {
    let small: String?
    let large: String?
    let screenshots: [String]
    enum CodingKeys: CodingKey { case path_cover_small, path_cover_large, merged_screenshots }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Bad or missing artwork metadata must not make a ROM impossible to browse.
        small = try? values.decode(String.self, forKey: .path_cover_small)
        large = try? values.decode(String.self, forKey: .path_cover_large)
        screenshots = (try? values.decode([String].self, forKey: .merged_screenshots)) ?? []
    }
}
private struct RomMFile: Decodable {
    let id: Int
    let file_name: String
    let file_size_bytes: Int64
}

private struct RomMPlatform: Decodable {
    let id: Int
    let name: String
    let display_name: String?
    let custom_name: String?
    var rom_count: Int
    var title: String {
        for value in [display_name, custom_name, name] {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return "Platform \(id)"
    }
}
