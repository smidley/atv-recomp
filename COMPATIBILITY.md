# Compatibility

**Status:** no game or Apple TV model has validated RecompTV support as of 2026-10-28. This document defines the proposed validation model, not an available-games list.

## Candidate matrix

| Game | Platform | Candidate runtime | ROM revision/hash | tvOS result |
| --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time | N64 | Shipwright / Ship of Harkinian 9.3.1 | [19 upstream SHA-1 references](upstream/shipwright-supported-roms.json); no real ROM tested here | First target; host identification prototype only; no tvOS game build/run |
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
become a bundled runtime or a Ready library entry. Shipwright remains first;
other N64 projects form the subsequent investigation queue.

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

Proposed baseline: calculate SHA-256 over a documented canonical byte representation, while retaining any additional identity checks required by upstream. If normalization is necessary, define and test it before accepting alternate representations.

N64 file extensions such as .z64, .v64, and .n64 are discovery hints only. Byte order, headers, archives, and modified ROMs need explicit handling. The POC may initially accept only the exact uncompressed representation selected for testing. Other formats must not be advertised until implemented and verified.

The [Shipwright host prototype](docs/SHIPWRIGHT_PORT.md) recognizes byte order from the header, hashes a canonical big-endian stream, and compares the pinned upstream SHA-1 values. Synthetic tests cover all three byte orders. This is not yet the app's validator, real-ROM validation, asset extraction, or permission to label a game Ready.

Do not use placeholder hashes, accept a filename as identity, or treat a server-reported checksum as a substitute for validating downloaded bytes. ROM hacks, translations, and other modifications are unsupported unless explicitly integrated and validated.

A checksum establishes byte identity for compatibility; it does not establish ownership or distribution rights.

## Cache and source changes

Bind validation to content identity, not just a path or provider ID. A renamed file may be identical; a file at the same path may have changed. Keep source identity so the user can locate or reacquire data.

Incomplete downloads never reach Ready. Revalidate changed or suspect cached content and clear stale readiness when a cached file is missing. An eligible runtime can remain installed while its game data is Unavailable.

## Evidence required to add support

Record app/runtime commits, accepted ROM revision and hashes, Apple TV model/chipset, tvOS version, controller, renderer configuration, test duration, tested game sections, graphics/audio defects, save/reload, and lifecycle results.

For provider support, separately record the tested SMB server/protocol/authentication combination and RomM version/authentication flow. Library-provider compatibility does not certify gameplay compatibility.

Keep this matrix aligned with [POC.md](POC.md), [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md), and the bundled registry once it exists.
