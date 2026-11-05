# Connect a ROM server

On first launch, a guided setup connects an existing RomM instance or SMB share,
finds the supported platforms on it, and scans each one for the games Nativecade
plays; every import verifies the exact ROM. Settings keeps the connections and a
browser for importing one particular file or folder. The Nativecade
scheme integrates native gameplay and on-device Torch/O2R preparation. See
[Nativecade build and TestFlight](NATIVECADE_TESTFLIGHT.md) for its prerequisites;
the RecompTV scheme remains the independent library/diagnostics harness.

## Try your server in Xcode

1. Open `RecompTV.xcodeproj` and let Swift Package Manager resolve its dependencies.
   Select the **Nativecade** scheme after preparing its runtime/resources, or
   **RecompTV** for the library-only harness, and an Apple TV simulator, then Run.
2. A new install opens on the guided setup; a library from before it goes straight
   to its home. Choose **Connect RomM**, or **Use an SMB share**.
3. Enter the connection details below and select **Connect**. This tests access
   before saving the connection. Passwords/tokens are stored in Keychain,
   separately from the source address and display name.
4. For RomM, select **Detect platforms**. **Choose platforms** shows a card for each
   supported platform on the server with its game count, counts the server's other
   platforms rather than listing them, and says more platforms are on the way. Turn
   platforms on or off, then select **Continue**. An SMB share skips this step.
5. On the platform's page, select **Scan for games**. The page counts the games
   that are ready to play, those already in the library and those not supported yet,
   and shows a shelf of their covers. **Add all** imports the new ones in one batch
   and reports what was added ("9 added · 1 is a different version"); a cover not
   yet added offers **Add this game**. **Start playing** finishes setup.
6. Each import checks the exact revision by SHA-1; a different game or unsupported
   revision is reported and not cached. In the Nativecade app, imported games appear
   on their platform's shelf on the home screen, where **Play** prepares the assets
   on the device. The RecompTV harness only verifies/imports; it does not link the
   game runtime.
7. Later, **Settings** (the gear next to Search) adds, edits and removes connections,
   turns platforms on and off, and opens a connection's browser: **Import and verify**
   for one file, or **Verify and import all ROMs** on a platform or folder page. The
   batch scans every page and subfolder, including items hidden by the current
   search, and never requests a multi-file ZIP. A platform's page on the home offers
   **Scan for games** again, for instance after an update adds a game.

Use a server address reachable from the Apple TV, or from the Mac for simulator testing. There is no
RecompTV server to install. No ROM or credential needs to be uploaded to GitHub or
sent through chat. The first live-server test needs only the instance URL or share
path for coordination; enter secrets directly in the app.

## Connection details

| Source | Address | Authentication |
| --- | --- | --- |
| SMB | `smb://nas.local/Games/N64` (share `Games`, optional root folder `N64`) | Username/password; optional domain. Empty username uses `guest`. |
| RomM | `https://romm.example.com`, including any reverse-proxy prefix | Client API token with `roms.read` and `platforms.read` permissions |

