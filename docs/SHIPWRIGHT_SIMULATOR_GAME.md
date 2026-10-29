# Shipwright simulator game experiment

This private development target boots the pinned Shipwright 9.3.1 runtime with a
locally verified ROM on Apple TV Simulator. It is separate from the RecompTV launcher
and rejects a physical-device SDK. The existing RomM connection and launcher cache
are independent of this experiment. The newer [Nativecade target](NATIVECADE_TESTFLIGHT.md) integrates a Play action,
on-device preparation, and device packaging without bundling ROM assets. Return
to the library currently requires closing and reopening Nativecade. The game now has local save recovery, RomM
backups, and controller vibration settings; see
[Saves and controllers](APPLE_TV_SAVES_AND_CONTROLLERS.md).

## Build the host asset tools

Use the exact clean checkouts recorded in `upstream/shipwright-baseline.json` under
`build/upstream/Shipwright`, `build/upstream/Torch` and `build/upstream/libultraship`;
`python3 scripts/upstream.py fetch` creates them.
CMake 3.26 or newer and Ninja must be on PATH. A local Python virtual environment
can supply both without changing the system installation.

```sh
cmake -S experiments/shipwright/host-tools -B build/shipwright-tools -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DRECOMPTV_SHIPWRIGHT_SOURCE="$PWD/build/upstream/Shipwright" \
  -DRECOMPTV_TORCH_SOURCE="$PWD/build/upstream/Torch"
cmake --build build/shipwright-tools --target soh-torch soh-o2r-packer --parallel 5
```

The pinned upstream CLI passes a path to an API that now requires a byte vector.
`ExtractROM.cpp` provides a bounded input adapter and keeps the checkout unchanged.
Its input must be a previously verified big-endian ROM, such as the launcher's
canonical cache copy. All asset-tool dependencies are pinned to commits.

```sh
python3 scripts/identify-shipwright-rom.py LocalData/shipwright/oot.z64
build/shipwright-tools/soh-torch LocalData/shipwright/oot.z64 \
  build/upstream/Shipwright/soh/assets/yml LocalData/shipwright/assets
```

Prepare the port's own archive from a separate staging copy of
`Shipwright/soh/assets/custom`, adding libultraship's `src/fast/shaders` as its
`shaders` directory. Run `soh-o2r-packer STAGING_DIRECTORY
LocalData/shipwright/assets/soh.o2r 9.3.1`. Do not modify either clean checkout.

Both `oot.o2r` and `soh.o2r` must pass ZIP CRC checks and contain the 7-byte 9.3.1
`portVersion` record. ROMs, archives, extraction caches and private app bundles
belong only in ignored `LocalData/` or `build/`; never upload them as CI artifacts.

## Build the simulator app

```sh
bash scripts/check-shipwright-game.sh build/upstream/Shipwright \
  build/upstream/Torch build/upstream/libultraship
```

The experiment compiles the actual game, Torch, libultraship, SDL2, Metal,
SDL2_net and audio decoders for arm64 tvOS Simulator. It preserves the game's
floating-point requirements and uses the 32-bit controller-button ABI throughout.
The game patch disables the desktop process-based file picker on tvOS and checks
the complete prepared-archive version before entering the game. SDL supplies the
UIKit entry point. A scoped SDL patch adopts the scene lifecycle required by
tvOS 27: it starts the game after scene activation, associates the SDL window with
that scene and forwards scene notifications to SDL's existing lifecycle handling.
Assets are prepared on the development Mac; gameplay runs in the simulator.

Copy the two private archives into the generated `.app`, then sign it with its
simulator-only Keychain identity before installing on an Apple TV simulator:

```sh
python3 scripts/sign-shipwright-simulator.py \
  build/shipwright-game/simulator-arm64/RecompTVShipwright.app
```

Repeat signing after rebuilding or changing bundled assets. This helper refuses
physical-device binaries and does not modify team signing or device profiles.
The app's identifier is
`com.smidley.RecompTVShipwrightExperiment`. On its first launch it stages those
archives into its own data container. Its main function checks for both archives
before entering the game. Existing saves and configuration are retained.

The private bundle and generated assets are not a distributable application.
All upstream source and dependency notices remain in their pinned checkouts.

## Local evidence

- A ROM imported from the intended RomM server matches NTSC 1.0 (US), SHA-1
  `ad69c91157f6705e8ab06c79fe08aad47bb57ba7`.
- The independent host validator confirms the same identity and 32 MiB size.
- Host extraction produced `oot.o2r` (38,415 entries); the port packer produced
  `soh.o2r` (1,056 entries). Both passed ZIP CRC checks and contain port version 9.3.1.
- The existing complete libultraship/Metal arm64 simulator link check passed.
- The full game compiled and linked for arm64 tvOS Simulator, with no desktop or
  OpenGL framework dependencies. The app passed ad-hoc signature verification.
- The documented preparation/build script was run again successfully from the
  clean pinned checkouts, including patch application and the final framework check.
- On 2026-10-28, the test app launched on an Apple TV 4K (3rd generation) simulator
  with tvOS 27.0. It loaded both archives, rendered the opening game sequence and
  initialized stereo SDL audio at 32 kHz. Audible quality has not been evaluated.
- The user confirmed that controls respond. A new game save was written inside
  the test app's own container and retained byte-for-byte across app replacements.

The first launch exposed SDL2's legacy app lifecycle, which tvOS 27 rejects. The
scene adapter fixes that startup crash. The next launch exposed an unconditional
desktop extractor-directory check; the tvOS path instead requires the prepared
9.3.1 archives and then uses the normal game initialization and resource loading.
See Apple's [scene lifecycle migration guidance](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle).

The app appears as **Shipwright Test** in the simulator. Keep it open to continue
testing. Default keyboard bindings are Space for Start, X for A, C for B, WASD for
the stick, arrows for C buttons, Z for Z, E for L and R for R. A game controller can
also be configured through Shipwright. Audio quality, sustained frame timing,
background/resume and integration into RecompTV's Play flow remain unverified.

Apple TV graphics presets, renderer optimizations, settings migration, and
frame-time diagnostics are documented in [APPLE_TV_PERFORMANCE.md](APPLE_TV_PERFORMANCE.md).

No physical Apple TV or performance claim follows from these checks.
