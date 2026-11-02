import Foundation

/// Whether guided setup has finished, and which platforms the library shows.
public struct LibrarySetup: Codable, Equatable, Sendable {
    public var complete: Bool
    public var platforms: Set<SupportedPlatform>

    public init(complete: Bool = false, platforms: Set<SupportedPlatform> = []) {
        self.complete = complete; self.platforms = platforms
    }

    /// Libraries from before guided setup skip it when they already have a connection or a game,
    /// with their games' platforms turned on (every platform while there are no games yet).
    public static func migrate(hasSources: Bool, games: [SupportedGame]) -> LibrarySetup {
        guard hasSources || !games.isEmpty else { return LibrarySetup() }
        let platforms = Set(games.map(\.platform))
        return LibrarySetup(complete: true, platforms: platforms.isEmpty ? Set(SupportedPlatform.allCases) : platforms)
    }
}
