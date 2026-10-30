# Super Smash Bros. / BattleShip

Nativecade can include the [BattleShip source port](https://github.com/JRickey/BattleShip)
(MIT), a libultraship and Torch port of the complete
[ssb-decomp-re](https://github.com/VetriTheRetri/ssb-decomp-re) decompilation, at the
release pinned in `upstream/battleship-baseline.json` (v1.6, recorded on 2026-10-30; see
[Updating game runtimes](UPDATING_UPSTREAM.md)). It runs compiled game code and prepares
the game's assets on the Apple TV from the player's imported ROM. No ROM, nothing
extracted from one, and no code generated from one is built or distributed.

It is in progress: the framework builds for Apple TV and the simulator and the app prepares and
starts it like the other games, but nothing has run with a ROM yet, because the USA ROM wasn't
in the RomM library available to the build Mac.

## Supported game data

| Release | Normalized SHA-1 |
|---|---|
| Super Smash Bros. (USA) | `e2929e10fccc0aa84e5776227e798abc07cedabf` |

That is NTSC-U 1.0 (game code NALE, internal name `SMASH BROTHERS`, MD5
`f7c52568a31aadf26e14dc2b6416b2ed`). BattleShip compiles one region per build, and
Nativecade builds the US one (`SSB64_VERSION=us`). The Japanese release would need a
second framework. Import an uncompressed `.z64`, `.v64` or `.n64` from RomM or SMB.

## Its own libultraship and Torch

The other games share one libultraship and one Torch, pinned by Lighthouse. BattleShip
can't use them:

- Its libultraship ([JRickey/libultraship](https://github.com/JRickey/libultraship), branch
  `ssb64`) forked Kenix3's in April 2026 and adds 177 commits (about 21,000 changed lines
  in 97 files): Fast3D interpreter hooks the port registers (`Fast::RegisterDLBoundsCheck`,
  `Fast::RegisterAddressClassifier`, framebuffer capture), widescreen and scissor bridge
  functions, post-processing, Raphnet adapters. Its `Ship::Context` still hands out
  `std::shared_ptr`s (`GetInstance()`, used 55 times in the port), where the shared copy
  uses `GetRawInstance()`.
- Its Torch ([JRickey/Torch](https://github.com/JRickey/Torch), branch `ssb64`) adds the
  SSB64 relocatable-file factory and VPK0 decompression, which the shared Torch doesn't
  have.

So `experiments/battleship` is a CMake project of its own (the shared runtime's project
already has targets named `libultraship`, `torch` and `ImGui`). It builds BattleShip's
libraries into `NativecadeBattleShip.framework` with hidden symbols, exports only
`NativecadePrepareSuperSmashBros`, and links `NativecadeRuntime.framework` last, so the
only symbols bound to it are SDL's and the game-runner API (`NativecadeSetPreparedGameRunner`,
`NativecadeRemoveOutdatedPreparations`). SDL's headers and build configuration come from the
shared runtime's build for the same SDK. ImGui's Metal backend is compiled with its three
Objective-C class names changed, since the shared runtime registers the originals.

The libraries libultraship downloads are taken from the shared runtime's build when it has
the same commit (ImGui, nlohmann/json, tinyxml2, spdlog, libzip, thread-pool, metal-cpp,
prism). Its ImGui carries the same patches as BattleShip's except Android-only guards and a
clear for floating viewports, which tvOS doesn't use. Torch's yaml-cpp is downloaded.

## Building

Build the shared runtime first (`scripts/build-nativecade-runtime.sh`). Then:

```sh
python3 scripts/upstream.py fetch
python3 scripts/prepare-battleship.py build/nativecade-runtime/NativecadeGame/BattleShip
cmake -S experiments/battleship -B build/nativecade-runtime/appletvsimulator/battleship -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT=appletvsimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_FIND_ROOT_PATH="$(xcode-select -p)/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator.sdk"
cmake --build build/nativecade-runtime/appletvsimulator/battleship --target NativecadeBattleShip
```

For Apple TV use `appletvos` and the `AppleTVOS` SDK path. `upstream.py fetch` checks out
BattleShip and its three submodules (`decomp`, `libultraship`, `torch`) inside
`build/upstream/BattleShip`. `scripts/prepare-battleship.py` writes an adapted copy to
`build/battleship/source` without changing those checkouts, and
`experiments/battleship/CMakeLists.txt` builds it with BattleShip's own options for the US
release. Compared with a desktop build, they:

- leave out the first-run extractor and its file dialog, which run Torch and `osascript`
  as processes: Nativecade prepares `BattleShip.o2r` before Play. If it is missing, the
  game returns to the library;
- leave out the updater, Discord Rich Presence and the shader-pack downloader, and hide
  their menu entries, the post-processing picker, windowed fullscreen and texture-dump
  tools, as BattleShip's Android build does. The menu's Quit button stays;
- build without mods (`DISABLE_SCRIPTING`): no TinyCC compiler or funchook, so no code is
  generated at run time. The Raphnet adapter code gets the no-op hidapi Android uses;
- make libultraship take its iOS paths on tvOS, without OpenGL, the macOS fullscreen and
  Core Audio code, or the ios-cmake toolchain; keep its files in the folder Nativecade
  names (`NATIVECADE_GAME_DIRECTORY`); leave `SDL_Quit` to Nativecade; and skip depth
  clamping in the simulator, as the shared libultraship does;
- write the log and the save beside the game's files instead of asking `SDL_GetPrefPath`,
  which shows a storage alert on tvOS; make the debug texture-dump folder without a shell;
  and keep the hang watchdog but not its process-wide crash handlers, which would outlive
  the game (tvOS has no `sigaltstack` either);
- add functions that reset the game loop's and the menu's cached state, so the game can
  start again in the same session (below);
- encode the staff roll from the decomp's own credits text, as upstream's build does, and
  write the stage-select arrow headers from BattleShip's arrow images (upstream uses
  Pillow for that).

The other Metal fixes in the shared libultraship (`experiments/shipwright/metal`:
rendering robustness, performance and rumble) are not ported to BattleShip's copy.

The relocatable-data headers are BattleShip's committed files (`include/reloc_data.us.h`,
`port/resource/RelocFileTable.us.cpp`). They hold symbol names, file IDs and offsets from
`tools/reloc_data_symbols.us.txt`, which ssb-decomp-re publishes, not ROM bytes; running
upstream's generators on the committed inputs reproduces them byte for byte.

The same script packs the support files the app bundles into `NativecadeGame/BattleShip`:
Torch's `config.yml` and US extraction definitions (`yamls/us`), `f3d.o2r` (the Fast3D
shaders of BattleShip's libultraship), the Montserrat and Inconsolata menu fonts, and the
licence.

Upstream's desktop build also extracts stage-select pictures for the stages the port adds
(Final Destination, Metal Cavern, Battlefield) from the ROM with a Python script. Nativecade
doesn't, like upstream's packaged releases: those stages show a question mark and their
ROM wallpaper.

## Preparation, storage and controls

Preparation rechecks the ROM's hash and extracts `BattleShip.o2r` with the framework's
Torch, as BattleShip's Android build does on the device. The archive is checked (at least
2,000 entries, each read in full) and cached per ROM and per BattleShip release and Torch
revision, in `Library/Caches/Nativecade/Prepared/BattleShip-v1.6-torch8060a90`, so later
starts skip extraction. It is installed with the shaders and fonts into
`Library/Caches/Nativecade/Games/SuperSmashBros`, which also holds the settings
(`BattleShip.cfg.json`), saves (`ssb64_save.bin`) and logs. tvOS can purge that folder
while Nativecade isn't running, and the saves have no safety copy yet.

