# Native tvOS Recompilation Proof of Concept

**Status:** the [foundation harness](docs/FOUNDATION_HARNESS.md) is implemented for checkpoints 1–2. The physical Apple TV experiment has not been run, the upstream dependency audit is open, and no game runtime is integrated as of 2026-10-28.

## Question to answer

Can an existing N64 static recompilation project be adapted to run natively on a physical Apple TV with usable graphics and controller input?

The first candidate is **The Legend of Zelda: Majora's Mask**, using [Zelda 64: Recompiled](https://github.com/Zelda64Recomp/Zelda64Recomp) as the starting point and a user-supplied ROM. Its desktop support is not evidence of tvOS support.

## Scope

Build a minimal tvOS harness. Prioritize native code execution, rendering, dependency feasibility, then a real game boot. Use a development-only method to place the user's ROM in app-local storage.

The POC does not need SMB, RomM, artwork, a polished library, multiple games, save synchronization, or a distribution-ready application. A colored Metal frame proves the presentation path only; it does not prove the game's renderer.

## Prerequisites

The foundation harness uses no game data or upstream runtime. The ROM and pinned dependency prerequisites below apply before the dependency/game integration checkpoints.

- Mac with a working Xcode/tvOS SDK installation and device signing setup.
- Physical Apple TV with its model, chipset, and tvOS version recorded.
- Compatible game controller.
- A ROM matching the exact revision accepted by the chosen upstream code.
- A pinned upstream commit, all required dependency revisions, and build/license notes.

Never put ROMs or extracted game assets in Git, CI artifacts, screenshots of source files, or a public build bundle. Define the private local provisioning procedure when the harness exists.

## Experiment sequence

### 1. Establish the app and native bridge

The native **RecompTV** target now calls `RTVBridgeAdd(19, 23)` through a C bridging header and displays the result. Open `RecompTV.xcodeproj` using the harness instructions and run it on the selected device.

**Evidence:** a successful device build/run and an observable result from the C++ code. Document the bridge and toolchain.

### 2. Establish Metal presentation

The harness now provides an `MTKView` that clears to C++-supplied blue, green, or red. Its passing display status requires successful GPU completion followed by explicit user confirmation of the visible color; tvOS does not provide the drawable presentation callback. Run and visually verify it on the same device, including reruns and suspend/resume.

**Evidence:** actual device output and the relevant GPU capabilities. Keep this checkpoint separate from any claim about the upstream renderer.

### 3. Audit and adapt dependencies

Inspect the selected upstream build instructions, submodules, renderer, shader tools, audio, input, filesystem, and window/lifecycle assumptions. Separate build-host tools from code that must run on tvOS.

For each dependency record:

| Field | Required evidence |
| --- | --- |
| Source/version | Repository and exact commit or release |
| Role | Host build tool or runtime component |
| tvOS result | Builds, needs changes, or blocked |
| Platform assumptions | APIs, GPU features, threads, files, or runtime code generation |
| License | License identifier and redistribution obligations to evaluate |
| Next action | Minimal adaptation or concrete blocker |

**Evidence:** a dependency matrix and a credible path to an app-bundled runtime without on-device code generation or downloaded native modules.

### 4. Integrate ROM loading and game boot

Add the selected game runtime, provision the user ROM locally, and validate the actual bytes before invoking game code. Record the exact revision and checksum policy; do not invent an accepted hash.

Adapt graphics and host services sufficiently to attempt a recognizable game screen.

**Evidence:** reproducible boot steps, validated ROM identity, device logs, and a record of graphics failures or missing features.

### 5. Exercise gameplay and lifecycle

Map the controller, test input-driven gameplay, investigate audio, and support a controlled return to the harness. Exercise repeated launch/exit, controller loss/reconnect, and suspension/resume.

Where the runtime exposes saves, attempt save/reload and record any format or persistence issues. Durable save recovery remains a separate release gate.

**Evidence:** measured frame timing, memory use, stability, graphics/audio issues, and lifecycle outcomes. Select target resolution and frame-rate expectations only after measuring the device.

## Go/no-go checkpoints

| Checkpoint | Passing evidence | If it fails |
| --- | --- | --- |
| Foundation | C++ executes and Metal presents on physical tvOS hardware | Resolve app/toolchain/device setup |
| Dependencies | Required runtime components have a documented tvOS path | Record blocker and reassess adaptation cost |
| Game boot | Validated ROM reaches a recognizable rendered game screen | Isolate runtime, data, or renderer failure |
| Gameplay feasibility | Controller-driven gameplay and repeatable launch/exit | Fix or rescope before full launcher work |

Passing these checkpoints justifies the next engineering phase. It does not certify full-game compatibility, production performance, save durability, or App Store eligibility.

## Result record

Complete this record after the physical-device experiment; its outcome is still untested. Host checks and CI builds are documented separately in the harness instructions and must not be entered as device results.

- Date and developer:
- App commit:
- Upstream/dependency commits:
- Xcode, SDK, and tvOS versions:
- Apple TV model/chipset and controller:
- ROM region/revision and validation policy:
- Build and private ROM provisioning steps:
- C++ bridge / Metal / dependency results:
- Furthest game state reached:
- Resolution, frame-time observations, memory, and run duration:
- Input, audio, lifecycle, and save results:
- Reproduction steps for failures:
- Decision: proceed, revise, or stop; supporting evidence:

Update [COMPATIBILITY.md](COMPATIBILITY.md) only with outcomes actually observed. Advance the milestones in [ROADMAP.md](ROADMAP.md) when their exit criteria are met.
