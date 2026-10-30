# Architecture

**Status:** proposed product architecture, 2026-10-28. A [foundation harness](docs/FOUNDATION_HARNESS.md) now implements a minimal SwiftUI shell, C/C++ probe, and Metal presentation check. The [network source package](docs/NETWORK_SOURCES.md) now implements RomM/SMB browsing, credential storage, staging, and ROM validation. Game runtime and physical-device behavior remain unvalidated.

The maintainer has confirmed the foundation checks in the simulator. The first game target is now [Shipwright](docs/SHIPWRIGHT_PORT.md), followed by N64 expansion and then other platforms. Earlier [runtime-core](docs/RUNTIME_AUDIT.md) and [RT64](docs/RT64_METAL_EXPERIMENT.md) experiments remain isolated research. They do not select Shipwright's runtime or renderer. The existing app bridge remains C++17.

## System boundary

RecompTV is one native tvOS app. Existing SMB storage and optional RomM provide data; game execution and rendering happen on Apple TV. No RecompTV server component is required.

~~~mermaid
flowchart TD
    SMB["Existing SMB share / NAS"] --> Providers["Library provider adapters"]
    RomM["Existing RomM instance (optional)"] --> Providers
    Providers --> Catalog["Unified catalog"]
    Catalog --> UI["SwiftUI launcher"]
    UI --> Launch["Launch coordinator"]
    Providers --> Cache["ROM staging and local cache"]
    Cache --> Validation["ROM validation"]
    Registry["Bundled runtime registry"] --> Validation
    Validation --> Assets["Runtime-specific asset preparation"]
    Assets --> Launch
    Launch --> Runtime["Bundled native game runtime"]
    Input["Controller input"] --> Runtime
    Runtime --> Graphics["Metal presentation and audio"]
    Runtime <--> Saves["Save service"]
~~~

The diagram describes responsibilities rather than a finalized module layout.

## Proposed components

| Component | Responsibility |
| --- | --- |
| Launcher | Source setup, catalog browsing, focus, status, errors, and runtime presentation |
| Library providers | Discover metadata and resolve/read game data from their source |
| Catalog | Retain source identity and locations; combine entries without confusing discovery with support |
| Runtime registry | Describe the runtimes compiled into this app and their ROM/device requirements |
| ROM validator | Identify the actual bytes and select an accepted revision or reject the launch |
| Asset preparation | Produce and validate the data format required by the selected runtime, without changing the source ROM |
| Cache manager | Stage transfers, verify completion, manage space, and recover from missing cached files |
| Launch coordinator | Order validation, save loading, runtime startup, shutdown, and return to the launcher |
| Runtime adapter | Connect each game's native code to graphics, audio, input, filesystem, and lifecycle services |
| Save service | Isolate game save formats, perform recoverable writes, and provide a future synchronization boundary |

Provider and runtime interfaces should stay separate: adding a source must not require modifying the game, and adding a game must not require changing SMB or RomM integration.

## Library providers

A proposed provider contract includes connection testing, paginated or incremental discovery, metadata lookup, source change detection, and cancellable transfer to a local staging file.

**SMB:** the initial implementation uses pinned AMSMB2 4.0.3 to browse a user-selected share/folder and stream candidate files. See the network guide for the checked APIs, license, and remaining live-server validation. Do not assume an app can mount a share like a desktop filesystem. ROM access is read-only in the initial design.

**RomM:** the initial implementation uses the 5.4.1 catalog/file API contract and a Client API token with `roms.read`. Artwork and additional authentication flows remain planned. Use the instance's OpenAPI specification to pin the integration rather than inventing endpoints. RomM documents an instance API explorer at /api/docs and a specification at /openapi.json. See the [RomM API reference](https://docs.romm.app/latest/developers/api-reference/).

RomM's [client API token documentation](https://docs.romm.app/latest/developers/client-api-tokens/) describes scoped tokens and pairing options. The initial client-token flow keeps credentials in Keychain, outside catalog metadata. Pairing and save synchronization are later adapter capabilities.

## Runtime and build boundary

