# Guided Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Nativecade's button-list home with a guided TV setup (Connect → Detect platforms → Scan for games) that says plainly that support grows gradually, without disturbing existing libraries.

**Architecture:** The RecompSources package gains a supported-platform table, RomM platform detection, a per-platform scan on each provider, a scanner that merges several connections, one batch import across connections, and the setup record with its migration, all tested with Swift Testing (pure tests plus the loopback fixture server). `LibraryModel` persists the setup record and drives detection, scanning and Add all. New SwiftUI screens (setup flow, scan results, Settings) share a small TV chrome (backdrop, step pills, support ribbon), and `LibraryView` switches between loading, setup and the restyled home.

**Tech Stack:** Swift 6, SwiftUI on tvOS 17+, Swift Testing, AMSMB2, RomM 5.4.1 REST API, the Python fixture server `scripts/network-fixtures.py` (impacket).

**Spec:** `docs/superpowers/specs/2026-11-02-guided-setup-design.md` (screens and copy: `docs/superpowers/specs/2026-11-02-guided-setup-mockups.html`)

## Global Constraints

- tvOS 17+, SwiftUI, Swift Testing for package tests. App behaviour is checked in the simulator.
- Builds that leave the Mac contain no ROMs or ROM-derived data; covers come from RomM at runtime. Tests and fixtures use synthetic bytes, the token `fixture-token` and the password `fixture-password` only.
- Only supported platforms can be enabled. Unsupported platforms and games are counted, never listed.
- Keep the RomM API token (no username or password); setup asks for `roms.read` and `platforms.read`.
- Cover Flow stays for Favorites and each platform's games; shelves are for the home's platform rows and the scan results.
- Existing users never see the welcome flow; sources, Keychain credentials, favorites and the ROM cache are untouched.
- New persisted state is one JSON key, `library.setup.v1`, in UserDefaults next to `library.sources.v1` and `library.favorites.v1`.
- Plain `http://` stays a per-connection opt-in. Release builds keep no Diagnostics tab.
- The game runtimes' own menus and controls are out of scope.
- 10-foot type: screen titles `.title` (76 pt on tvOS), body `.body` (29 pt), the Welcome title about 110 pt heavy. System focus effects (`.buttonStyle(.card)` for covers and platform cards), one default focus per screen.
- `RecompTV.xcodeproj` lists files explicitly. Register each new app Swift file like `LibraryView.swift`: a `PBXFileReference` (like `042064B99A910D4E9735395E`), a `PBXBuildFile` (like `370340BBE638A857F7D98094`), the reference in group `F810A3947224DC074E90BB0D`'s `children`, and the build file next to `370340BBE638A857F7D98094` in both `PBXSourcesBuildPhase` `files` lists. New ids are 24 unused uppercase hex characters.
- Commits: account smidley only (`git config --local user.email` is `smidley@gmail.com`), a plain-sentence message like recent commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `audit.log`. Stay on `feature/network-rom-sources`; push with `GH_TOKEN=$(gh auth token --user smidley) git push origin feature/network-rom-sources`.
- The fixture servers, needed by every `RECOMPTV_NETWORK_FIXTURES=1` run and every screenshot run (restart after editing the script):

```bash
python3 -m venv build/fixtures-venv && build/fixtures-venv/bin/pip install -q impacket==0.13.0
build/fixtures-venv/bin/python scripts/network-fixtures.py > build/fixtures.log 2>&1 &
```

## Review Focus

1. A server holding several dumps of one game (USA and Europe, Ocarina and Master Quest): Add all must import the supported one. Prefer records whose RomM `sha1_hash` is a supported revision, else import every title match. Pinned in Task 3's scan test.
2. A token without `platforms.read`: setup still finds Nintendo 64 and only drops the server-wide count. Pinned in Task 3 (`/roms-only`).
3. Updating with an existing library: a neutral loading screen, then the home; never the welcome flow; nothing lost. Pinned in Task 1's migration test and Task 10's install-over check.
4. Scan again when games are already imported: "Add all N" counts and imports only games not yet in the library. Pinned in Task 7's `results` screenshot (synthetic library).
5. One of several connections offline: the others' games still appear, and the failing connection is named. Pinned in Task 5's scanner test.

## Deferred

- The one-time "New: <platform> is now supported" home banner. It can only appear once a second platform exists; that update adds it, treating a missing record as "knows Nintendo 64".
- Restyling the connection browser beyond moving it under Settings.

---

### Task 1: Supported platforms, filename matching and the setup record

**Files:**
- Modify: `Packages/RecompSources/Sources/RecompSources/SupportedGame.swift:30-31`
- Create: `Packages/RecompSources/Sources/RecompSources/LibrarySetup.swift`
- Modify: `RecompTV/Library/LibraryModel.swift:57-73`, `RecompTV/Library/LibraryView.swift:36-55,435-452`
- Test: `Packages/RecompSources/Tests/RecompSourcesTests/SupportedGameTests.swift`, create `Packages/RecompSources/Tests/RecompSourcesTests/GuidedSetupTests.swift`

