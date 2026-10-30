# Star Fox 64 / Starship

Nativecade includes the [Starship source port](https://github.com/HarbourMasters/Starship)
at the release pinned in `upstream/starship-baseline.json` (v2.0.0 on 2026-10-29;
see [Updating game runtimes](UPDATING_UPSTREAM.md)). It runs compiled game code
locally and prepares game assets from the user's imported ROM. No ROM or
extracted game archive is distributed. This integration is new: it runs in the
simulator, but has not been played with a controller or on an Apple TV yet.

## Supported game data

Only the US releases are accepted, matching Starship's own extraction
definitions:

| Release | Normalized SHA-1 |
|---|---|
| Star Fox 64 (U) (V1.0) | `d8b1088520f7c5f81433292a9258c1184afa1457` |
| Star Fox 64 (U) (V1.1) | `09f0d105f476b00efa5303a3ebc42e60a7753b7a` |

Import an uncompressed `.z64`, `.v64`, or `.n64` from RomM or SMB. The file's bytes
determine its identity; its name and server metadata do not select a runtime.
Japanese, European and Chinese releases, and Starship's optional voice packs
made from them, are not supported.

## Building

Follow [Nativecade and TestFlight](NATIVECADE_TESTFLIGHT.md). `scripts/upstream.py fetch`
clones Starship at its pin into `build/upstream/Starship`, and
`scripts/prepare-starship.py` writes an adapted copy to `build/starship/source`
without changing the checkout. Starship v2.0.0 was written for an older
libultraship and Torch than the ones Nativecade shares among its games, so the
script:

- maps the older libultraship header paths (for example `Resource.h` to
  `ship/resource/Resource.h` and `Fast3D/` to `fast/`);
- uses libultraship's event system, which the context now owns, in place of
  Starship's own copy, keeping Starship's `REGISTER_LISTENER` argument order;
- follows renamed interfaces: texture lookup on `Fast3dGui`, the control deck's
  button names, the audio channel setting, and Torch's `Companion` constructor;
- loads music sequences in the format the shared Torch writes (`SEQC` version 2,
  since Torch `4e021e10`) with libultraship's blob reader, because Starship v2.0.0
  expected plain blobs. Without it every sequence failed to load and the audio
  thread crashed;
- adds `NativecadeStarshipReset` for game switching
  ([Switching games](GAME_SWITCHING.md)).

Star Fox is built without `GBI_FLOATS`, so it uses the same fixed-point
matrices as the other games and shares their Fast3D interpreter.
`NativecadeStarship.framework` hides its game symbols and links the shared
runtime. Like Mario Kart, it compiles its own `os_pi.cpp` and an F3DEX
display-list XML factory. The shared runtime gains libultraship's event bridge,
and its Torch is built with Star Fox extraction.

`scripts/prepare-starship-resources.py` packs Starship's own support archive,
`starship.o2r`, from upstream's `port/` folder with the shared Metal shaders. It
also copies `config.yml` and the US extraction definitions.

## Preparation, storage and controls

Preparation rechecks the ROM's hash, extracts `sf64.o2r` with the shared Torch,
and checks the archive before installing it. The result is cached per ROM
revision and per Starship release and Torch revision, so later starts skip
extraction. Star Fox uses `Documents/StarFox64` for its archives, settings,
saves and logs.

Starship's default controller mapping, in N64 terms: A is A, X is B, Menu is
Start, Y or the right trigger is C-left, B or the left trigger is C-down, the
right stick gives C-up and C-right, the left shoulder is Z and the right shoulder
is R. The port's settings menu has no input editor in this build; it logs
"Could not find input editor window".

## Verification on 2026-10-29

- The framework compiled and linked for the tvOS simulator (arm64). CI builds the
  device slice; it has not been built locally yet.
- A Star Fox 64 (U) (V1.1) ROM from the user's RomM was imported and verified.
  The first preparation took about 20 seconds in the simulator.
- On the tvOS 27.0 Apple TV 4K simulator, the Nintendo 64 logo and the title
  cutscene rendered in widescreen, with General Pepper's radio messages. The
  audio thread mixed sequence notes; the sound itself was not checked.
- The restart check passed with Star Fox three times among the other games.
- Not yet checked: gameplay with a controller, saves, performance, Address
  Sanitizer, and anything on a physical Apple TV.
