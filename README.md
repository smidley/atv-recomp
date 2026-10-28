# RecompTV

RecompTV is the working name for a native Apple TV launcher that discovers a user's game library through SMB or RomM and runs supported native ports and statically recompiled games locally on tvOS.

**Status: RomM/SMB browsing and verified ROM import implemented; Shipwright is the first game target.** Development continues with the simulator for now; physical Apple TV validation is deferred. No game runtime is integrated. See [simulator evidence](docs/SIMULATOR_PROGRESS.md) and the [Shipwright baseline and ROM identification tool](docs/SHIPWRIGHT_PORT.md). Earlier Zelda64Recomp/RT64 experiments remain separate from the app.

## Run the launcher

Open `RecompTV.xcodeproj` in Xcode 16 or newer, let Swift Package Manager resolve dependencies, select the **RecompTV** scheme and an Apple TV simulator, then Run. In **Library**, add an SMB share or RomM connection and import an uncompressed N64 ROM. See [Network sources](docs/NETWORK_SOURCES.md) for connection details and testing. No project-generation tool is required.

The **Diagnostics** tab shows the native C++ result, a solid Metal test surface, and separate GPU-completion and user-confirmed visual evidence. See [Foundation harness](docs/FOUNDATION_HARNESS.md) for setup, checks, limitations, and the physical-device evidence to collect. The provisional tvOS 17 deployment floor is for the harness only.

Portable native checks: `sh scripts/test-native.sh`. Presentation-state checks with Swift 6: `sh scripts/test-evidence.sh`. GitHub CI also builds unsigned simulator and device targets; it does not establish physical-device support.

## Project direction

- Deliver one native tvOS app with a SwiftUI interface and controller navigation.
- Use existing SMB shares, including NAS or Unraid storage, without custom server software.
- Offer RomM as an optional source of library metadata, artwork, and ROM downloads. SMB must work independently.
- Execute games on Apple TV using bundled native ARM64 game code and a renderer targeting Metal.
- Require user-supplied game data and validate the exact ROM revision before launch.
- Fetch and cache individual games as needed instead of copying an entire collection.
- Keep library providers and game runtimes modular so other sources and consoles can be considered later.

A discovered game is not automatically playable. Each supported title needs a compatible game-specific runtime included in the app. Adding a ROM to RomM or an SMB folder does not create that runtime.

## First milestone

The first game is **The Legend of Zelda: Ocarina of Time**, using **Ship of Harkinian (Shipwright)** and a user-supplied ROM. Shipwright compiles decompiled game source and uses libultraship's renderer; it is a different integration from Zelda64Recomp and RT64. The ROM supplies game assets to the native port.

The agreed order is Shipwright first, then expanding N64 coverage toward the full library, then other platforms. Each added title needs a compatible native runtime and its own validation. A shared launcher does not automatically make every N64 ROM executable.

Game integration remains a proof of concept; network browsing and verified imports can now be developed and tested independently. Desktop or macOS support is useful starting evidence, but does not establish tvOS compatibility. See [POC.md](POC.md) for the checkpoints and required evidence.

## Intended technology stack

| Area | Direction | Validation still needed |
| --- | --- | --- |
| App and library UI | Swift, SwiftUI, native tvOS | Focus navigation and runtime presentation |
| Game execution | Game-specific C/C++ code compiled ahead of time for ARM64 | tvOS dependency and lifecycle support |
| Graphics | Metal on Apple TV | Selected runtime renderer and device feature requirements |
| Input | Apple Game Controller framework | Mapping, disconnects, pause, and resume |
| Library sources | AMSMB2 4.0.3 and RomM 5.4.1 API contract | Live intended-server validation; artwork and broader version coverage |
| Game data | User-supplied ROMs, validated local cache | Revision hashes, format handling, storage limits |
| Saves | Local runtime saves; optional synchronization later | Durable storage and recovery on tvOS |

The source/import implementation is described in [Network sources](docs/NETWORK_SOURCES.md); the runtime, controller and save integrations remain work in progress.

## Documentation

| Document | Purpose |
| --- | --- |
| [Product requirements](PRODUCT_REQUIREMENTS.md) | User flows, MVP boundaries, and acceptance criteria |
| [Architecture](ARCHITECTURE.md) | App components, providers, runtime boundary, and data flow |
| [Roadmap](ROADMAP.md) | Milestones ordered around technical feasibility |
| [Proof of concept](POC.md) | First native tvOS experiment and go/no-go evidence |
| [Network sources](docs/NETWORK_SOURCES.md) | RomM/SMB setup, verified ROM imports, storage limits, and fixture tests |
| [Foundation harness](docs/FOUNDATION_HARNESS.md) | Open the Xcode project, run checks, and collect device evidence |
| [Simulator progress](docs/SIMULATOR_PROGRESS.md) | Maintainer-confirmed checks and remaining evidence |
| [Shipwright first game](docs/SHIPWRIGHT_PORT.md) | Pinned native port, local ROM identification, and next tvOS integration steps |
| [Shipwright Metal build](docs/SHIPWRIGHT_METAL_BUILD.md) | Complete libultraship services and renderer link checks for tvOS Simulator |
| [Earlier runtime audit](docs/RUNTIME_AUDIT.md) | Zelda64Recomp dependencies, porting blockers, and isolated core builds |
| [RT64 Metal experiment](docs/RT64_METAL_EXPERIMENT.md) | Separate renderer build research; not Shipwright's renderer |
| [Compatibility](COMPATIBILITY.md) | ROM validation, runtime eligibility, and support status |
| [Decisions and risks](DECISIONS_AND_RISKS.md) | Agreed direction, proposals, unresolved choices, and sources |

The initial documentation was reconstructed from the project's planning discussion on 2026-10-28 because the earlier documentation ZIP was unavailable. Agreed direction is identified separately from proposed implementation details and open questions.

## Development prerequisites

The foundation harness needs a Mac with Xcode and the tvOS SDK; physical validation also needs an Apple TV available for development and its remote or a controller. It does not need a ROM. The later game experiment additionally needs a compatible game controller and a user-supplied ROM matching the selected upstream revision. Record exact hardware, OS, toolchain, and dependency versions when starting each experiment.

The minimum Apple TV model and tvOS version have not been selected. Simulator results alone will not establish graphics, performance, or device compatibility.

## Project boundaries

RecompTV does not distribute commercial ROMs or extracted copyrighted game assets. Do not commit ROMs, private library data, credentials, or game-derived build artifacts to this repository.

Remote game streaming, a custom server/container, on-device recompilation or JIT, downloadable native runtimes, and automatic support for arbitrary ROMs are outside the initial scope. Emulator fallback is an optional future discussion, not part of the MVP.

No project license or distribution channel has been selected. Dependency licenses, redistribution obligations, and App Store suitability require review before distributing an application; see [DECISIONS_AND_RISKS.md](DECISIONS_AND_RISKS.md).