**Interfaces:**
- Produces:
  - `public enum SupportedPlatform: String, Codable, CaseIterable, Identifiable, Sendable { case nintendo64 }` with `id`, `title` ("Nintendo 64"), `rommSlug` ("n64"), `games: [SupportedGame]` (in `SupportedGame.allCases` order), `init?(rommSlug: String)` (case-insensitive), `func game(named name: String) -> SupportedGame?` (first of `games` whose `searchTerm` the name contains, `localizedStandardContains`).
  - `SupportedGame.platform: SupportedPlatform` (was `String`).
  - `public struct LibrarySetup: Codable, Equatable, Sendable { public var complete: Bool; public var platforms: Set<SupportedPlatform>; public init(complete: Bool = false, platforms: Set<SupportedPlatform> = []) }` and `public static func migrate(hasSources: Bool, games: [SupportedGame]) -> LibrarySetup`.
  - App: `LibraryModel.Shelf.platforms: [SupportedPlatform]`, `games: [SupportedPlatform: [ImportedROM]]`; `PlatformView.platform: SupportedPlatform`.

- [ ] **Step 1: Write the failing tests**

```swift
// SupportedGameTests.swift
@Test func platformTableMatchesRomMSlugsAndFilenames() {
    #expect(SupportedPlatform(rommSlug: "N64") == .nintendo64)
    #expect(SupportedPlatform(rommSlug: "3ds") == nil)
    #expect(SupportedPlatform.nintendo64.title == "Nintendo 64")
    #expect(SupportedPlatform.nintendo64.games == SupportedGame.allCases)
    #expect(SupportedGame.allCases.allSatisfy { $0.platform == .nintendo64 })
    let n64 = SupportedPlatform.nintendo64
    #expect(n64.game(named: "Mario Kart 64 (USA).z64") == .marioKart64)
    #expect(n64.game(named: "Legend of Zelda, The - Ocarina of Time (USA).z64") == .ocarinaOfTime)
    #expect(n64.game(named: "Star Wars Episode I - Racer (USA).z64") == .episodeOneRacer)
    #expect(n64.game(named: "Paper Mario (USA).z64") == nil)
}

// GuidedSetupTests.swift
@Test func librariesFromBeforeGuidedSetupSkipTheWelcome() {
    #expect(LibrarySetup.migrate(hasSources: false, games: []) == LibrarySetup())
    // A connection but no games yet: every supported platform, so the home isn't empty.
    #expect(LibrarySetup.migrate(hasSources: true, games: []) ==
            LibrarySetup(complete: true, platforms: Set(SupportedPlatform.allCases)))
    #expect(LibrarySetup.migrate(hasSources: false, games: [.marioKart64]) ==
            LibrarySetup(complete: true, platforms: [.nintendo64]))
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/RecompSources --filter "platformTable|librariesFromBefore"`
Expected: build error, `SupportedPlatform` and `LibrarySetup` not found.

- [ ] **Step 3: Implement the interfaces above**

`migrate`: set up when `hasSources || !games.isEmpty`; platforms are the games' platforms, or every supported platform when there are no games; otherwise `LibrarySetup()`.

- [ ] **Step 4: Fix the app call sites**

The shelf groups by `game?.platform` (games without one are left out) and lists platforms in `SupportedPlatform.allCases` order; `LibraryView` shows `platform.title`.

- [ ] **Step 5: Run the package tests and build the app**

Run: `swift test --package-path Packages/RecompSources` → all pass (the network suite is skipped).
Run: `bash scripts/ci-build-tvos.sh simulator` → `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit** "Add a supported-platform table and the guided setup record"

### Task 2: One batch for items from several connections

**Files:**
- Modify: `Packages/RecompSources/Sources/RecompSources/ROMBatchImporter.swift`
- Test: `Packages/RecompSources/Tests/RecompSourcesTests/BatchImportTests.swift`

**Interfaces:**
- Produces:
  - `public struct ImportItem: Sendable { public let entry: LibraryEntry; public let sourceID: UUID; public let provider: any LibraryProvider; public init(entry:sourceID:provider:) }`: a file to import, or a folder (such as a RomM game) whose files are imported.
  - `public static func ROMBatchImporter.run(items: [ImportItem], cache: ROMCache, progress: @escaping @Sendable (BatchImportProgress) -> Void) async -> BatchImportReport`
  - `public var BatchImportReport.addedLine: String`
  - Unchanged: `run(location:sourceID:provider:cache:progress:)` (the connection browser and `SourceSimulatorProbe` use it).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func itemsFromSeveralConnectionsImportInOneReport() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = syntheticROM()
    var second = first; second[20] ^= 1
    let cache = try acceptedCache(in: root, bytes: [first, second])
    let den = BatchFixtureProvider(pages: [PageKey(.rom(1)): LibraryPage(entries: [file("first")], nextOffset: nil)],
                                   bytes: ["first": first])
    let share = BatchFixtureProvider(pages: [:], bytes: ["second": second])
    let denID = UUID(), shareID = UUID()
    let report = await ROMBatchImporter.run(items: [
        ImportItem(entry: folder(1), sourceID: denID, provider: den),
        ImportItem(entry: file("second"), sourceID: shareID, provider: share),
        ImportItem(entry: folder(2), sourceID: denID, provider: den), // can't be listed; the rest still import
    ], cache: cache, progress: { _ in })
    #expect(report.discoveryComplete)
    #expect(report.failure == nil)
    #expect(report.count(.imported) == 2)
    #expect(report.count(.failed) == 1)
    #expect(report.results.compactMap(\.rom).map(\.sourceID) == [denID, shareID])
}

@Test func addedLineSaysWhatWasAddedAndWhyTheRestWasNot() {
    func report(_ outcomes: [BatchImportResult.Outcome], cancelled: Bool = false) -> BatchImportReport {
        var report = BatchImportReport()
        report.results = outcomes.enumerated().map {
            BatchImportResult(id: String($0.offset), name: "", outcome: $0.element, message: "", rom: nil)
        }
        report.cancelled = cancelled
        return report
    }
    #expect(report(Array(repeating: .imported, count: 9) + [.unsupported]).addedLine == "9 added · 1 is a different version")
    #expect(report([.imported, .skipped, .skipped, .failed]).addedLine == "1 added · 2 are compressed · 1 couldn't be downloaded")
    #expect(report([]).addedLine == "Nothing was added")
    #expect(report([.imported], cancelled: true).addedLine == "Cancelled · 1 added")
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/RecompSources --filter "itemsFromSeveral|addedLine"`
Expected: build error, `ImportItem`, `run(items:)` and `addedLine` not found.

