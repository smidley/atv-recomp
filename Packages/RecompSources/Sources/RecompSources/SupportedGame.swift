import Foundation

public enum SupportedGame: String, Codable, Sendable, CaseIterable {
    case ocarinaOfTime
    case marioKart64
    case starFox64
    case superMario64
    case banjoKazooie
    case shadowsOfTheEmpire
    case episodeOneRacer
    case superSmashBros
    case cruisnUSA
    case cruisnWorld

    public var title: String {
        switch self {
        case .ocarinaOfTime: "The Legend of Zelda: Ocarina of Time"
        case .marioKart64: "Mario Kart 64"
        case .starFox64: "Star Fox 64"
        case .superMario64: "Super Mario 64"
        case .banjoKazooie: "Banjo-Kazooie"
        case .shadowsOfTheEmpire: "Star Wars: Shadows of the Empire"
        case .episodeOneRacer: "Star Wars Episode I: Racer"
        case .superSmashBros: "Super Smash Bros."
        case .cruisnUSA: "Cruis'n USA"
        case .cruisnWorld: "Cruis'n World"
        }
    }

    /// The library groups imported games by platform. Every supported game is a Nintendo 64 game so far.
    public var platform: String { "Nintendo 64" }

    /// Words in both the RomM metadata title and the No-Intro filename. Browsing uses
    /// them to hide other games; an import still verifies the exact revision.
    public var searchTerm: String {
        switch self {
        case .ocarinaOfTime: "Ocarina of Time"
        case .marioKart64: "Mario Kart 64"
        case .starFox64: "Star Fox 64"
        case .superMario64: "Super Mario 64"
        case .banjoKazooie: "Banjo-Kazooie"
        case .shadowsOfTheEmpire: "Shadows of the Empire"
        case .episodeOneRacer: "Episode I - Racer"
        case .superSmashBros: "Super Smash Bros"
        case .cruisnUSA: "Cruis'n USA"
        case .cruisnWorld: "Cruis'n World"
        }
    }

    var manifest: String {
        switch self {
        case .ocarinaOfTime: "shipwright-supported-roms"
        case .marioKart64: "spaghettikart-supported-roms"
        case .starFox64: "starship-supported-roms"
        case .superMario64: "ghostship-supported-roms"
        case .banjoKazooie: "lighthouse-supported-roms"
        case .shadowsOfTheEmpire: "sote-supported-roms"
        case .episodeOneRacer: "racer-supported-roms"
        case .superSmashBros: "battleship-supported-roms"
        case .cruisnUSA: "cruisn-usa-supported-roms"
        case .cruisnWorld: "cruisn-world-supported-roms"
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
