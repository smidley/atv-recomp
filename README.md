# RecompTV

RecompTV is the working name for a native Apple TV launcher that discovers a user's game library through SMB or RomM and runs supported, statically recompiled games locally on tvOS.

**Status: foundation checks confirmed in the simulator; runtime porting experiments underway.** The maintainer confirmed the C++ result and visible Metal color checks on 2026-10-28. Development continues with the simulator for now; physical Apple TV validation is deferred. No game runtime is integrated. See [simulator evidence](docs/SIMULATOR_PROGRESS.md) and the [pinned runtime audit](docs/RUNTIME_AUDIT.md).

## Run the foundation harness

Open `RecompTV.xcodeproj` in Xcode 16 or newer, select the **RecompTV** scheme and an Apple TV simulator or paired device, then Run. A physical device needs your development team selected under Signing & Capabilities. No project-generation tool or third-party dependency is required.

The app shows the native C++ result, a solid Metal test surface, and separate GPU-completion and user-confirmed visual evidence. See [Foundation harness](docs/FOUNDATION_HARNESS.md) for setup, checks, limitations, and the physical-device evidence to collect. The provisional tvOS 17 deployment floor is for the harness only.

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

Prove that a native tvOS app can run a C++ module, display a Metal frame, and host the dependencies needed for an N64 recompilation runtime. Then attempt to boot **The Legend of Zelda: Majora's Mask** using the existing Zelda 64: Recompiled project and a user-supplied ROM.

The proof of concept comes before the full launcher and network integrations. Desktop or macOS support is useful starting evidence, but does not establish tvOS compatibility. See [POC.md](POC.md) for the checkpoints and required evidence.

## Intended technology stack

| Area | Direction | Validation still needed |
| --- | --- | --- |
| App and library UI | Swift, SwiftUI, native tvOS | Focus navigation and runtime presentation |
| Game execution | Game-specific C/C++ code compiled ahead of time for ARM64 | tvOS dependency and lifecycle support |
| Graphics | Metal on Apple TV | Selected runtime renderer and device feature requirements |
| Input | Apple Game Controller framework | Mapping, disconnects, pause, and resume |
| Library sources | Independent SMB and RomM adapters | SMB library choice and supported RomM versions |
| Game data | User-supplied ROMs, validated local cache | Revision hashes, format handling, storage limits |
| Saves | Local runtime saves; optional synchronization later | Durable storage and recovery on tvOS |

These are design directions, not implemented capabilities.

## Documentation

| Document | Purpose |
| --- | --- |
| [Product requirements](PRODUCT_REQUIREMENTS.md) | User flows, MVP boundaries, and acceptance criteria |
| [Architecture](ARCHITECTURE.md) | App components, providers, runtime boundary, and data flow |
| [Roadmap](ROADMAP.md) | Milestones ordered around technical feasibility |
| [Proof of concept](POC.md) | First native tvOS experiment and go/no-go evidence |
| [Foundation harness](docs/FOUNDATION_HARNESS.md) | Open the Xcode project, run checks, and collect device evidence |
| [Simulator progress](docs/SIMULATOR_PROGRESS.md) | Maintainer-confirmed checks and remaining evidence |
| [Runtime audit](docs/RUNTIME_AUDIT.md) | Pinned upstream dependencies, porting blockers, and isolated core builds |
| [RT64 Metal experiment](docs/RT64_METAL_EXPERIMENT.md) | tvOS backend adapter, link checks, and upstream shader conversion |
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
