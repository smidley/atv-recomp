# Roadmap

**Planning baseline:** 2026-10-28. This is a sequence of evidence-based milestones, not a dated delivery commitment. The maintainer confirmed the foundation checks in the simulator and requested simulator-only development for now. Physical-device validation is deferred; it remains a compatibility/release gate, not a prerequisite for continuing simulator engineering.

Validate native execution before investing in the full launcher. If the runtime or renderer is infeasible, revisit the scope before building provider integrations around it.

## M0 — Establish the project baseline

**Deliverables**

- The seven project documents with a shared scope and compatibility vocabulary.
- Explicit separation of decisions, proposals, and untested assumptions.
- A reproducible evidence checklist for the first tvOS experiment.

**Exit:** documentation is reviewed and the next technical step is the POC in [POC.md](POC.md).

## M1 — Prove the tvOS foundation

**Progress:** the [foundation harness](docs/FOUNDATION_HARNESS.md) provides a SwiftUI tvOS target, C/C++ bridge probe, on-demand Metal surface, visual confirmation checks, and an unsigned build workflow. The maintainer [confirmed its simulator checks](docs/SIMULATOR_PROGRESS.md). A [first source audit](docs/RUNTIME_AUDIT.md) pins the candidate runtime and identifies desktop rendering and live-recompiler boundaries. The isolated core experiment compiles the upstream service library separately from the game, renderer, and mod loader. M1's physical-device exit criteria remain open.

**Active simulator track:** compile the core services for both simulator architectures, test their callback boundaries on the host, then adapt the renderer and a static-only runtime build. No physical device or ROM is required for the current core experiment.

The core service builds and callback tests passed in PR #2. The
[RT64 Metal experiment](docs/RT64_METAL_EXPERIMENT.md) now isolates the renderer's
Metal backend, replaces Cocoa window metrics, and adds simulator shader build
checks. Actual RT64 GPU execution and the full static-only runtime remain open.

**Deliverables**

- Minimal native tvOS application with SwiftUI.
- A C++ module compiled and executed on a physical Apple TV.
- A Metal frame displayed on that same device.
- Dependency, GPU feature, and build feasibility notes for the selected upstream runtime.

**Exit:** record device/toolchain versions and demonstrate all three early checkpoints. If dependencies or renderer features cannot be adapted within an acceptable scope, record the blocker and revisit the game/runtime choice.

## M2 — Attempt the first native game

**Deliverables**

- A pinned upstream revision and dependency/license inventory.
- The Majora's Mask candidate runtime integrated into the tvOS harness.
- Development-only local ROM provisioning, exact revision validation, and graphics output.
- Basic controller input, audio investigation, lifecycle handling, and diagnostics.
- Measured frame timing and memory behavior on physical hardware.

**Exit:** reach a recognizable game screen, demonstrate input-driven gameplay, and repeat launch/exit. Record rendering, audio, performance, and stability limitations. A booting screen alone is not a claim of supported gameplay.

**Decision gate:** proceed to the product launcher only after the POC supports a credible native gameplay path. Resolve or explicitly rescope major failures first.

## M3 — Build the launcher around the proven runtime

**Deliverables**

- Native library UI and controller/remote navigation.
- Runtime registry and compatibility states.
- Launch coordinator, validated ROM cache, progress, and error handling.
- Save creation/reload and a tested proposal for durable recovery.
- Return-to-library and controller/lifecycle handling.

**Exit:** launch the proven runtime through the UI using locally provisioned data; reject invalid data; recover from expected failures; record the chosen save policy.

## M4 — Connect existing libraries

**Deliverables**

- SMB folder discovery and ROM acquisition independent of RomM.
- RomM authentication, catalog, metadata/artwork, and ROM downloads.
- A unified library with explicit eligibility and source identity.
- Tests for missing files, changed content, offline sources, interrupted transfers, and cache misses.

**Exit:** browse the RomM library and launch a validated game natively on Apple TV, then demonstrate the equivalent path with SMB alone and no custom server software.

## M5 — Validate the player-facing MVP

**Deliverables**

- A published tested-device/runtime/ROM matrix.
- Stable controls, graphics, audio, save/reload, and repeated lifecycle transitions.
- Documented save durability and recovery, including cache eviction scenarios.
- Chosen minimum device/tvOS baseline and measured performance targets.
- License/attribution inventory and an evaluated distribution route.
- Reproducible build/setup instructions once an actual project exists.

**Exit:** meet [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md), resolve release-blocking risks, and attach evidence to every advertised support claim. App Store acceptance is a separate outcome, not implied by passing technical tests.

## M6 — Expand after the MVP

Evaluate additional precompiled runtimes, optional RomM save synchronization, game-specific settings, and performance improvements. Each added title must pass its own ROM, device, gameplay, and save validation.

Additional consoles, providers, and emulator fallback require separate scope decisions. The initial architecture leaves room for them without promising delivery.

## Working method

For each milestone, record the responsible maintainer, exact revision, device/toolchain, result, and remaining blockers. Mark completion only after the exit evidence exists. Prefer small changes with meaningful validation; do not schedule downstream polish as if native feasibility were already proven.
