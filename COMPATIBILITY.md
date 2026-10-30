# Compatibility

**Status:** Nativecade includes five experimental native ports as of 2026-10-30. All have simulator rendering evidence; physical Apple TV qualification remains pending. A verified ROM is launchable in a development build without implying full gameplay or hardware support.

## Candidate matrix

| Game | Platform | Candidate runtime | ROM revision/hash | tvOS result |
| --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time | N64 | Shipwright / Ship of Harkinian 9.3.1 | [19 upstream SHA-1 references](upstream/shipwright-supported-roms.json); NTSC 1.0 US imported and extracted | Experimental; integrated app renders in tvOS Simulator; earlier simulator gameplay and controls confirmed by the user. [Evidence](docs/NATIVECADE_TESTFLIGHT.md) |
| Mario Kart 64 | N64 | SpaghettiKart 1.0.0 | USA, SHA-1 `579c48e211ae952530ffc8738709f078d5dd215e` | Experimental; RomM import, extraction, title/demo, and Luigi Raceway acceleration through SDL controller input verified in tvOS Simulator. [Evidence and limits](docs/SPAGHETTIKART.md) |
| Star Fox 64 | N64 | Starship v2.0.0 | USA 1.0 and 1.1, [SHA-1s](upstream/starship-baseline.json); 1.1 imported | Experimental; RomM import, extraction, and startup verified in tvOS Simulator; switches with the other games. [Evidence and limits](docs/STARSHIP.md) |
| Super Mario 64 | N64 | Ghostship 3.0.0 | USA, SHA-1 `9bef1128717f958171a4afac3ed78ee2bb4e86ce` | Experimental; import, extraction, and title screen verified in tvOS Simulator; switches with the other games. [Evidence and limits](docs/GHOSTSHIP.md) |
| Banjo-Kazooie | N64 | Lighthouse 1.2.2 | USA 1.0 and 1.1, Europe, Japan, [SHA-1s](upstream/lighthouse-baseline.json); USA 1.1 imported | Experimental; RomM import, extraction, and opening scene verified in tvOS Simulator; switches with the other games. [Evidence and limits](docs/LIGHTHOUSE.md) |
| The Legend of Zelda: Majora's Mask | N64 | Zelda 64: Recompiled | Earlier audit only | Deferred candidate; isolated core/RT64 builds do not establish gameplay |

Do not interpret upstream desktop support as RecompTV support. Add other titles only with their own runtime integration and test evidence.

After Shipwright, grow N64 coverage toward the full library before adding other platforms. One N64 port working does not make all other titles compatible.

## Finding candidate projects

Use the maintainer-supplied [recomp.fyi](https://recomp.fyi/) index to discover
N64 recompilation, native source-port, and decompilation projects. Follow each
row to its public upstream repository and verify the actual project type,
release state, toolchain, renderer, accepted game data, and platform support.
The index warns that automatically collected rows can be misclassified.

Record upstream progress separately from RecompTV progress. A decompilation
can supply groundwork without supplying a playable native port; a released
desktop port still needs a tvOS integration. No index row should automatically
become a bundled runtime or a Ready library entry. Shipwright and SpaghettiKart
are integrated; other N64 projects remain in the investigation queue.

## What makes a game launchable

All of the following must hold:

1. This app build includes a runtime for the game.
2. The actual ROM matches a revision accepted by that runtime.
3. The device and tvOS version meet the runtime's tested requirements.
4. Complete validated game data is locally available.
5. Required runtime services and save initialization are available.

RomM metadata, a recognizable filename, or a matching extension can suggest a candidate. None proves these conditions. Discovering thousands of catalog entries does not imply thousands of playable games.

## Proposed library states

| State | Meaning | Launch behavior |
| --- | --- | --- |
| Unverified | Candidate entry exists; exact bytes have not been checked | Acquire/validate before play |
| Unsupported | No bundled runtime for the title/platform | Explain lack of support |
| Unsupported revision | ROM is identifiable but is not accepted by this runtime | Reject and explain the revision mismatch |
| Invalid data | Truncated, malformed, or otherwise failed validation | Reject and allow retry/replacement |
| Device incompatible | Known runtime requirements are not met | Explain device/tvOS requirement |
| Unavailable | Required data cannot currently be acquired or reopened | Offer reconnect/retry |
| Ready | Runtime/device checks pass and complete ROM data validates | Allow launch |

Keep the runtime's test maturity separate from data readiness. A development build may have a Ready ROM for an experimental runtime without claiming that the game is fully supported.

## Proposed runtime maturity levels

- **Candidate:** selected for investigation; no tvOS result.
- **Boots:** a recognizable game screen has been observed.
- **Experimental:** some gameplay works, with known or insufficiently tested limitations.
- **Supported:** meets the project's documented gameplay, graphics, audio, input, lifecycle, and save criteria on named configurations.
- **Blocked:** a known issue prevents the stated use case; record the issue and affected versions.

A short smoke test is insufficient to claim a full playthrough. State the test scope alongside each support label.

## ROM identification policy

Choose an authoritative revision allowlist when pinning a runtime. Record region, revision, byte size, accepted representation, checksum algorithm/value, and source of the reference data. The allowlist ships with the app and is tied to the bundled runtime version.

The app hashes a canonical big-endian representation with SHA-1 for the upstream
allowlist and SHA-256 for local integrity. The cache revalidates both immediately
before handing the ROM to its selected native runtime.

N64 file extensions such as .z64, .v64, and .n64 are discovery hints only. The app
recognizes and normalizes all three uncompressed byte orders from their headers;
archives and modified ROMs are not accepted by the current allowlists.

Synthetic tests cover all three byte orders. Live imports have matched the
supported Ocarina NTSC 1.0 US, Mario Kart USA, Star Fox 64 USA 1.1, Super Mario 64
USA and Banjo-Kazooie USA 1.1 identities, and every native preparer rechecks the
ROM before extracting assets. A filename or RomM title
cannot select the wrong game's runtime.

Do not use placeholder hashes, accept a filename as identity, or treat a server-reported checksum as a substitute for validating downloaded bytes. ROM hacks, translations, and other modifications are unsupported unless explicitly integrated and validated.

A checksum establishes byte identity for compatibility; it does not establish ownership or distribution rights.

## Cache and source changes

Bind validation to content identity, not just a path or provider ID. A renamed file may be identical; a file at the same path may have changed. Keep source identity so the user can locate or reacquire data.

Incomplete downloads never reach Ready. Revalidate changed or suspect cached content and clear stale readiness when a cached file is missing. An eligible runtime can remain installed while its game data is Unavailable.

## Evidence required to add support

Record app/runtime commits, accepted ROM revision and hashes, Apple TV model/chipset, tvOS version, controller, renderer configuration, test duration, tested game sections, graphics/audio defects, save/reload, and lifecycle results.

For provider support, separately record the tested SMB server/protocol/authentication combination and RomM version/authentication flow. Library-provider compatibility does not certify gameplay compatibility.

Keep this matrix aligned with [POC.md](POC.md), [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md), and the bundled registry once it exists.
