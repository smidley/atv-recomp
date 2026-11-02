import Foundation

/// A supported platform found on a server, with its ROM count when the server reports one.
public struct DetectedPlatform: Hashable, Sendable {
    public let platform: SupportedPlatform
    public let romCount: Int?
}

/// What Detect platforms found. serverPlatformCount is nil when the token can't list platforms.
public struct PlatformDetection: Hashable, Sendable {
    public let platforms: [DetectedPlatform]
    public let serverPlatformCount: Int?
}

/// A supported game a scan found on one connection. Its entries are what Add all imports:
/// more than one when the connection holds several copies and none is known to be supported.
public struct ScanCandidate: Identifiable, Equatable, Sendable {
    public let game: SupportedGame
    public let sourceID: UUID
    public let entries: [LibraryEntry]
    public var id: String { "\(sourceID)-\(game.rawValue)" }
    public var artwork: RomMArtwork? { entries.first?.artwork }
}

/// One platform's games on a connection, sorted by title, and how many of the platform's ROMs
/// there match no supported game (nil when unknown, as on an SMB share).
public struct PlatformScan: Equatable, Sendable {
    public var candidates: [ScanCandidate]
    public var unsupportedCount: Int?
}