SMB uses **AMSMB2 4.0.3**, pinned at
[`1726aaaf7adf63d7d1d2a0c5d1b0e635028215c0`](https://github.com/amosavian/AMSMB2/tree/1726aaaf7adf63d7d1d2a0c5d1b0e635028215c0).
Its package declares tvOS support. The app uses read-only listing, attributes, and
streaming reads, never remote writes. It supports SMB2/3 with NTLM account or guest
access, depending on server policy. **Require SMB3 encryption** fails on servers
that cannot provide it. Kerberos, SMB1, NFS, AFP, share autodiscovery, and mounted
desktop filesystem paths are not implemented. Provide an explicit share name.

RomM's implemented contract is checked against **5.4.1** source:

- [`GET /api/roms`](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/roms/__init__.py):
  `limit`, `offset`, `search_term`, `platform_ids`, `group_by_meta_id`;
  decode `items`, `total`, and `offset`. Reject mismatched platform IDs and invalid
  pagination so a platform import cannot silently include another platform.
  Browsing sends one `search_term` per supported game ("Ocarina of Time",
  "Mario Kart 64", "Star Fox 64", "Super Mario 64", "Banjo-Kazooie"), which RomM matches word by word against the title, filename
  and aliases. Because aliases match too (Paper Mario matches "Super Mario 64"), a result is kept
  only when its title or filename contains the phrase ([search](https://github.com/rommapp/romm/blob/5.4.1/backend/handler/database/roms_handler.py)).
  It also sends `group_by_meta_id=true` and `missing=false`
  ([filters](https://github.com/rommapp/romm/blob/5.4.1/backend/handler/database/rom_filters.py)),
  so several records for one game show as one, as in RomM's gallery, and records
  whose file is gone from the server are skipped. Matches outside `platform_slug`
  `n64` are dropped, and the platform list is grouped from the remaining items,
  so browsing needs only `roms.read`. Titles only narrow the list; an import still
  verifies the exact revision by SHA-1.
- [`GET /api/platforms`](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/platform.py)
  (scope `platforms.read`) answers a bare list of platforms with `slug` and
  `rom_count`. **Detect platforms** offers each supported platform whose slug it
  lists (`n64` for Nintendo 64) and counts the server's platforms that hold ROMs. A
  token without `platforms.read` gets 401/403 there; setup then finds the supported
  platforms through the per-game search instead and leaves out the server's total.
- **Scan for games** sends the same per-game `search_term` with
  `group_by_meta_id=false` and `missing=false`, limited by `platform_ids` to the
  platform's own entries when the token can list platforms, so every record of a
  game is a candidate and other platforms' games stay out. A game with more than 150
  records keeps the first 150 instead of stopping the scan. When a record's
  `sha1_hash` is a supported revision, only that record is imported. RomM hashes the
  file as stored, so only big-endian `.z64` dumps can match; for other dumps,
  **Add all** tries the first 10 title matches and the verifier keeps the supported
  one. The "not supported yet" count is the platform's `rom_count` minus the records
  titled like a supported game. An SMB share is scanned by file name across its
  folders, with no count.
- `GET /api/roms/{rom_id}`: enumerate individual `files`.
- [`GET /api/roms/{file_id}/files/content/{file_name}`](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/roms/files.py):
  download one file using its **file ID**, not the catalog ROM ID.
- [Client API token authentication](https://docs.romm.app/5.4.0/developers/api-authentication/):
  `Authorization: Bearer …`. Obtain the token in RomM's Client API token settings.

This is source-contract validation and fixture testing, not a claim that every
RomM version or a live 5.4.1 deployment has been tested. Descriptions,
device pairing and OAuth refresh are later work. The separate optional game-save
backup setup is described below. ROM browsing needs no write scope. A 401/403 prompts reconnecting with a valid token and scope.

HTTPS is the default. **Allow HTTP for this server** is an explicit per-source
choice for local servers. HTTP sends the API token without transport encryption.
The app's ATS exception allows arbitrary user-entered HTTP hostnames/IPs; the
provider still rejects HTTP unless that source opts in. TLS certificate checks
are never bypassed. All HTTP redirects are rejected before another request is
sent, so use the final instance URL rather than a login or redirect URL. The
app does not use browser cookies or persist tokens in URLs or catalog records.

## Validation, storage, and cancellation

- **Add all** on a scan page, and **Verify and import all ROMs** in a connection's
  browser, scan first, then process one file at a time, even across connections.
  Repeated catalog/file IDs are deduplicated. Each file is reported as imported,
  unsupported, skipped (unsupported format), or failed. Listing or transfer failures
  for individual games do not hide the other results. A stopped/incomplete scan is
  reported explicitly. **View import results** shows the per-file outcome.
- Platform browsing does not add other game runtimes or verification manifests.
  Only the pinned Ocarina of Time revisions are accepted. Other N64 games fail
  identity verification; archives and other formats are skipped without downloading.
- Only individual `.z64`, `.v64`, and `.n64` files can be imported. Extract archives
  on the server first. SMB browsing shows folders and candidate ROM files.
- The file's magic bytes determine byte order; the extension does not prove identity.
  Streamed canonicalization checks the N64 header, size/alignment, SHA-1 against
  all 19 pinned Shipwright revisions plus Mario Kart 64 (USA), Star Fox 64 (USA)
  1.0 and 1.1, Super Mario 64 (USA), and Banjo-Kazooie (USA 1.0 and 1.1, Europe,
  Japan), and SHA-256 for local integrity.
- Transfers reject changed sizes, partial bodies, paths that escape the selected
  share folder, and ROMs larger than 64 MiB. HTTP catalog bodies are limited to 8 MiB.
  SMB compares size and modification time before/after transfer. A content change
  that escapes those checks still cannot pass the accepted-ROM hash comparison.
- Files first enter private staging, then verification. Only an accepted complete
  ROM is promoted to the cache, in canonical byte order. Unknown bytes and failed
  or cancelled transfers are removed. A previous accepted copy survives a failed
  import. Orphan staging files are removed at app initialization.
- **Cancel import**, leaving the browser or scan page, or backgrounding the app cancels the
  transfer. HTTP uses URLSession cancellation; SMB stops on its next read callback,
  with a 20-second operation timeout if the server is unresponsive. No partial file
  is considered usable during that interval. Completed batch imports are kept;
  opening the results sheet does not cancel the queue.
- The cache retains every accepted ROM, deduplicated by canonical SHA-256, and
  migrates the original single-ROM record without removing it or its ROM. Allow
  storage for retained ROMs plus up to 128 MiB for transfer and normalization.
  Failed or unsupported imports do not evict accepted copies. Download/write
  failures remain recoverable. This is purgeable tvOS storage, not a save backup.
  Each cached identity is rechecked when restoring the library after app launch.
- In **Settings**, **Edit** tests the new connection before updating it. **Remove** deletes the
  source and its Keychain entry; **Clear ROM cache** separately removes local ROM
  data. Neither action changes files on the server.

## Game artwork

RomM platform pages display cover cards, and each game's file page shows a larger
cover and up to 12 screenshots. Select a screenshot to enlarge it. Imported games
retain the RomM title and artwork references with their verified ROM record.
SMB entries and missing artwork use placeholders; image failures never block a
ROM import or Play.

The implementation uses RomM's `path_cover_small`, `path_cover_large`, and
`merged_screenshots` fields from its
[5.4.1 ROM response](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/responses/rom.py)
and [resource paths](https://github.com/rommapp/romm/blob/5.4.1/backend/models/rom.py).
It fetches images beneath `/assets/romm/resources` on the configured instance,
plus the platform icon its web interface uses, `/assets/platforms/<slug>.ico`
([PlatformIcon.vue](https://github.com/rommapp/romm/blob/5.4.1/frontend/src/components/common/Platform/PlatformIcon.vue)),
preserving a reverse-proxy prefix. The existing Client API token authenticates
these requests. Third-party `url_cover` links, redirects, path traversal, and
non-resource URLs are not followed. No additional RomM write permission is needed.

Each download is limited to 8 MiB and 15 seconds. ImageIO validates and downsamples
the image to a maximum dimension of 1,200 pixels away from the main actor. Shared
requests are coalesced and queued; leaving the last requesting view cancels the
download. The least recently used images are trimmed to a 64 MiB disk budget.
Cached images remain available offline, subject to tvOS cache eviction. Server
timestamps in image URLs refresh changed art; a missing small cover can use the
large cover. Tokens are never stored in image URLs or cache filenames.

**Refresh artwork** updates imported records without transferring the ROM again.
Older records without a RomM ROM ID are matched only when the catalog contains
one exact filename/size match; ambiguous matches retain their placeholder. A
normal reimport also records the current artwork. Metadata refresh cannot change
ROM identity or invalidate an already selected Play action.

The 2026-10-28 verification pass includes 25 host tests with loopback HTTP/SMB
fixtures and an on-device simulator probe for authenticated image download,
ImageIO decoding, and offline reuse. Cover-card and screenshot layouts were
inspected on the tvOS 27.0 Apple TV 4K simulator using synthetic color charts.
Live artwork from the intended RomM server and physical remote focus still need
an interactive pass. `--artwork-fixture-preview` opens that fixed-loopback visual
fixture at its platform list (or, with `--artwork-fixture-detail`, at a game's file
page) in Debug simulator builds only; the fixture is absent from device and
Release builds.

## Box art

The library shows each game as a 3D box with its cartridge inside
([design](superpowers/specs/2026-11-05-box-shelf-design.md)). The box's back and spine and the
cartridge photo come from RomM's `ss_metadata` (ScreenScraper) and `launchbox_metadata` (LaunchBox):
`box2d_path`, `box2d_back_path`, `box2d_side_path` and `physical_path`, paths beneath
`/assets/romm/resources`, through the same checks as the covers. Whatever RomM doesn't have, Nativecade
draws: the spine with the game's title, the back with its description and screenshots, and a cartridge
label from the cover.

RomM downloads only front covers, screenshots and manuals by default. For real backs, spines and
cartridges, on the RomM server:

1. In RomM's web app, Settings → Scan, turn on the back cover and box spine media types. LaunchBox
   supplies them.
2. For cartridge art, add a free ScreenScraper account to RomM's container settings as
   `SCREENSCRAPER_USER` and `SCREENSCRAPER_PASSWORD`, then turn on the cartridge-or-disc media type on
   the same page.
3. Re-scan the platform, so RomM downloads the new art for games it already has. **Refresh artwork** in
   Nativecade's Settings then picks it up.

## Automated verification

On a Mac with Swift 6, run `bash scripts/test-network-sources.sh` for address,
canonicalization, multi-ROM cache migration, corruption, batch pagination,
deduplication, cancellation, partial failure, and bounded sink tests.
The bundled manifest is checked against `upstream/shipwright-supported-roms.json`.

For actual loopback network tests:

```sh
python3 -m venv /tmp/recomptv-fixture-venv
/tmp/recomptv-fixture-venv/bin/pip install impacket==0.13.0
/tmp/recomptv-fixture-venv/bin/python scripts/network-fixtures.py
```

In another terminal:

```sh
RECOMPTV_NETWORK_FIXTURES=1 bash scripts/test-network-sources.sh
bash scripts/ci-build-tvos.sh simulator
python3 scripts/run-source-simulator-probe.py \
  --app build/simulator/Build/Products/Debug-appletvsimulator/RecompTV.app \
  --output build/source-probe
```

Stop the fixture process when finished. It listens only on loopback ports 18080
and 1445, uses public test-only credentials, and serves generated bytes that do not
match any game. It never reads a user ROM directory. The simulator probe creates
and deletes only its own simulator, launches the actual app twice, verifies
Keychain save/read/delete, both providers' download/hash/rejection paths, and the
observable platform-batch UI model, and saves fresh per-launch JSON plus launcher
screenshots. Its opt-in code is excluded
from device and Release builds.

The runner installs only an `AppleTVSimulator` build, unchanged.
`scripts/ci-build-tvos.sh simulator` keeps Xcode's ad hoc "Sign to Run Locally"
signature, whose simulated application identifier supplies the default Keychain
group; no certificate, team account or device profile is involved. Re-signing that
identifier into an ad hoc code signature stops the app from launching on both the
tvOS 26.5 and 27.0 simulators.

The `Network sources` workflow runs the protocol and simulator checks. The
`Foundation harness` workflow also builds Simulator Debug and device Release;
device compilation is not physical-device validation. A manual simulator pass
against the intended RomM/NAS is still needed for server-specific authentication,
remote focus/keyboard interaction, network permission prompts, and the real ROM's
revision. Local simulator testing on 2026-10-28 verified platform browsing against
the intended RomM server; the earlier single-ROM import verified the user's NTSC
1.0 Ocarina of Time ROM. A two-entry platform batch also completed in the simulator
and reported both unsupported file formats as skipped. Full-library imports are
not required for these checks.

## Game save backups

Nativecade's integrated Shipwright game can back up completed saves to RomM.
Backups have their own opt-in Keychain setup and need `assets.read` / `assets.write`;
ROM browsing credentials are not automatically reused. The older standalone
simulator experiment remains in its own container. See
[Game saves and controllers](APPLE_TV_SAVES_AND_CONTROLLERS.md).

## Third-party notices

AMSMB2 is linked as its upstream dynamic Swift package product, unmodified.
Upstream describes its Swift sources as MIT and the combined library with libsmb2
as LGPL 2.1. The full combined-library license is bundled in
`Packages/RecompSources/Sources/RecompSources/Resources/AMSMB2-LICENSE.txt`.
The pinned source, its dependency submodule references, build manifest, and
rebuildable application sources are available from the links above and this
repository. Nativecade also bundles runtime dependency notices and buildable integration
sources. Public App Store distribution and license review remain separate from
the initial internal TestFlight test.
