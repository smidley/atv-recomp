#if DEBUG && targetEnvironment(simulator)
import Foundation
import RecompSources

/// Opt-in CI probe: fixed loopback endpoints and synthetic data only. No launch argument can
/// supply a remote host, credential, or accepted-ROM hash. Excluded from release/device builds.
@MainActor enum SourceSimulatorProbe {
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--source-fixture-probe"),
              let runID = ProcessInfo.processInfo.environment["RECOMPTV_PROBE_ID"] else { return }
        var steps = [String]()
        do {
            let credentialID = UUID()
            defer { try? CredentialStore.remove(credentialID) }
            try CredentialStore.save("synthetic-keychain-secret", for: credentialID)
            guard try CredentialStore.load(credentialID) == "synthetic-keychain-secret" else {
                throw LibraryError.message("Keychain round trip failed.")
            }
            try CredentialStore.remove(credentialID)
            guard try CredentialStore.load(credentialID).isEmpty else {
                throw LibraryError.message("Keychain removal failed.")
            }
            steps.append("keychain")
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-probe-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let cache = try ROMCache(root: root)
            let sources: [(LibrarySource, String)] = [
                (LibrarySource(kind: .romm, address: "http://127.0.0.1:18080", allowHTTP: true), "fixture-token"),
                (LibrarySource(address: "smb://127.0.0.1:1445/GAMES", username: "player"), "fixture-password"),
            ]
            for (source, secret) in sources {
                let provider = try ProviderFactory.make(source: source, secret: secret)
                let page = try await provider.list(.root, search: "", offset: 0)
                let files: LibraryPage
                if source.kind == .romm { files = try await provider.list(.rom(3), search: "", offset: 0) }
                else { files = page }
                guard let entry = files.entries.first(where: { $0.isROM }) else {
                    throw LibraryError.message("The fixture ROM was not listed.")
                }
                if source.kind == .romm {
                    guard let artwork = entry.artwork, let cover = artwork.cover, artwork.screenshots.count == 1 else {
                        throw LibraryError.message("RomM artwork metadata was not decoded safely.")
                    }
                    let images = try ArtworkCache(root: root.appendingPathComponent("images"))
                    let data = try await images.image(at: cover, artwork: artwork, sourceID: source.id, provider: provider)
                    let offline = try await images.image(at: cover, artwork: artwork, sourceID: source.id, provider: nil)
                    guard data.starts(with: [0x89, 0x50, 0x4e, 0x47]), data == offline else {
                        throw LibraryError.message("Artwork did not decode or survive an offline cache read.")
                    }
                    steps.append("romm-artwork")
                }
                let result = try await cache.acquire(entry, sourceID: source.id, provider: provider, progress: { _ in })
                guard result.sha256 == "92a2313a5151db3e56f5386dd2714fcb01f6023fdd6e50d5bbd223fcf491f9c0",
                      !result.recognized, !result.launchable, try await cache.current() == nil else {
                    throw LibraryError.message("Synthetic ROM identity or cache eligibility was incorrect.")
                }
                steps.append(source.kind.rawValue)
            }
            // Exercise the observable UI model as well as the package queue: in-place
            // updates of an optional observed report must not overlap reads/writes.
            let batchSource = sources[0].0
            try CredentialStore.save(sources[0].1, for: batchSource.id)
            defer { try? CredentialStore.remove(batchSource.id) }
            let library = LibraryModel(cache: cache)
            library.acquireAll(in: .platform(1), title: "Fixture N64", source: batchSource)
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while library.isImporting && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard !library.isImporting, let report = library.batchReport,
                  report.discoveryComplete, report.failure == nil, !report.cancelled,
                  report.total == 3, report.count(.unsupported) == 2, report.count(.skipped) == 1,
                  library.importedROMs.isEmpty else {
                library.cancelImport()
                throw LibraryError.message("The platform batch UI model did not complete correctly.")
            }
            steps.append("platform-batch")
            write(runID: runID, passed: true, steps: steps, error: nil)
        } catch {
            write(runID: runID, passed: false, steps: steps, error: userFacingNetworkError(error))
        }
    }

    private static func write(runID: String, passed: Bool, steps: [String], error: String?) {
        do {
            let report: [String: Any] = ["run_id": runID, "passed": passed, "steps": steps, "error": error ?? ""]
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                .write(to: directory.appendingPathComponent("source-probe.json"), options: .atomic)
        } catch { /* Missing output is a hard failure in the host runner. */ }
    }
}

/// Manual integration check against an already configured account: `--import-from-romm GAME`
/// (a SupportedGame case, such as cruisnUSA) imports that game, and `--import-mario-kart-from-romm`
/// Mario Kart 64. Credentials stay in Keychain; only the normal provider and ROM verifier can
/// import a playable identity. The report is Documents/romm-import-GAME.json.
@MainActor enum RomMSimulatorImport {
    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        let game: SupportedGame
        if arguments.contains("--import-mario-kart-from-romm") {
            game = .marioKart64
        } else if let index = arguments.firstIndex(of: "--import-from-romm"), index + 1 < arguments.count,
                  let named = SupportedGame(rawValue: arguments[index + 1]) {
            game = named
        } else {
            return
        }
        var report: [String: Any] = ["passed": false]
        do {
            let cache = try ROMCache()
            if let existing = try await cache.all().first(where: { $0.game == game }) {
                report = ["passed": true, "sha1": existing.sha1]
            } else {
                let data = UserDefaults.standard.data(forKey: "library.sources.v1") ?? Data("[]".utf8)
                let sources = try JSONDecoder().decode([LibrarySource].self, from: data).filter { $0.kind == .romm }
                var found: ImportedROM?
                var checked = 0
                for source in sources {
                    let provider = try ProviderFactory.make(source: source, secret: CredentialStore.load(source.id))
                    let platforms = try await provider.list(.root, search: "64", offset: 0)
                    for platform in platforms.entries {
                        guard let location = platform.folder else { continue }
                        let entries = try await provider.list(location, search: game.searchTerm, offset: 0)
                        for entry in entries.entries {
                            guard let location = entry.folder, checked < 12 else { continue }
                            let files = try await provider.list(location, search: "", offset: 0)
                            // N64 cartridges hold at most 64 MB; the verifier accepts only the supported release.
                            for file in files.entries where file.isROM && (file.size ?? 0) <= 64 * 1024 * 1024 && checked < 12 {
                                checked += 1
                                let rom = try await cache.acquire(file, sourceID: source.id, provider: provider, progress: { _ in })
                                if rom.game == game { found = rom; break }
                            }
                            if found != nil { break }
                        }
                        if found != nil { break }
                    }
                    if found != nil { break }
                }
                guard let found else {
                    throw LibraryError.message("No supported, uncompressed \(game.title) ROM was found in the configured RomM library.")
                }
                report = ["passed": true, "sha1": found.sha1, "files_checked": checked]
            }
        } catch { report["error"] = userFacingNetworkError(error) }
        if let directory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true),
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("romm-import-\(game.rawValue).json"), options: .atomic)
        }
    }
}
#endif
