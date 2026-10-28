# Runtime audit and simulator experiment

**Baseline: 2026-10-28.** Development continues on the tvOS Simulator at the
maintainer's request. The foundation bridge and visible blue/green/red checks
were confirmed by the maintainer; hardware validation remains deferred. This
audit does not establish game compatibility.

## Selected source snapshot

The audit follows the submodules recorded by Zelda64Recomp, rather than mixing
the current heads of its dependencies. Exact revisions and the gitlinks inspected
in these four repositories are in [audit-baseline.json](../upstream/audit-baseline.json).
The JSON is an audit baseline, not a complete recursive SBOM or an app dependency
lockfile. No upstream runtime is linked into the RecompTV application yet.

| Component | Audited commit | Role | License text inspected |
| --- | --- | --- | --- |
| [Zelda64Recomp](https://github.com/Zelda64Recomp/Zelda64Recomp/tree/b65c482ed672258eb684ab94a4e8c8aa662615ee) | `b65c482ed672258eb684ab94a4e8c8aa662615ee` | Game integration, patches, desktop host | GPL v3, `COPYING` |
| [N64ModernRuntime](https://github.com/N64Recomp/N64ModernRuntime/tree/df7e820d8c55e4fcb4616c210cbb2c01b25cd48c) | `df7e820d8c55e4fcb4616c210cbb2c01b25cd48c` | `ultramodern` services and `librecomp` | GPL v3, `COPYING` |
| [RT64](https://github.com/rt64/rt64/tree/23cab603c4f9f4a8b369b38e036f1aa484603878) | `23cab603c4f9f4a8b369b38e036f1aa484603878` | Renderer and shader build pipeline | MIT, `LICENSE` |
| [N64Recomp](https://github.com/N64Recomp/N64Recomp/tree/c1a6dc93bfa5977de0ea256562058be4f1b73353) | `c1a6dc93bfa5977de0ea256562058be4f1b73353` | Host recompiler, plus a separate live-recompiler library | MIT, `LICENSE` |

License identifiers here describe the root license texts, not a completed
redistribution review. The selected distribution package must also account for
vendored files, subdependencies, notices, and any different per-file terms. The
project's own license is still unselected.

## Findings and adaptation boundaries

| Area | Source evidence | tvOS implication / next action |
| --- | --- | --- |
| Ahead-of-time game code | Zelda's [build guide](https://github.com/Zelda64Recomp/Zelda64Recomp/blob/b65c482ed672258eb684ab94a4e8c8aa662615ee/BUILDING.md) runs `N64Recomp` and `RSPRecomp` before compiling generated C/C++ | Keep generation on the development host. Generated game code and private ROM inputs are outside this public experiment. |
| Core runtime services | [`ultramodern/CMakeLists.txt`](https://github.com/N64Recomp/N64ModernRuntime/blob/df7e820d8c55e4fcb4616c210cbb2c01b25cd48c/ultramodern/CMakeLists.txt) is a separate C++20 static library with input, audio, messages, timers, threads, and renderer interfaces | Compile this target alone first. No SDL, RT64, ROM, or recompiler submodule is required for this isolated target. |
| Live recompilation | [`librecomp/CMakeLists.txt`](https://github.com/N64Recomp/N64ModernRuntime/blob/df7e820d8c55e4fcb4616c210cbb2c01b25cd48c/librecomp/CMakeLists.txt) unconditionally links `N64Recomp` and `LiveRecomp`; [`recomp.cpp`](https://github.com/N64Recomp/N64ModernRuntime/blob/df7e820d8c55e4fcb4616c210cbb2c01b25cd48c/librecomp/src/recomp.cpp) initializes the live recompiler | The current full target does not meet our ahead-of-time-only boundary. Introduce a real build-time separation; a disabled menu option is insufficient. |
| Executable patching / native mods | [`mods.cpp`](https://github.com/N64Recomp/N64ModernRuntime/blob/df7e820d8c55e4fcb4616c210cbb2c01b25cd48c/librecomp/src/mods.cpp) changes code protection, patches functions, and can load native-library mods. Zelda's [CMake](https://github.com/Zelda64Recomp/Zelda64Recomp/blob/b65c482ed672258eb684ab94a4e8c8aa662615ee/CMakeLists.txt) uses a macOS linker wrapper for writable executable memory | Exclude these paths from a tvOS runtime. Convert required built-in patches to build-time code/static dispatch; audit the final linked binary. Simulator success must not justify retaining desktop code-patching behavior. |
| Desktop window ownership | Zelda's [`main.cpp`](https://github.com/Zelda64Recomp/Zelda64Recomp/blob/b65c482ed672258eb684ab94a4e8c8aa662615ee/src/main/main.cpp) creates SDL windows and reads Cocoa window handles; [`support_apple.mm`](https://github.com/Zelda64Recomp/Zelda64Recomp/blob/b65c482ed672258eb684ab94a4e8c8aa662615ee/src/main/support_apple.mm) patches an SDL Cocoa view method | Retain the SwiftUI/UIKit app lifecycle and supply a tvOS window/layer adapter. Do not embed the desktop `main`. |
| RT64 Apple backend | [`rt64_apple.mm`](https://github.com/rt64/rt64/blob/23cab603c4f9f4a8b369b38e036f1aa484603878/src/apple/rt64_apple.mm) imports AppKit and uses `NSWindow` / `NSScreen` | This translation unit cannot be used as the tvOS host adapter. Separate window size, refresh rate, and fullscreen behavior from renderer code. |
| GPU feature checks | [`rt64_metal.cpp`](https://github.com/rt64/rt64/blob/23cab603c4f9f4a8b369b38e036f1aa484603878/src/metal/rt64_metal.cpp) uses `CopyAllDevices`, Mac2/Apple6 family checks, desktop vsync access, and working-set queries. Zelda's README requires argument buffers tier 2 | Audit each API against the tvOS SDK and test the required resource bindings. A clear pass does not prove RT64 support. Simulator GPU capabilities describe the host, not an Apple TV. |
| Shader pipeline | RT64's [CMake](https://github.com/rt64/rt64/blob/23cab603c4f9f4a8b369b38e036f1aa484603878/CMakeLists.txt) runs DXC, SPIRV-Cross, then `xcrun -sdk macosx metal/metallib`; [`spirv_cross_msl.cpp`](https://github.com/rt64/rt64/blob/23cab603c4f9f4a8b369b38e036f1aa484603878/src/tools/spirv_cross_msl/spirv_cross_msl.cpp) selects MSL 2.1 and argument buffers | Build conversion tools for the Mac host, with shader outputs separately targeted to `appletvsimulator` and later `appletvos`. Do not reuse macOS metallibs or cross-compile tools that must execute during the build. |
| Audio and input | [`ultramodern.hpp`](https://github.com/N64Recomp/N64ModernRuntime/blob/df7e820d8c55e4fcb4616c210cbb2c01b25cd48c/ultramodern/include/ultramodern/ultramodern.hpp) and [`input.hpp`](https://github.com/N64Recomp/N64ModernRuntime/blob/df7e820d8c55e4fcb4616c210cbb2c01b25cd48c/ultramodern/include/ultramodern/input.hpp) expose callbacks; Zelda supplies SDL implementations | Use these boundaries for future Apple audio and controller adapters. The experiment tests callback semantics with synthetic input and samples, not hardware input or audible output. |
| Desktop UI / dialogs | Zelda links RmlUi, lunasvg, FreeType, and nativefiledialog; RT64 also links nativefiledialog | Keep desktop UI out of the initial app host. Removing dialogs from the renderer requires a source/build split. Pins are recorded; transitive license/platform review remains open. |
| Threads / lifecycle / files | `ultramodern` uses native threads, queues, timers, filesystem types, and host callbacks | An archive build cannot validate event-loop shutdown, suspension, sandbox paths, saves, memory use, or timing. Exercise these after the host adapter exists. |

The source audit supports a **staged porting experiment**, not a drop-in import
of the upstream desktop target. The full runtime and renderer remain unported.

The core-services experiment subsequently passed its host callback tests and both
simulator architecture builds in [CI at `94aa928`](https://github.com/smidley/atv-recomp/actions/runs/40743318116).
The next source adaptation is tracked in the [RT64 Metal experiment](RT64_METAL_EXPERIMENT.md).

## ROM identity is a later gate

The pinned build guide identifies the normal US ROM by SHA-1
`d6133ace5afaa0882cf214cf88daba39e266c078`, and requires a decompressed copy only
for host code generation. Its runtime uses the ordinary ROM. The registered
game in `main.cpp` is `mm.n64.us.1.0` with the upstream `rom_hash` value
`0xEF18B4A9E2386169`. That integer is **not** a SHA-256 identifier.

These are source observations, not a new RecompTV acceptance policy. Before
ROM loading, define canonical byte order, length limits, exact digest algorithm,
and normalization tests. No ROM, decompressed input, or generated game output is
needed by this experiment or sent to CI.

## Reproduce the isolated core experiment

The experiment requires Git, Python 3, CMake 3.20+, Make, and a C++20 compiler.
Simulator compilation additionally requires macOS with Xcode and its tvOS SDK.
Start in this repository and create a separate checkout under ignored `build/`:

```sh
git clone --no-checkout https://github.com/N64Recomp/N64ModernRuntime.git build/upstream/N64ModernRuntime
git -C build/upstream/N64ModernRuntime checkout --detach df7e820d8c55e4fcb4616c210cbb2c01b25cd48c

# Compile the whole core archive; run the input/audio callback fixture on the host.
bash scripts/check-runtime-core.sh host build/upstream/N64ModernRuntime

# Compile and link for each simulator architecture. These commands do not launch it.
bash scripts/check-runtime-core.sh simulator build/upstream/N64ModernRuntime arm64
bash scripts/check-runtime-core.sh simulator build/upstream/N64ModernRuntime x86_64
```

No recursive submodule checkout is needed. The wrapper rejects an incorrect
revision or a checkout with local changes before building. Its output stays
under `build/runtime-core/`. It does not change the Xcode app or download files
when the app builds.

The [workflow](../.github/workflows/runtime-core.yml) repeats this experiment in
CI. Record successful runs for the exact commit; the workflow's existence is not
evidence that compilation succeeded.

The callback fixture links the real upstream input/audio object files from the
core archive. It checks press/release, analog conversion, disconnect/reconnect,
missing callbacks, audio sample counts, emulated address translation, and queue
accounting. Its SI-message function is explicitly a test double. The remaining
core objects are compiled but are not forced into the linked executable. This
does not test the event scheduler, the full runtime link, game boot, or rendering.

## Next simulator work

1. Core compile/link checks and host callback tests passed; retain these regressions.
2. Continue the isolated RT64 Metal backend and shader experiment, then validate
   GPU execution and presentation in a simulator app.
3. Design a static-only `librecomp` build without LiveRecomp, executable patching,
   or native-mod loading; verify the resulting binary's dependencies and symbols.
4. Connect a minimal app host, then add private ROM validation and a real game
   boot experiment once the renderer and static runtime paths can link.

Physical-device checks resume when hardware is available. They remain required
for device compatibility, graphics correctness, performance, and save/lifecycle
claims, but do not block this simulator engineering work.
