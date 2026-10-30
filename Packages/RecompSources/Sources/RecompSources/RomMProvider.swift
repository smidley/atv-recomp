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
            // Only platforms that hold a game Nativecade plays.
            let entries = Dictionary(grouping: try await playable(platformID: nil), by: \.platform_id)
                .map { id, roms -> LibraryEntry in
                    let name = roms[0].platform_display_name ?? "Platform \(id)"
                    return LibraryEntry(id: "platform-\(id)", name: name,
                                        detail: roms.count == 1 ? "1 game" : "\(roms.count) games", size: nil,
                                        target: .folder(.platform(id)), artwork: icon(name: name, slug: roms[0].platform_slug))
                }
                .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return LibraryPage(entries: entries, nextOffset: nil)
        case .platform(let id):
            guard id > 0, offset == 0 else { throw LibraryError.message("Invalid RomM platform.") }
            let entries = try await playable(platformID: id).map { rom in
                LibraryEntry(id: "rom-\(rom.id)", name: rom.name ?? rom.fs_name,
                             detail: "Open to choose a ROM file", size: nil, target: .folder(.rom(rom.id)),
                             artwork: artwork(id: rom.id, title: rom.name ?? rom.fs_name, media: rom.media))
            }
            return LibraryPage(entries: entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) },
                               nextOffset: nil)
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
        let filename = (rom.name as NSString).deletingPathExtension
        guard let candidates = try await allPages(search: filename, platformID: nil) else { return nil }
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

    /// Every catalog page for a search, or nil past 150 ROMs.
    private func allPages(search term: String, platformID: Int?, onePerGame: Bool = false) async throws -> [RomMItem]? {
        var items = [RomMItem]()
        var offset = 0
        while true {
            let page = try await catalog(platformID: platformID, search: term, offset: offset, onePerGame: onePerGame)
            items.append(contentsOf: page.items)
            guard let next = page.nextOffset else { return items }
            guard next < 150 else { return nil }
            offset = next
        }
    }

    /// Nintendo 64 ROMs titled like a game Nativecade plays, one search per game so
    /// servers without RomM 5.4's "|" alternatives also match.
    private func playable(platformID: Int?) async throws -> [RomMItem] {
        var found = [Int: RomMItem]()
        for game in SupportedGame.allCases {
            guard let roms = try await allPages(search: game.searchTerm, platformID: platformID, onePerGame: true) else {
                throw LibraryError.message("RomM returned too many matches for \(game.title).")
            }
            // A server that omits the platform slug keeps its matches. RomM also matches metadata
            // aliases, so Paper Mario can match "Super Mario 64"; the title or filename must contain it.
            for rom in roms where rom.platform_slug.map({ $0 == "n64" }) ?? true
                && [rom.name, rom.fs_name].contains(where: { $0?.localizedStandardContains(game.searchTerm) == true }) {
                found[rom.id] = rom
            }
        }
        return found.values.sorted {
            ($0.name ?? $0.fs_name).localizedStandardCompare($1.name ?? $1.fs_name) == .orderedAscending
        }
    }

    /// RomM's own platform icon, such as /assets/platforms/n64.ico. It belongs to no ROM.
    private func icon(name: String, slug: String?) -> RomMArtwork? {
        guard let slug, !slug.isEmpty else { return nil }
        let path = "/assets/platforms/\(slug.lowercased()).ico"
        guard (try? address.artworkURL(path)) != nil else { return nil }
        return RomMArtwork(romID: 0, server: address.base.absoluteString, title: name,
                           coverSmall: path, coverLarge: nil, screenshots: [])
    }

    private func catalog(platformID: Int?, search: String, offset: Int, onePerGame: Bool = false) async throws -> RomMPage {
        guard offset >= 0 else { throw LibraryError.message("Invalid page offset.") }
        var query = [
            URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "search_term", value: search),
            URLQueryItem(name: "with_char_index", value: "false"),
            URLQueryItem(name: "with_filter_values", value: "false"),
            URLQueryItem(name: "with_rom_id_index", value: "false"),
            URLQueryItem(name: "group_by_meta_id", value: String(onePerGame)),
            URLQueryItem(name: "order_by", value: "name"),
        ]
        // Like RomM's gallery, one record per metadata match. Records whose file is gone
        // are left out first, so the one shown can be downloaded.
        if onePerGame { query.append(URLQueryItem(name: "missing", value: "false")) }
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
    let platform_slug: String?
    let platform_display_name: String?
    let files: [RomMFile]?
    let media: RomMMedia

    enum CodingKeys: CodingKey { case id, name, fs_name, platform_id, platform_slug, platform_display_name, files }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        fs_name = try values.decode(String.self, forKey: .fs_name)
        platform_id = try values.decode(Int.self, forKey: .platform_id)
        platform_slug = try values.decodeIfPresent(String.self, forKey: .platform_slug)
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