- [ ] **Step 3: Implement**

Both `run` functions share one discovery-and-import core. Queued folders and files carry their `sourceID` and provider; `visited` and the file de-duplication key on the `sourceID` too. Files import in item order, a folder's files in listing order. For `run(items:)` a folder that can't be listed is a `.failed` result; for `run(location:)` a failure listing its own location still stops the batch, as today. `addedLine` parts: "N added", "N is/are a different version" (`.unsupported`), "N is/are compressed" (`.skipped`), "N couldn't be downloaded" (`.failed`); zero parts left out, joined with " · "; "Nothing was added" when all are zero; prefixed "Cancelled · " when cancelled.

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/RecompSources` → all pass, the existing batch tests included.

- [ ] **Step 5: Commit** "Import items from several connections in one batch"

### Task 3: RomM platform detection and scan

**Files:**
- Create: `Packages/RecompSources/Sources/RecompSources/PlatformScan.swift`
- Modify: `Packages/RecompSources/Sources/RecompSources/LibraryTypes.swift:93-121`, `Packages/RecompSources/Sources/RecompSources/RomMProvider.swift`, `scripts/network-fixtures.py`
- Test: `Packages/RecompSources/Tests/RecompSourcesTests/NetworkTests.swift`

**Interfaces:**
- Consumes: `SupportedPlatform`, `SupportedGame.platform` (Task 1).
- Produces:
  - `public struct DetectedPlatform: Hashable, Sendable { public let platform: SupportedPlatform; public let romCount: Int? }`
  - `public struct PlatformDetection: Hashable, Sendable { public let platforms: [DetectedPlatform]; public let serverPlatformCount: Int? }`: `serverPlatformCount` is nil when the token can't list platforms.
  - `public struct ScanCandidate: Identifiable, Equatable, Sendable { public let game: SupportedGame; public let sourceID: UUID; public let entries: [LibraryEntry]; public var id: String { "\(sourceID)-\(game.rawValue)" }; public var artwork: RomMArtwork? { entries.first?.artwork } }`: `entries` are what Add all imports for that game.
  - `public struct PlatformScan: Equatable, Sendable { public var candidates: [ScanCandidate]; public var unsupportedCount: Int? }`: candidates sorted by game title; `unsupportedCount` is the platform's ROMs on the server that match no supported game, nil when unknown.
  - `LibraryProvider` gains `func detectPlatforms() async throws -> PlatformDetection` and `func scan(_ platform: SupportedPlatform) async throws -> PlatformScan`, with default implementations that throw `LibraryError.message`.
  - Copy: `.httpStatus(401/403)` reads "RomM denied access. Check the API token and its roms.read and platforms.read permissions."; `RomMProvider.init`'s token error reads "Enter a RomM Client API token with roms.read and platforms.read permissions."

- [ ] **Step 1: Extend the fixture server**

- `GET /api/platforms` answers a bare JSON array: `[{"id": 1, "slug": "n64", "name": "Nintendo 64", "rom_count": 6}, {"id": 2, "slug": "3ds", "name": "Nintendo 3DS", "rom_count": 1}, {"id": 10, "slug": "gba", "name": "Game Boy Advance", "rom_count": 0}]`.
- Paths under `/roms-only/` drop that prefix, as `/art-proxy/` does, except `/roms-only/api/platforms`, which answers 403 (a token with only `roms.read`).
- ROM 3 gets `"sha1_hash": "ad69c91157f6705e8ab06c79fe08aad47bb57ba7"` (the supported Ocarina revision's published SHA-1, as in `SupportedGameTests`); ROM 7 gets `"sha1_hash": ""` (RomM sends "" for a file it didn't hash).

- [ ] **Step 2: Write the failing tests** (in the fixture-gated `NetworkTests` suite)

```swift
@Test func rommDetectsSupportedPlatformsAndFallsBackWithoutPlatformsRead() async throws {
    #expect(try await romm().detectPlatforms() == PlatformDetection(
        platforms: [DetectedPlatform(platform: .nintendo64, romCount: 6)], serverPlatformCount: 2))
    // Without platforms.read the per-game search still finds Nintendo 64, without counts.
    #expect(try await romm("/roms-only").detectPlatforms() == PlatformDetection(
        platforms: [DetectedPlatform(platform: .nintendo64, romCount: nil)], serverPlatformCount: nil))
}

