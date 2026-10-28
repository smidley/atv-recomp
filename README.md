# RecompTV

RecompTV is the working name for a native Apple TV launcher that discovers a user's game library through SMB or RomM and runs supported, statically recompiled games locally on tvOS.

**Status: native foundation proof of concept.** The repository now includes a SwiftUI tvOS app, a C++ static library, and a basic Metal clear/present pass. No game runtime or validated game support is included. See [BUILDING.md](BUILDING.md) to build and run it and [POC.md](POC.md) for verification evidence and remaining device checks.

## Run the foundation

Open **RecompTV.xcodeproj**, select the **RecompTV** scheme and an Apple TV simulator, then Run. The screen shows the C++ probe result and a Metal-rendered color. Use **Change test color** to verify another frame through the same native path. Physical Apple TV installation requires selecting your development signing team in Xcode.

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
| [Build and run](BUILDING.md) | Xcode setup, simulator checks, and physical-device steps |
| [Compatibility](COMPATIBILITY.md) | ROM validation, runtime eligibility, and support status |
| [Decisions and risks](DECISIONS_AND_RISKS.md) | Agreed direction, proposals, unresolved choices, and sources |

The initial documentation was reconstructed from the project's planning discussion on 2026-10-28 because the earlier documentation ZIP was unavailable. Agreed direction is identified separately from proposed implementation details and open questions.

## Development prerequisites

The first experiment needs a Mac with Xcode and the tvOS SDK, a physical Apple TV available for development, a compatible controller, and a user-supplied ROM matching the selected upstream revision. Record exact hardware, OS, toolchain, and dependency versions when starting the experiment.

The minimum Apple TV model and tvOS version have not been selected. Simulator results alone will not establish graphics, performance, or device compatibility.

## Project boundaries

RecompTV does not distribute commercial ROMs or extracted copyrighted game assets. Do not commit ROMs, private library data, credentials, or game-derived build artifacts to this repository.

Remote game streaming, a custom server/container, on-device recompilation or JIT, downloadable native runtimes, and automatic support for arbitrary ROMs are outside the initial scope. Emulator fallback is an optional future discussion, not part of the MVP.

No project license or distribution channel has been selected. Dependency licenses, redistribution obligations, and App Store suitability require review before distributing an application; see [DECISIONS_AND_RISKS.md](DECISIONS_AND_RISKS.md).
