import Foundation

public enum SourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case smb, romm
    public var id: String { rawValue }
    public var title: String { self == .smb ? "SMB share" : "RomM" }
}

/// Secrets are deliberately excluded from source metadata.
public struct LibrarySource: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: SourceKind
    public var address: String
    public var username: String
    public var domain: String
    public var allowHTTP: Bool
    public var requireSMBEncryption: Bool

    public init(id: UUID = UUID(), name: String = "", kind: SourceKind = .smb,
                address: String = "", username: String = "", domain: String = "",
                allowHTTP: Bool = false, requireSMBEncryption: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.address = address
        self.username = username; self.domain = domain; self.allowHTTP = allowHTTP
        self.requireSMBEncryption = requireSMBEncryption
    }

    public func validate() throws {
        switch kind {
        case .smb: _ = try SMBAddress(address)
        case .romm: _ = try RomMAddress(address, allowHTTP: allowHTTP)
        }
    }
}

public enum LibraryLocation: Hashable, Sendable {
    case root
    case platform(Int)
    case directory(String)
    case rom(Int)
}

public struct LibraryEntry: Identifiable, Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case folder(LibraryLocation)
        case smbFile(String)
        case romFile(Int, String)
    }
    public let id: String
    public let name: String
    public let detail: String
    public let size: Int64?
    public let target: Target
    public var artwork: RomMArtwork? = nil
    public var folder: LibraryLocation? {
        if case .folder(let location) = target { return location }
        return nil
    }
    public var isROM: Bool { Self.isROMName(name) }
    public static func isROMName(_ name: String) -> Bool {
        ["z64", "v64", "n64"].contains((name as NSString).pathExtension.lowercased())
    }
}

public struct LibraryPage: Sendable {
    public let entries: [LibraryEntry]
    public let nextOffset: Int?
    public var artwork: RomMArtwork? = nil
}

/// Only server-owned artwork references, never a token or third-party image URL.
public struct RomMArtwork: Codable, Hashable, Sendable {
    public let romID: Int
    public let server: String
    public let title: String
    public let coverSmall: String?
    public let coverLarge: String?
    public let screenshots: [String]
    public var cover: String? { coverSmall ?? coverLarge }
    public func belongs(to source: LibrarySource) -> Bool {
        source.kind == .romm && (try? RomMAddress(source.address, allowHTTP: source.allowHTTP).base.absoluteString) == server
    }
}

public struct TransferProgress: Sendable {
    public let bytes: Int64
    public let total: Int64?
    public init(bytes: Int64, total: Int64?) { self.bytes = bytes; self.total = total }
}

public typealias ProgressHandler = @Sendable (TransferProgress) -> Void

public protocol LibraryProvider: Sendable {
    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage
    func download(_ entry: LibraryEntry, to destination: URL,
                  progress: @escaping ProgressHandler) async throws
    func imageData(at path: String) async throws -> Data
    func artwork(for rom: ImportedROM) async throws -> RomMArtwork?
}

public extension LibraryProvider {
    func imageData(at path: String) async throws -> Data {
        throw LibraryError.message("This source does not provide game artwork.")
    }
    func artwork(for rom: ImportedROM) async throws -> RomMArtwork? { nil }
}

public enum LibraryError: Error, LocalizedError, Equatable, Sendable {
    case message(String)
    case httpStatus(Int)
    public var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .httpStatus(401), .httpStatus(403):
            "RomM denied access. Check the API token and its roms.read permission."
        case .httpStatus(404):
            "RomM could not find this item. Refresh the library or check the instance URL."
        case .httpStatus(let code): "RomM returned HTTP \(code). Try again after checking the server."
        }
    }
}

/// Provider diagnostics may contain private server addresses; keep them out of UI reports.
public func userFacingNetworkError(_ error: any Error) -> String {
    if let error = error as? LibraryError { return error.localizedDescription }
    if let error = error as? URLError {
        switch error.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut:
            return "The server could not be reached. Check its address, network access and local-network permission, then retry."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed:
            return "The server's TLS connection could not be verified. Check its HTTPS certificate."
        default: return "The network transfer failed. Check the server and retry."
        }
    }
    return "The operation failed. Check the server, share name, account permissions and available storage, then retry."
}

public enum TransferLimits {
    public static let romBytes: Int64 = 64 * 1024 * 1024
    static let catalogBytes: Int64 = 8 * 1024 * 1024
    static func validateSize(_ size: Int64) throws {
        guard size >= 64, size <= romBytes, size % 4 == 0 else {
            throw LibraryError.message("Choose an uncompressed N64 ROM (.z64, .v64 or .n64), up to 64 MiB.")
        }
    }
}

public enum ProviderFactory {
    public static func make(source: LibrarySource, secret: String) throws -> any LibraryProvider {
        try source.validate()
        switch source.kind {
        case .smb: return try SMBProvider(source: source, password: secret)
        case .romm: return try RomMProvider(source: source, token: secret)
        }
    }
}

public enum SourceNotices {
    public static var license: String {
        guard let url = Bundle.module.url(forResource: "AMSMB2-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "AMSMB2 / libsmb2 · GNU Lesser General Public License 2.1. See the repository's network sources guide."
        }
        return "AMSMB2 4.0.3 / libsmb2\nSource: https://github.com/amosavian/AMSMB2/tree/4.0.3\n\n" + text
    }
}