@Test func rommScanPrefersHashMatchesAndCountsTheRest() async throws {
    let source = LibrarySource(kind: .romm, address: "http://127.0.0.1:18080", allowHTTP: true)
    let scan = try await RomMProvider(source: source, token: "fixture-token").scan(.nintendo64)
    #expect(scan.candidates.map(\.game) == [.marioKart64, .ocarinaOfTime])
    // Ocarina's second record (7) loses to the record whose sha1_hash is a supported revision.
    #expect(scan.candidates.map { $0.entries.map(\.folder) } == [[.rom(4)], [.rom(3)]])
    #expect(scan.candidates.allSatisfy { $0.sourceID == source.id })
    #expect(scan.candidates.last?.artwork?.romID == 3)
    // 6 Nintendo 64 records, 3 of them titled like a supported game (3, 4 and 7).
    #expect(scan.unsupportedCount == 3)
    #expect(try await romm("/roms-only").scan(.nintendo64).unsupportedCount == nil)
}
```

- [ ] **Step 3: Run them to see them fail**

Restart the fixtures. Run: `RECOMPTV_NETWORK_FIXTURES=1 swift test --package-path Packages/RecompSources --filter "rommDetects|rommScan"`
Expected: build error, `detectPlatforms` and `scan` not found.

- [ ] **Step 4: Implement**

- `RomMProvider` keeps `source.id` for `ScanCandidate.sourceID`.
- `detectPlatforms()`: decode `GET /api/platforms` as `[{slug, rom_count}]`. Platforms with `rom_count > 0` make up `serverPlatformCount`; each supported platform among them (`SupportedPlatform(rommSlug:)`) becomes a `DetectedPlatform` with its summed `rom_count`, in `SupportedPlatform.allCases` order. On `LibraryError.httpStatus(401)` or `(403)` from that request only, fall back to the existing per-game search: the platforms of the games it matched, with `romCount` and `serverPlatformCount` nil.
- `scan(_ platform)`: for each of `platform.games`, the existing per-game search, but with `group_by_meta_id=false` and `missing=false`, keeping records on `platform.rommSlug` (or with no slug) whose title or filename contains the search term, as `playable` does today. If any kept record's `sha1_hash`, lowercased, is one of that game's revision SHA-1s (`revisions()`), the candidate's entries are those records; otherwise all kept records. Build entries like `list(.platform)` does (`.folder(.rom(id))` with artwork) through one shared helper. `unsupportedCount` = `max(rom_count − distinct kept records, 0)` from `/api/platforms`, nil when that request fails.
- `playable` checks `game.platform.rommSlug` instead of `"n64"`. Browsing requests are otherwise unchanged.

- [ ] **Step 5: Run the whole suite with fixtures**

Run: `RECOMPTV_NETWORK_FIXTURES=1 bash scripts/test-network-sources.sh` → all pass, the existing browsing tests unchanged.

- [ ] **Step 6: Commit** "Detect RomM platforms and scan them for supported games"

### Task 4: SMB scan

**Files:**
- Modify: `Packages/RecompSources/Sources/RecompSources/SMBProvider.swift`, `scripts/network-fixtures.py`
- Test: `Packages/RecompSources/Tests/RecompSourcesTests/NetworkTests.swift:107-124`

**Interfaces:**
- Consumes: `SupportedPlatform.game(named:)` (Task 1); `PlatformScan`, `ScanCandidate`, `LibraryProvider.scan(_:)` (Task 3).
- Produces: `SMBProvider.scan(_ platform: SupportedPlatform) async throws -> PlatformScan`, with `unsupportedCount` always nil.

- [ ] **Step 1: Extend the fixture and update the browsing test**

Write the synthetic `ROM` bytes to `N64/Mario Kart 64 (USA).z64` in the SMB share. In `smbAuthenticatesBrowsesFoldersAndStreamsROM`, expect `nested.entries.map(\.name) == ["Fixture.v64", "Mario Kart 64 (USA).z64"]`.

- [ ] **Step 2: Write the failing test**

```swift
@Test func smbScanMatchesFilenamesInSubfolders() async throws {
    let source = LibrarySource(address: "smb://127.0.0.1:1445/GAMES", username: "player")
    let scan = try await SMBProvider(source: source, password: "fixture-password").scan(.nintendo64)
    #expect(scan.candidates.map(\.game) == [.marioKart64])
    #expect(scan.candidates.first?.entries.map(\.name) == ["Mario Kart 64 (USA).z64"])
    #expect(scan.candidates.first?.sourceID == source.id)
    #expect(scan.unsupportedCount == nil)
}
```

- [ ] **Step 3: Run it to see it fail**

Restart the fixtures. Run: `RECOMPTV_NETWORK_FIXTURES=1 swift test --package-path Packages/RecompSources --filter smbScan`
Expected: FAIL, the default `scan` throws.

- [ ] **Step 4: Implement**

Walk the share from `.root` with `list(_:search:offset:)` (empty search, offset 0), following folders. Every ROM file (`isROM`) that `platform.game(named:)` recognizes joins that game's entries; all copies are kept, and the import's verification picks the supported dump. Past 100,000 listed items (`ROMBatchImporter`'s limit), throw `LibraryError.message("This share has too many files to scan. Point the connection at its \(platform.title) folder.")`. Sort candidates by game title.

- [ ] **Step 5: Run the whole suite with fixtures**

Run: `RECOMPTV_NETWORK_FIXTURES=1 bash scripts/test-network-sources.sh` → all pass.

- [ ] **Step 6: Commit** "Scan SMB shares for supported games"

### Task 5: Scanning every connection

**Files:**
- Modify: `Packages/RecompSources/Sources/RecompSources/PlatformScan.swift`
- Test: `Packages/RecompSources/Tests/RecompSourcesTests/GuidedSetupTests.swift`

**Interfaces:**
- Consumes: `PlatformScan`, `ScanCandidate`, `LibraryProvider.scan(_:)` (Task 3).
- Produces:
  - `public struct ScanConnection: Sendable { public let name: String; public let provider: any LibraryProvider; public init(name:provider:) }`
  - `public struct ScanReport: Sendable { public var scan: PlatformScan; public var failures: [String] }`
  - `public enum PlatformScanner { public static func scan(_ platform: SupportedPlatform, connections: [ScanConnection]) async -> ScanReport }`. Connections are scanned in order. Each game appears once, from the first connection that has it, and candidates stay sorted by game title. `unsupportedCount` is the sum of the known counts, nil when none is known. A failing connection adds "Couldn't scan <name>. <userFacingNetworkError(error)>" and the rest still count. Cancellation stops without a failure line.

- [ ] **Step 1: Write the failing test**

```swift
private struct ScanFixture: LibraryProvider {
    let result: Result<PlatformScan, LibraryError>
    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage {
        throw LibraryError.message("Not listed")
    }
    func download(_ entry: LibraryEntry, to destination: URL, progress: @escaping ProgressHandler) async throws {}
    func scan(_ platform: SupportedPlatform) async throws -> PlatformScan { try result.get() }
}

