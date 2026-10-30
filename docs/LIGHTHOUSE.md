# Banjo-Kazooie / Lighthouse

Nativecade includes the [Lighthouse source port](https://github.com/HarbourMasters/Lighthouse)
at the release pinned in `upstream/lighthouse-baseline.json` (1.2.2 "Montauk
Charlie" on 2026-10-29; see [Updating game runtimes](UPDATING_UPSTREAM.md)). It
runs compiled game code locally and prepares game assets from the user's
imported ROM. No ROM or extracted game archive is distributed.

## Supported game data

Lighthouse plays every retail release, so all four are accepted:

| Release | Normalized SHA-1 |
|---|---|
| Banjo-Kazooie (USA) | `1fe1632098865f639e22c11b9a81ee8f29c75d7a` |
| Banjo-Kazooie (USA) (Rev 1) | `ded6ee166e740ad1bc810fd678a84b48e245ab80` |
| Banjo-Kazooie (Europe) | `bb359a75941df74bf7290212c89fbc6e2c5601fe` |
| Banjo to Kazooie no Daibouken (Japan) | `90726d7e7cd5bf6cdfd38f45c9acbf4d45bd9fd8` |

Import an uncompressed `.z64`, `.v64`, or `.n64` from RomM or SMB. The file's bytes
determine its identity; its name and server metadata do not select a runtime.
Romhacks and Lighthouse's language packs are not supported.

## Shared libraries

Lighthouse needs newer shared libraries than the other games: Torch's
Banjo-Kazooie extraction, and the libultraship branch Lighthouse ships
([JeodC/libultraship](https://github.com/JeodC/libultraship)), which adds N64
mipmaps and a few fixes on top of the libultraship the other games used. All
games build against one copy of each, so Lighthouse's version file now pins
both for every game, and the other games were rechecked with them. Our tvOS
patches to libultraship applied to the newer branch unchanged.

## Building

Follow [Nativecade and TestFlight](NATIVECADE_TESTFLIGHT.md). `scripts/upstream.py fetch`
clones Lighthouse at its pin into `build/upstream/Lighthouse`, and
`scripts/prepare-lighthouse.py` writes an adapted copy to `build/lighthouse/source`
without changing the checkout. Lighthouse 1.2.2 was written for the same
libultraship interface the shared runtime uses, so the script changes little:

- skips Lighthouse's first-run extractor. Nativecade prepares `bk.o2r` before the
  game starts, so `GameEngine::Create` loads the archives directly;
- removes the relaunch after a settings change, since an Apple TV app can't
  replace its own process;
- builds `guMtxIdent` from the fixed-point conversion, like the other `gu`
  functions, and declares controller button masks with the shared
  libultraship's 32-bit type;
- fixes one include path that went through upstream's libultraship submodule
  folder;
- writes `src/port/build.c`, the version strings upstream's CMake generates;
- adds functions that clear the main loop's and the N64 thread layer's shutdown
  flags, so the game can start again in the same session
  ([Switching games](GAME_SWITCHING.md)).

Lighthouse is built without `GBI_FLOATS`, like Star Fox and Super Mario 64, so it
shares the fixed-point Fast3D interpreter; its code keeps the fixed-point paths.
Networking (`USE_NETWORKING`) is off, so Anchor multiplayer is unavailable. File
pickers use libultraship's built-in browser (`LIGHTHOUSE_NATIVE_FILE_DIALOG=0`),
as on consoles. Upstream's CMake script generates the Flag Tracer's name tables.
`NativecadeLighthouse.framework` hides its game symbols, links the shared
runtime, and compiles libultraship's `os_pi.cpp`, `os_vm.cpp` and graphics
bridge, which the shared runtime doesn't use. The shared Torch is built with
Banjo-Kazooie extraction.

`scripts/prepare-lighthouse-resources.py` packs Lighthouse's support archive,
`lighthouse.o2r`, from upstream's `port/` folder with the shared Metal shaders,
and copies `config.yml` and the extraction definitions for all four releases.

## Preparation, storage and controls

Preparation rechecks the ROM's hash, extracts `bk.o2r` with the shared Torch,
stamps it with the Lighthouse version as Lighthouse's own extractor does, and
checks the archive before installing it. The result is cached per ROM and per
Lighthouse release and Torch revision, so later starts skip extraction.
Banjo-Kazooie keeps its archives, settings, saves and logs in
`Library/Caches/Nativecade/Games/BanjoKazooie`. tvOS can purge that folder while
Nativecade isn't running, and its saves have no safety copy yet.

The controls are Lighthouse's defaults on libultraship's N64 mapping.

## Verification on 2026-10-30

- The framework compiled and linked for the tvOS simulator (arm64). The device
  slice has not been built yet.
- A Banjo-Kazooie (USA) (Rev 1) ROM from the user's RomM was imported and
  verified. The first preparation took a few seconds in the simulator and
  produced a 26 MB `bk.o2r`, which Lighthouse identified as US 1.1.
- On the tvOS 27.0 Apple TV 4K simulator, the port's splash screen and the
  opening scene in Spiral Mountain rendered in widescreen.
- The restart check passed with Banjo-Kazooie first, twice in a row, after
  Ocarina, and after the other three games
  (`banjo,banjo,oot,banjo,kart,fox,mario,banjo`). Its first attempt crashed on a
  graphics task left pending at Quit, which the reset now clears.
- With the shared libraries moved to Lighthouse's, the four other games passed
  the restart check, and each rendered its title or opening.
- Not yet checked: gameplay with a controller, audio, saves, performance,
  Address Sanitizer, and anything on a physical Apple TV.