The intended build pipeline produces native ARM64 game code ahead of time and packages it with the tvOS app. The device obtains user game data, not new native executable modules. A new runtime requires a new app build.

Adapters can wrap source ports such as Shipwright or static recompilation projects. They do not share one mandatory renderer or assume the ROM is their direct runtime input. Shipwright uses libultraship and extracts ROM assets into an O2R archive. Zelda64Recomp uses a different runtime and RT64. Neither integration establishes support for arbitrary N64 games.

Use a narrow Swift-to-C/C++ boundary, potentially a C interface with an Objective-C++ adapter where needed. This is a proposal pending the first integration spike. It should expose:

- Runtime identity, version, accepted ROM revisions, and required device capabilities.
- Initialization with validated game data and explicit host services.
- Input delivery, audio output, frame presentation, and timing.
- Pause/resume, save flush, controlled shutdown, and diagnostic errors.

Keep game state separate from SwiftUI view state. Define which thread owns the runtime and renderer. Avoid blocking the main UI thread with discovery, hashing, downloads, or game execution.

The foundation harness uses a C-compatible bridging header and a C++17 translation unit. SwiftUI diagnostics and the tiny, on-demand `MTKView` clear pass are main-actor owned. Metal callbacks send scalar/string evidence back to that actor, tagged by test generation. This ownership is specific to the probe; it is not a decision to execute future game code or data transfers on the UI thread.

The renderer must ultimately present through Metal on tvOS. Existing desktop Metal support does not prove that the required GPU features, shaders, windowing code, or dependencies work on Apple TV. The exact backend adaptation is a POC outcome.

## Launch sequence

1. Resolve the catalog entry's candidate runtime from the bundled registry.
2. Check runtime/device eligibility; keep ROM identity unverified until bytes are available.
3. Acquire or reopen the selected ROM and establish sufficient local space.
4. Validate the format and exact revision under the policy in [COMPATIBILITY.md](COMPATIBILITY.md).
5. Promote a completed, validated transfer into the cache.
6. Prepare runtime-specific assets; bind derived caches to the ROM digest, extractor version, and runtime version. Publish only complete outputs.
7. Load the applicable save and initialize the runtime.
8. Present gameplay and route controller/audio/lifecycle events.
9. Flush saves and release runtime resources before returning to the library.

Treat interrupted staging data as incomplete. If a source changes or cached content no longer matches its validated identity, invalidate eligibility and validate again. Never launch while a transfer is still mutating the file.

## Storage and saves

Proposed storage categories are small settings, provider catalog metadata, artwork cache, staged/downloaded ROMs, and game saves. Credentials belong in platform credential storage; none belong in the repository.

ROM and artwork caches are replaceable. Preserve source references so missing content can be reacquired. Bound cache usage and keep save handling separate from cache eviction.

Apple's [archived tvOS programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/index.html) describes purgeable app data and recoverable downloads. Use it as a warning to validate current SDK/device behavior, not as a current numeric storage specification.

A local save write alone is not a durable backup strategy. Prototype save/reload first, then select and test a durable recovery mechanism before a user-facing release. Options such as iCloud storage or an existing network destination remain unselected. Full RomM synchronization stays later work; it is not silently required for SMB users.

## Failure and trust boundaries

Treat remote filenames, paths, metadata, and ROM bytes as untrusted input. Use bounded parsing/transfers and app-controlled cache paths. Archive extraction, if later supported, needs explicit size and path handling.

Handle authentication expiry, offline providers, insufficient storage, invalid ROMs, runtime initialization failures, controller loss, and application suspension as explicit states. Logs should identify stages and errors without including tokens, private URLs, or ROM contents.

A native runtime shares the app process in this proposal; a runtime crash can terminate the app. Recovery must therefore tolerate incomplete cache/save operations rather than assuming a separate process isolates failure.

## Choices still open

Minimum device/tvOS version, SMB library, RomM baseline, persistence framework, bridge details, audio integration, renderer changes, and save durability remain unselected. Record their evidence and decisions in [DECISIONS_AND_RISKS.md](DECISIONS_AND_RISKS.md).