private func candidate(_ game: SupportedGame, _ sourceID: UUID) -> ScanCandidate {
    ScanCandidate(game: game, sourceID: sourceID, entries: [
        LibraryEntry(id: game.rawValue, name: game.title, detail: "", size: nil, target: .smbFile(game.rawValue))])
}

@Test func scanningSeveralConnectionsCountsEachGameOnceAndSurvivesAFailure() async {
    let den = UUID(), share = UUID()
    let report = await PlatformScanner.scan(.nintendo64, connections: [
        ScanConnection(name: "Den", provider: ScanFixture(result: .success(PlatformScan(
            candidates: [candidate(.marioKart64, den), candidate(.ocarinaOfTime, den)], unsupportedCount: 5)))),
        ScanConnection(name: "Attic", provider: ScanFixture(result: .failure(.httpStatus(503)))),
        ScanConnection(name: "Share", provider: ScanFixture(result: .success(PlatformScan(
            candidates: [candidate(.marioKart64, share), candidate(.starFox64, share)], unsupportedCount: nil)))),
    ])
    #expect(report.scan.candidates.map(\.game) == [.marioKart64, .starFox64, .ocarinaOfTime])
    #expect(report.scan.candidates.first?.sourceID == den)
    #expect(report.scan.unsupportedCount == 5)
    #expect(report.failures == ["Couldn't scan Attic. RomM returned HTTP 503. Try again after checking the server."])
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --package-path Packages/RecompSources --filter scanningSeveral`
Expected: build error, `PlatformScanner` not found.

- [ ] **Step 3: Implement `PlatformScanner.scan` as specified in Interfaces**

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/RecompSources` → all pass.

- [ ] **Step 5: Commit** "Scan every connection for a platform"

### Task 6: Library model: setup state, detection, scanning and Add all

**Files:**
- Modify: `RecompTV/Library/LibraryModel.swift`

There is no app test target. The logic this task calls is tested in the package; this task is checked by the build and the existing simulator probe, and Tasks 7–10's screenshots exercise it.

**Interfaces:**
- Consumes: `LibrarySetup` (Task 1); `ImportItem`, `run(items:)` (Task 2); `PlatformDetection`, `ScanCandidate` (Task 3); `PlatformScanner`, `ScanConnection`, `ScanReport` (Task 5).
- Produces, on `LibraryModel`:
  - `init(cache: ROMCache? = nil, defaults: UserDefaults = .standard)`: every UserDefaults read and write goes through `defaults`.
  - `private(set) var restored: Bool`: false until `restoreCache()` finishes, failure included.
  - `private(set) var setup: LibrarySetup`, stored as JSON at `library.setup.v1`. When the key is absent (or unreadable), `restoreCache()` sets it to `LibrarySetup.migrate(hasSources: !sources.isEmpty, games: importedROMs.compactMap(\.game))` and saves it before setting `restored`.
  - `func setPlatform(_ platform: SupportedPlatform, enabled: Bool)` and `func completeSetup()`: both save.
  - `var ownedGames: Set<SupportedGame>`: the games of `importedROMs`.
  - `func detectPlatforms(_ source: LibrarySource) async throws -> PlatformDetection`
  - `func scan(_ platform: SupportedPlatform) async -> ScanReport`: every saved connection in saved order, named by `source.name`. A connection whose credential or provider can't be loaded becomes a failure line, not a stop.
  - `func addAll(_ candidates: [ScanCandidate], title: String)`: imports every entry of the candidates whose game isn't in `ownedGames`, through `ROMBatchImporter.run(items:)`, with `acquireAll`'s status text, progress, `batchReport`, cancellation and retaining of imported ROMs. Share one private helper with `acquireAll(in:title:source:)`, which keeps its signature for `SourceSimulatorProbe`.

- [ ] **Step 1: Implement the interfaces above**

- [ ] **Step 2: Build**

Run: `bash scripts/ci-build-tvos.sh simulator` → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the existing simulator probe** (fixtures running)

Run: `python3 scripts/run-source-simulator-probe.py --app build/simulator/Build/Products/Debug-appletvsimulator/RecompTV.app --output build/source-probe`
Expected: a line starting `PASS:`. Its platform-batch step drives `acquireAll` through the shared helper.

- [ ] **Step 4: Commit** "Keep the setup state and drive scanning from the library model"

### Task 7: TV chrome and the platform scan screen

**Files:**
- Create: `RecompTV/Library/TVChrome.swift`, `RecompTV/Library/PlatformScanView.swift` (register both in the project)
- Modify: `RecompTV/Library/LibraryView.swift` (make `GameArtworkView`, `CoverBackdrop`, `GameView` and `BatchResultsView` internal; generalize `CoverBackdrop`; `PlatformView`; fixture preview), `RecompTV/RecompTVApp.swift`, `scripts/run-source-simulator-probe.py`

**Interfaces:**
- Consumes: Task 6's model API.
- Produces:
  - `struct SupportRibbon: View`: "Supported now" followed by `SupportedPlatform.allCases`' titles, then "Coming over time" and "more consoles and games, added with each update".
  - `struct CalmBackdrop: View`: the mockups' calm gradient (violet top left, cyan bottom right, over #0b0d12).
  - `enum SetupStage: Int { case connect, platforms, games }` and `struct StepPills: View { let current: SetupStage; var skipsPlatforms = false }`: pills "Connect", "Platforms" and "Games"; earlier stages show a check, and SMB setups leave out "Platforms".
  - `CoverBackdrop(artwork: RomMArtwork?, sourceID: UUID, title: String)`, keeping a convenience init for an `ImportedROM` so existing call sites stay.
  - `struct PlatformScanView: View { enum Mode { case setup, library }; let platform: SupportedPlatform; let library: LibraryModel; let mode: Mode }`
  - DEBUG simulator only: `struct SetupFixturePreview: View { let step: String }` in `LibraryView.swift`, opened from `RecompTVRootView` by `--setup-fixture-step <step>`, like `--artwork-fixture-preview`. It uses `LibraryModel(cache: ROMCache(root: <temporary folder>), defaults: <suite "nativecade.setup-fixture", emptied first>)`. Where a step needs a connection it saves the loopback RomM fixture (`http://127.0.0.1:18080`, HTTP allowed, token `fixture-token`, a fixed UUID) and removes that Keychain item on disappear. It awaits `restoreCache()`, so `NATIVECADE_SYNTHETIC_LIBRARY` games count as owned. This task adds the steps `games` (setup mode, before scanning) and `results` (library mode, which scans on appear).
  - `run-source-simulator-probe.py --screens <comma-separated steps>`: on its throwaway simulator, launch each step with `SIMCTL_CHILD_NATIVECADE_SYNTHETIC_LIBRARY=3`, wait 8 seconds, and save `setup-<step>.png` in `--output`. With `--screens` it skips the two probe launches; without it, it runs the probe and then every step (CI uploads them with the probe's screenshots).

The screen (copy from the mockups; wording may be tuned within the "counted, never listed" rule):
- Backdrop: the first candidate's cover (`CoverBackdrop`), else `CalmBackdrop`. Setup mode adds `StepPills(current: .games)` and the kicker "Step 3 of 3".
- Before a scan (setup mode only): the platform's title, one line, and a focused **Scan for games**. Library mode scans on appear. While scanning, a progress indicator.
- After a scan: the first candidate's cover, large and tilted −3°, on the right; the title; then "N games are ready to play.", "N are already in your library." (when any are owned), "N more aren't supported yet." (when `unsupportedCount` > 0), and each failure line in orange. Buttons: a focused **Add all N** (N = candidates not owned; hidden at 0) and **Scan again**. Below, a "Ready to play" shelf with every candidate's cover (`GameArtworkView`, title art when there is no artwork): an owned game's cover opens its `GameView`; any other offers **Add this game** in a confirmation dialog, which calls `addAll([candidate], title:)`.
- During and after Add all: today's progress row (bar, status, **Cancel import**), then `batchReport.addedLine` and **View import results** (`BatchResultsView`). Once at least one game has been added, the primary button becomes **Start playing** (setup mode: `completeSetup()`) or **Done** (library mode: back to the Cover Flow).
- Leaving the screen or backgrounding the app cancels a running import, as `SourceBrowserView` does.
- `SupportRibbon` along the bottom.
- `PlatformView`: **Scan for games** next to the title (a `NavigationLink` to `PlatformScanView(mode: .library)`), "No games yet." when it has none, and `SupportRibbon` at the bottom. Its Cover Flow is unchanged.

- [ ] **Step 1: Implement and register the two new files**

- [ ] **Step 2: Build**

Run: `bash scripts/ci-build-tvos.sh simulator` → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Screenshot the two steps** (fixtures running)

Run: `python3 scripts/run-source-simulator-probe.py --app build/simulator/Build/Products/Debug-appletvsimulator/RecompTV.app --output build/setup-screens --screens games,results`
Expected, in `build/setup-screens/`:
- `setup-games.png`: pills with Connect and Platforms checked, "Nintendo 64", a focused Scan for games, the ribbon.
- `setup-results.png`: "2 games are ready to play.", "1 is already in your library." (the synthetic games are Ocarina), "3 more aren't supported yet.", **Add all 1**, a shelf with two covers, the ribbon.

- [ ] **Step 4: Commit** "Add the platform scan screen and the support ribbon"

### Task 8: Setup flow

**Files:**
- Create: `RecompTV/Library/SetupFlow.swift` (register in the project)
- Modify: `RecompTV/Library/LibraryView.swift` (`SourceEditorView` internal with a setup mode; preview steps)

**Interfaces:**
- Consumes: Tasks 6 and 7.
- Produces:
  - `struct SetupFlowView: View { let library: LibraryModel }`: a `NavigationStack(path:)` over `enum SetupRoute: Hashable { case connect(SourceKind), findPlatforms(LibrarySource), choosePlatforms(LibrarySource, PlatformDetection), games(SupportedPlatform, skipsPlatforms: Bool) }`, rooted at the Welcome screen. The remote's Back steps back one screen.
  - `struct ChoosePlatformsView: View { let library: LibraryModel; let detection: PlatformDetection?; let serverName: String?; let onContinue: (() -> Void)? }`: a nil `detection` means Settings (every supported platform, no counts, no Continue).
  - `SourceEditorView(source:library:setup: Bool = false, onSaved: ((LibrarySource) -> Void)? = nil)`: when set, `onSaved` replaces `dismiss()`.

Screens (copy from the mockups), each with `StepPills` and `SupportRibbon`:
1. **Welcome**: `CalmBackdrop`; kicker "Welcome"; "Nativecade"; "Play the games on your RomM server, natively on Apple TV. Setup takes three steps."; a focused **Connect RomM**, and a secondary **Use an SMB share**.
2. **Connect**: kicker "Step 1 of 3"; "Connect RomM" or "Connect an SMB share"; the editor in setup mode. Setup mode has no name field: the connection is named after the server's host, else the kind's title. RomM shows "Server" and "RomM API token", the line "Give the token the roms.read and platforms.read permissions.", and **Allow HTTP for this server** only once the address starts with `http://`. SMB keeps today's fields. The primary button is **Connect** (today's access check, then save). RomM continues to Find platforms. SMB turns on every supported platform and continues to `games(SupportedPlatform.allCases[0], skipsPlatforms: true)` (`// ponytail: one platform today; SMB setups enable them all until shares get a platform step`).
3. **Find platforms**: kicker "● Connected · <host>"; "Find your platforms"; "Nativecade checks which consoles your server has games for, and shows the ones it can play."; a focused **Detect platforms**, with any error in orange below it.
4. **Choose platforms**: "Choose platforms", then "Your server has N platforms. Nativecade plays K of them so far." Without a server count it reads "Nativecade plays K of your server's platforms so far. Add platforms.read to your RomM token to see how many it has."
   - One large card per detected platform: its name, "N games on your server" when known, and an On/Off pill. Selecting a card toggles `setPlatform`. All are on at the first visit.
   - Then the dashed card "More platforms are on the way · They'll appear here when an update adds them."
   - **Continue**, enabled while a detected platform is on, opens `games(first enabled, skipsPlatforms: false)`.
   - Settings mode reads "Turn on the platforms you want in your library." and has no Continue.
5. **Games**: `PlatformScanView(mode: .setup)`.

Outside setup, the editor's caption also asks for roms.read and platforms.read. The preview gains the steps `welcome`, `connect`, `detect` and `platforms`.

- [ ] **Step 1: Implement and register the new file**

- [ ] **Step 2: Build**

Run: `bash scripts/ci-build-tvos.sh simulator` → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Screenshot the four steps** (fixtures running)

Run: the Task 7 command with `--screens welcome,connect,detect,platforms`.
Expected:
- `welcome`: a focused Connect RomM, and the ribbon "Supported now Nintendo 64".
- `connect`: Server, RomM API token and the permissions line, with no HTTP toggle (the address is empty).
- `detect`: "Connected · 127.0.0.1" and Detect platforms.
- `platforms`: "Your server has 2 platforms. Nativecade plays 1 of them so far.", a Nintendo 64 card reading "6 games on your server" and On, and the dashed card.

- [ ] **Step 4: Commit** "Guide first launch through connect, platforms and games"

### Task 9: Home, Settings and the first-run switch

**Files:**
- Create: `RecompTV/Library/SettingsView.swift` (register in the project)
- Modify: `RecompTV/Library/LibraryView.swift`

**Interfaces:**
- Consumes: Tasks 6, 7 and 8.
- Produces:
  - `LibraryView`, the root that owns the model, shows one of three states:
    - Until `library.restored`: a neutral loading state (`CalmBackdrop` and a progress indicator).
    - While `!library.setup.complete`: `SetupFlowView`.
    - Otherwise: `LibraryHomeView(library:)`.
    - The `.task` (restore, simulator launch probe, artwork refresh), the alert and the "Preparing your game" overlay stay on this root, so they cover every state.
  - `struct LibraryHomeView: View { let library: LibraryModel }`:
    - Header: "Nativecade", then Search (when there are games) and a **Settings** button with the `gearshape` symbol.
    - Favorites in today's Cover Flow.
    - One row per enabled platform, in `SupportedPlatform.allCases` order: its title and game count, then a horizontal shelf that runs off the right edge. The shelf starts with a platform card that opens `PlatformView`, followed by the platform's games as `GameTile`s.
    - "Turn on a platform in Settings." when none is enabled, then today's controller hint line.
    - Backdrop: the selected favorite's `CoverBackdrop`, else `CalmBackdrop`.
    - The old Connections section and the bottom row of buttons are removed from the home.
  - `struct SettingsView: View { let library: LibraryModel }`. Everything except Platforms moves here from the home, with its sheet and full-screen cover:
    - Connections: each one can be browsed (`SourceBrowserView`), edited or removed; **Add RomM** and **Add SMB share** open the `SourceEditorView` sheet.
    - **Platforms** opens `ChoosePlatformsView(library:detection: nil, serverName: nil, onContinue: nil)`.
    - **Clear ROM cache** and **Refresh artwork**, when there are games.
    - **Third-party notices** and **Last game log**.
  - The preview gains the steps `home` (setup complete, Nintendo 64 on, synthetic library) and `settings` (fixture connection saved).

- [ ] **Step 1: Implement and register the new file**

- [ ] **Step 2: Build**

Run: `bash scripts/ci-build-tvos.sh simulator` → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Screenshot the two steps** (fixtures running)

Run: the Task 7 command with `--screens home,settings`.
Expected:
- `home`: Search and Settings in the header, a Nintendo 64 row with its platform card and three synthetic covers, and no connection buttons.
- `settings`: the fixture connection, Platforms, and the moved actions.

- [ ] **Step 4: Commit** "Restyle the home and move connections and tools into Settings"

### Task 10: Docs and the full check

**Files:**
- Modify: `docs/NETWORK_SOURCES.md` (the steps at lines 9–30, the token row at 44, the API notes at 60–72), `docs/NATIVECADE_TESTFLIGHT.md:122`

- [ ] **Step 1: Update the docs**

- `NETWORK_SOURCES.md`, walkthrough: follow the guided setup (Welcome → Connect RomM or Use an SMB share → Detect platforms → Choose platforms → Scan for games → Add all). Settings holds later connections, the connection browser, Clear ROM cache and Refresh artwork.
- `NETWORK_SOURCES.md`, RomM token row: ask for `roms.read` and `platforms.read`.
- `NETWORK_SOURCES.md`, API notes:
  - `GET /api/platforms`: needs the `platforms.read` scope and returns a bare array with `slug` and `rom_count`. On 401/403, setup falls back to the per-game search, without the server count.
  - The scan searches with `group_by_meta_id=false` and prefers records whose `sha1_hash` is a supported revision. RomM hashes the file as stored, so only big-endian `.z64` dumps can match; for other dumps every title match is imported and the verifier chooses.
- `NATIVECADE_TESTFLIGHT.md`: Last game log is now in Settings (the gear next to Search).

- [ ] **Step 2: Run every package test with fixtures**

Run: `RECOMPTV_NETWORK_FIXTURES=1 bash scripts/test-network-sources.sh` → all pass.

- [ ] **Step 3: Build both configurations**

Run: `bash scripts/ci-build-tvos.sh simulator` and `bash scripts/ci-build-tvos.sh device` → `** BUILD SUCCEEDED **` for both (the device build is Release).

- [ ] **Step 4: Run the probe and every screen**

Run: `python3 scripts/run-source-simulator-probe.py --app build/simulator/Build/Products/Debug-appletvsimulator/RecompTV.app --output build/source-probe`
Expected: `PASS:` and eight `setup-*.png` files. Compare each with the mockups.

- [ ] **Step 5: Install over an existing library** (Review Focus 3)

Build Nativecade for the simulator: `xcodebuild -project RecompTV.xcodeproj -scheme Nativecade -configuration Debug -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' -derivedDataPath build/nativecade-sim build` → `** BUILD SUCCEEDED **`.

Install it over the booted simulator's Nativecade with `xcrun simctl install`, which keeps its data, so the imported games stay. Never uninstall it. Launch it and screenshot. Expected: a loading screen, then the home with those games; the welcome flow never appears.

- [ ] **Step 6: Commit and push** "Document the guided setup"
