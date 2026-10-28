# Connect a ROM server

The Library tab connects to an existing SMB share or RomM instance, browses files,
downloads an individual uncompressed N64 ROM, and identifies its exact Shipwright
revision. Development and execution checks remain simulator-only. Native gameplay
and Torch/O2R asset preparation are not integrated yet.

## Try your server in Xcode

1. Open `RecompTV.xcodeproj` and let Swift Package Manager resolve its dependencies.
   Select the **RecompTV** scheme and an Apple TV simulator, then Run.
2. Open **Library** and choose **Add SMB share** or **Add RomM**.
3. Enter the connection details below and select **Connect and save**. This tests
   access before saving the connection. Passwords/tokens are stored in Keychain,
   separately from the source address and display name.
4. Select the saved connection, browse to the file, and select **Import and verify**.
   RomM catalog entries open a file list so individual files can be chosen without
   automatically downloading a multi-file ZIP.
5. A matching Ocarina of Time ROM displays its revision and SHA-1. A different game
   or unsupported revision displays an explicit rejection and is not cached. The
   app has no Play action yet: identifying data does not provide the native game runtime.

Use a server address reachable from the Mac running the simulator. There is no
RecompTV server to install. No ROM or credential needs to be uploaded to GitHub or
sent through chat. The first live-server test needs only the instance URL or share
path for coordination; enter secrets directly in the app.

## Connection details

| Source | Address | Authentication |
| --- | --- | --- |
| SMB | `smb://nas.local/Games/N64` (share `Games`, optional root folder `N64`) | Username/password; optional domain. Empty username uses `guest`. |
| RomM | `https://romm.example.com`, including any reverse-proxy prefix | Client API token with `roms.read` permission |

SMB uses **AMSMB2 4.0.3**, pinned at
[`1726aaaf7adf63d7d1d2a0c5d1b0e635028215c0`](https://github.com/amosavian/AMSMB2/tree/1726aaaf7adf63d7d1d2a0c5d1b0e635028215c0).
Its package declares tvOS support. The app uses read-only listing, attributes, and
streaming reads, never remote writes. It supports SMB2/3 with NTLM account or guest
access, depending on server policy. **Require SMB3 encryption** fails on servers
that cannot provide it. Kerberos, SMB1, NFS, AFP, share autodiscovery, and mounted
desktop filesystem paths are not implemented. Provide an explicit share name.

RomM's implemented contract is checked against **5.4.1** source:

- [`GET /api/roms`](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/roms/__init__.py):
  `limit`, `offset`, `search_term`; decode `items`, `total`, and `offset`.
- `GET /api/roms/{rom_id}`: enumerate individual `files`.
- [`GET /api/roms/{file_id}/files/content/{file_name}`](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/roms/files.py):
  download one file using its **file ID**, not the catalog ROM ID.
- [Client API token authentication](https://docs.romm.app/5.4.0/developers/api-authentication/):
  `Authorization: Bearer …`. Obtain the token in RomM's Client API token settings.

This is source-contract validation and fixture testing, not a claim that every
RomM version or a live 5.4.1 deployment has been tested. Artwork, descriptions,
device pairing, OAuth refresh, and save synchronization are later work. No write
scope is needed. A 401/403 prompts reconnecting with a valid token and scope.

HTTPS is the default. **Allow HTTP for this server** is an explicit per-source
choice for local servers. HTTP sends the API token without transport encryption.
The app's ATS exception allows arbitrary user-entered HTTP hostnames/IPs; the
provider still rejects HTTP unless that source opts in. TLS certificate checks
are never bypassed. All HTTP redirects are rejected before another request is
sent, so use the final instance URL rather than a login or redirect URL. The
app does not use browser cookies or persist tokens in URLs or catalog records.

## Validation, storage, and cancellation

- Only individual `.z64`, `.v64`, and `.n64` files can be imported. Extract archives
  on the server first. SMB browsing shows folders and candidate ROM files.
- The file's magic bytes determine byte order; the extension does not prove identity.
  Streamed canonicalization checks the N64 header, size/alignment, SHA-1 against
  all 19 pinned Shipwright revisions, and SHA-256 for local integrity.
- Transfers reject changed sizes, partial bodies, paths that escape the selected
  share folder, and ROMs larger than 64 MiB. HTTP catalog bodies are limited to 8 MiB.
  SMB compares size and modification time before/after transfer. A content change
  that escapes those checks still cannot pass the accepted-ROM hash comparison.
- Files first enter private staging, then verification. Only an accepted complete
  ROM is promoted to the cache, in canonical byte order. Unknown bytes and failed
  or cancelled transfers are removed. A previous accepted copy survives a failed
  import. Orphan staging files are removed at app initialization.
- **Cancel import**, leaving the browser, or backgrounding the app cancels the
  transfer. HTTP uses URLSession cancellation; SMB stops on its next read callback,
  with a 20-second operation timeout if the server is unresponsive. No partial file
  is considered usable during that interval.
- The initial cache retains one accepted ROM. Allow roughly 192 MiB of free space
  for an old 64 MiB copy plus staging and normalization. Download/write failures
  remain recoverable. This cache is purgeable tvOS storage, not a save backup.
  Cache identity is rechecked when restoring its status after app launch.
- **Edit** tests the new connection before updating it. **Remove** deletes the
  source and its Keychain entry; **Clear ROM cache** separately removes local ROM
  data. Neither action changes files on the server.

## Automated verification

On a Mac with Swift 6, run `bash scripts/test-network-sources.sh` for address,
canonicalization, cache promotion, corruption, cancellation, and bounded sink tests.
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
Keychain save/read/delete and both providers' download/hash/rejection paths, and
saves fresh per-launch JSON plus launcher screenshots. Its opt-in code is excluded
from device and Release builds.

The runner ad-hoc signs only the disposable `AppleTVSimulator` build, with a
test-only application identifier and default Keychain group, then verifies that
signature before installation. Normal Xcode development signing supplies the app
identifier automatically. This does not modify the user's team or device profile.

The `Network sources` workflow runs the protocol and simulator checks. The
`Foundation harness` workflow also builds Simulator Debug and device Release;
device compilation is not physical-device validation. A manual simulator pass
against the intended RomM/NAS is still needed for server-specific authentication,
remote focus/keyboard interaction, network permission prompts, and the real ROM's
revision. No live-server test has been claimed.

## Third-party notices

AMSMB2 is linked as its upstream dynamic Swift package product, unmodified.
Upstream describes its Swift sources as MIT and the combined library with libsmb2
as LGPL 2.1. The full combined-library license is bundled in
`Packages/RecompSources/Sources/RecompSources/Resources/AMSMB2-LICENSE.txt`.
The pinned source, its dependency submodule references, build manifest, and
rebuildable application sources are available from the links above and this
repository. Distribution packaging and license obligations remain a release gate;
this milestone is simulator development, not an App Store release.
