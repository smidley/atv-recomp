import Foundation
import RecompSources

enum GameRuntime {
    static var available: Bool {
        #if NATIVECADE_RUNTIME
        true
        #else
        false
        #endif
    }
}

/// Serial isolation keeps Torch's process-wide extraction state off the main actor.
/// The native call is synchronous CPU work; it never touches the UI or credentials.
actor GamePreparation {
    func prepare(_ rom: ImportedROM, cache: ROMCache) async throws {
        #if NATIVECADE_RUNTIME
        let url = try await cache.verifiedFileURL(for: rom)
        guard let game = rom.game else { throw LibraryError.message("This ROM does not have a playable runtime yet.") }
        try Task.checkCancellation()
        var message = [CChar](repeating: 0, count: 512)
        let prepared = url.path.withCString { path in
            rom.sha1.withCString { hash in
                switch game {
                case .ocarinaOfTime: NativecadePrepareGame(path, hash, &message, 512)
                case .marioKart64: NativecadePrepareMarioKart(path, hash, &message, 512)
                case .starFox64: NativecadePrepareStarFox(path, hash, &message, 512)
                case .superMario64: NativecadePrepareSuperMario(path, hash, &message, 512)
                case .banjoKazooie: NativecadePrepareBanjoKazooie(path, hash, &message, 512)
                case .shadowsOfTheEmpire: NativecadePrepareShadowsOfTheEmpire(path, hash, &message, 512)
                }
            }
        }
        guard prepared else {
            throw LibraryError.message(String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        #else
        throw LibraryError.message("Open the Nativecade app to play this ROM.")
        #endif
    }

    @MainActor static func launch() throws {
        #if NATIVECADE_RUNTIME
        guard NativecadeLaunchPreparedGame() else {
            throw LibraryError.message("The game could not start. Try Play again.")
        }
        #else
        throw LibraryError.message("Open the Nativecade app to play this ROM.")
        #endif
    }
}
