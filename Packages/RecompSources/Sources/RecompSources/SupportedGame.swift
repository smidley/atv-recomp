import Foundation

public enum SupportedGame: String, Codable, Sendable, CaseIterable {
    case ocarinaOfTime
    case marioKart64

    public var title: String {
        switch self {
        case .ocarinaOfTime: "The Legend of Zelda: Ocarina of Time"
        case .marioKart64: "Mario Kart 64"
        }
    }

    var manifest: String {
        switch self {
        case .ocarinaOfTime: "shipwright-supported-roms"
        case .marioKart64: "spaghettikart-supported-roms"
        }
    }

    /// Runtime selection uses the normalized ROM identity, never a filename or
    /// mutable server title. Existing Ocarina cache records need no migration.
    public static func identify(sha1: String) -> SupportedGame? {
        identities[sha1.lowercased()]
    }

    private static let identities: [String: SupportedGame] = {
        var result = [String: SupportedGame]()
        for game in allCases {
            guard let revisions = try? game.revisions() else { continue }
            for revision in revisions { result[revision.sha1] = game }
        }
        return result
    }()

    func revisions() throws -> [ROMRevision] {
        guard let url = Bundle.module.url(forResource: manifest, withExtension: "json") else {
            throw LibraryError.message("The \(title) ROM manifest is missing from this app build.")
        }
        return try JSONDecoder().decode([ROMRevision].self, from: Data(contentsOf: url))
    }
}

struct ROMRevision: Decodable, Sendable { let name: String; let sha1: String }
