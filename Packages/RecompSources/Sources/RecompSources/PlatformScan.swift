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

/// A connection to scan, with the name a failure message uses.
public struct ScanConnection: Sendable {
    public let name: String
    public let provider: any LibraryProvider
    public init(name: String, provider: any LibraryProvider) { self.name = name; self.provider = provider }
}

/// Every connection's scan of one platform, merged, and what couldn't be scanned.
public struct ScanReport: Sendable {
    public var scan: PlatformScan
    public var failures: [String]
}

public enum PlatformScanner {
    /// Scans the connections in order. Each game appears once, from the first connection that has
    /// it, and the known counts add up. A connection that fails is named; the others still count.
    public static func scan(_ platform: SupportedPlatform, connections: [ScanConnection]) async -> ScanReport {
        var candidates = [SupportedGame: ScanCandidate]()
        var unsupported: Int?
        var failures = [String]()
        for connection in connections {
            guard !Task.isCancelled else { break }
            do {
                let scan = try await connection.provider.scan(platform)
                for candidate in scan.candidates where candidates[candidate.game] == nil { candidates[candidate.game] = candidate }
                if let count = scan.unsupportedCount { unsupported = (unsupported ?? 0) + count }
            } catch {
                if Task.isCancelled || error is CancellationError { break }
                failures.append("Couldn't scan \(connection.name). \(userFacingNetworkError(error))")
            }
        }
        let sorted = candidates.values.sorted { $0.game.title.localizedStandardCompare($1.game.title) == .orderedAscending }
        return ScanReport(scan: PlatformScan(candidates: sorted, unsupportedCount: unsupported), failures: failures)
    }
}
