# Super Mario 64 / Ghostship

Nativecade includes the [Ghostship source port](https://github.com/HarbourMasters/Ghostship)
at the release pinned in `upstream/ghostship-baseline.json` (3.0.0 on 2026-10-29;
see [Updating game runtimes](UPDATING_UPSTREAM.md)). It runs compiled game code
locally and prepares game assets from the user's imported ROM. No ROM or
extracted game archive is distributed. This integration is new: it runs in the
simulator, but has not been played with a controller or on an Apple TV yet.

## Supported game data

Only the US release is accepted, because Ghostship's game code is built for it:

| Release | Normalized SHA-1 |
|---|---|
| Super Mario 64 (U) | `9bef1128717f958171a4afac3ed78ee2bb4e86ce` |

Import an uncompressed `.z64`, `.v64`, or `.n64` from RomM or SMB. The file's bytes
determine its identity; its name and server metadata do not select a runtime.
The Japanese release, which Ghostship's extractor also reads, is not supported.

## Building

Follow [Nativecade and TestFlight](NATIVECADE_TESTFLIGHT.md). `scripts/upstream.py fetch`
clones Ghostship at its pin into `build/upstream/Ghostship`, and
`scripts/prepare-ghostship.py` writes an adapted copy to `build/ghostship/source`
without changing the checkout. Ghostship 3.0.0 was written for a libultraship
branch whose subsystems (logger, window, resource manager, controller deck and
so on) are components added to the context one at a time. Nativecade's shared
libultraship builds them in `Context::Init`, so the script:

- rewrites the `GameEngine` constructor to create the context the way
  SpaghettiKart's engine does, and rewrites `ShipCompat.cpp`, Ghostship's own
  accessor layer, to read the context's getters;
- moves GUI windows from a component's `OnInit(json)` to `InitElement()`, giving
  windows that had no `OnInit` an empty one;
- follows renamed interfaces: GUI texture loading takes a palette path, the
  graphics debugger window takes only its name, and frame interpolation passes
  matrix replacements but not display-list replacements, as upstream's Switch
  build does;
- skips Ghostship's first-run extractor screens. Nativecade prepares `sm64.o2r`
  before the game starts, so `GameEngine::Create` loads the archives directly;
- turns the touch controls off by default, since an Apple TV has no touchscreen;
- removes the shader-pack menu, which the shared libultraship lacks.

Ghostship is built without `GBI_FLOATS`, like Star Fox, so it shares the fixed-point
Fast3D interpreter; its code keeps the fixed-point paths. Its extraction settings
are shipped with `gbi_floats: false` for the same reason; the setting only changes
its two matrix assets. Networking (`USE_NETWORKING`) and scripting are off.
Upstream compiles the C code without strict aliasing because the camera breaks
otherwise, and so does Nativecade. `NativecadeGhostship.framework` hides its game
symbols, links the shared runtime, and compiles libultraship's `os_pi.cpp`,
`os_vm.cpp` and the event debugger window, which the shared runtime doesn't use.
The shared Torch is built with Super Mario 64 extraction.

`scripts/prepare-ghostship-resources.py` packs Ghostship's support archive,
`ghostship.o2r`, from upstream's `port/` folder with the shared Metal shaders, and
copies `config.yml` and the US extraction definitions.

## Preparation, storage and controls

Preparation rechecks the ROM's hash, extracts `sm64.o2r` with the shared Torch,
and checks the archive before installing it. The result is cached per ROM
and per Ghostship release and Torch revision, so later starts skip extraction.
Super Mario 64 keeps its archives, settings, saves and logs in
`Library/Caches/Nativecade/Games/SuperMario64`. tvOS can purge that folder while
Nativecade isn't running, and its saves have no safety copy yet.

The controls are libultraship's default N64 mapping; they have not been tried
with a controller yet.

## Verification on 2026-10-29

- The framework compiled and linked for the tvOS simulator (arm64). The device
  slice has not been built yet.
- A Super Mario 64 (USA) ROM from the user's RomM was imported and verified.
  The first preparation took a few seconds in the simulator and produced a 10 MB
  `sm64.o2r`.
- On the tvOS 27.0 Apple TV 4K simulator, the Mario head and title logo rendered,
  followed by the "Press Start" screen.
- The restart check passed with Super Mario 64 before and after each other game,
  three times in one session (`mario,oot,mario,kart,fox,mario`), and it rendered
  again when started after Ocarina.
- Not yet checked: gameplay with a controller, audio, saves, performance,
  Address Sanitizer, and anything on a physical Apple TV.