The first-run wizard never appears. BattleShip v1.6's netplay is an experimental UDP peer
started only by `SSB64_NETPLAY` environment variables, with no menu; it stays compiled in
and unused. The controls are BattleShip's defaults on libultraship's N64 mapping.

## Switching games

`NativecadeRunSuperSmashBros` runs BattleShip's `main` and then resets what its startup
doesn't rebuild: the relocatable-data token table, whose pointers belong to the ended
game's resources; the game loop's pending display list and counters; and the menu's
cached fonts, which belong to the ended ImGui context. The decomp's and the port's C
globals are restored by `GameStateSection.h`, as for the other games. BattleShip's own
context, logger and window are destroyed by its `PortShutdown`; Nativecade then quits
SDL. Known gaps, all unchecked: the hang watchdog only runs during the first start, and
the coroutine stacks of the emulated N64 threads (256 KB each) aren't freed between
starts.

## Verification on 2026-10-30

- `NativecadeBattleShip.framework` compiled (935 build steps, Release) and linked for the
  tvOS simulator and Apple TV, arm64, tvOS 17.0 minimum; about 7.6 MB each.
- It links Foundation, UIKit, Core Foundation, AVFoundation, Metal, Quartz Core, Core
  Audio, Audio Toolbox, libz and `NativecadeRuntime`; no AppKit, Cocoa, OpenGL or OpenGL ES.
- It exports only `NativecadePrepareSuperSmashBros` and no weak definitions. Of the 102
  symbols bound to `NativecadeRuntime`, 100 are SDL functions, all exported by the current
  runtime, and two are the game-runner API. Its Objective-C classes are ImGui's three,
  renamed.
- There is no Super Smash Bros. ROM on the build Mac, the build reads none, and the
  relocatable-data headers regenerate identically from their committed inputs.
- Not yet checked: the app calling the framework, preparation with a ROM, rendering,
  audio, controls, saves, restarts, performance and anything on a physical Apple TV.
