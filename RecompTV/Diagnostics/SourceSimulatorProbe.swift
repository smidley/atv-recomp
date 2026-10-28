#if DEBUG && targetEnvironment(simulator)
import Foundation
import RecompSources

/// Opt-in CI probe: fixed loopback endpoints and synthetic data only. No launch argument can
/// supply a remote host, credential, or accepted-ROM hash. Excluded from release/device builds.
enum SourceSimulatorProbe {
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
                let result = try await cache.acquire(entry, sourceID: source.id, provider: provider, progress: { _ in })
                guard result.sha256 == "92a2313a5151db3e56f5386dd2714fcb01f6023fdd6e50d5bbd223fcf491f9c0",
                      !result.recognized, !result.launchable, try await cache.current() == nil else {
                    throw LibraryError.message("Synthetic ROM identity or cache eligibility was incorrect.")
                }
                steps.append(source.kind.rawValue)
            }
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
#endif
