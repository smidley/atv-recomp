# Cruis'n USA and Cruis'n World

Nativecade includes Cruis'n USA and Cruis'n World through navjack's N64Recomp setups:
[cruisn-recomp](https://github.com/navjack/cruisn-recomp) (the shared workspace: host code and
runtime patches), [cruisn-usa-recomp](https://github.com/navjack/cruisn-usa-recomp) and
[cruisn-world-recomp](https://github.com/navjack/cruisn-world-recomp) (each game's configuration and
symbol file), at the commits pinned in `upstream/cruisn-baseline.json`. Like
[Racer](RACER.md), their code would normally be generated from the ROM, so Nativecade runs it from
the player's ROM with the [N64 interpreter](N64_INTERPRETER.md). The build holds navjack's Controller
Pak code and patches, Racer's runtime, renderer and frontend, and tables written from navjack's
configurations; none of it comes from a ROM.

It is in progress: both games build into `NativecadeCruisn.framework` for Apple TV and the simulator,
and the app lists them, but neither has run with a ROM yet, because neither ROM is in the RomM
library available to the build Mac.

## Supported game data

navjack's configurations describe one release of each game (the SHA-1 in each repository's
`splat.yaml`):

| Release | SHA-1 |
|---|---|
| Cruis'n USA (USA) (Rev 2) | `54a875ee0b482036fa401a6bc2b242699f0259f7` |
| Cruis'n World (USA) | `6da1a6a2bda687d50e798d80c342948ad1738202` |

The earlier Cruis'n USA revisions have their code at other addresses, so they aren't accepted.

## Versions

navjack publishes no releases, so the version file pins commits of `main` (`"releases": false`; the
weekly release check reports the pin and skips it), and updates are made by hand
([Updating game runtimes](UPDATING_UPSTREAM.md)). The runtime, renderer, recompiler lists and
frontend are Racer's pins of sp00nznet's forks, listed again in Cruis'n's version file, so the two
games can't drift apart from Racer without the upstream tests noticing.

navjack builds on N64ModernRuntime `cdf5abb` and RT64 `5473732`, which Racer's forks contain: they
are 10 and 9 commits older than Racer's pins. Cruis'n uses Racer's commits instead, with navjack's
patches on top, so no second copy of either is checked out.

## How it is adapted

`scripts/prepare-cruisn.py` copies the runtime, renderer and Racer's frontend to
`build/cruisn/source` without changing the checkouts, then:

- applies navjack's runtime patch (`N64ModernRuntime-cruisn-runtime.patch`: guest thread shutdown,
  interrupt and clock scheduling points, the audio interface's own clock, PIF RAM and cartridge reads,
  fixed-address overlays loaded by DMA, and uncached addresses mapped onto RDRAM) a hunk at a time.
  Five hunks meet code that Racer's newer commits changed (the COP0 status register, `osGetCount`,
  `send_si_message`, external-message waits and the timer thread); the script makes their changes
  itself and stops if any other hunk fails to apply. navjack's patch also brings its own
  `osPiReadIo`, which replaces Racer's;
- applies navjack's RT64 patch (Cruis'n's graphics microcode is F3DEX2; framebuffers are never
  copied to address 0) and the part of navjack's N64Recomp patch that keeps every COP0 register in
  `recomp_context`, which the runtime and the interpreter (`N64INTERP_COP0_REGISTERS`) share;
- applies the tvOS changes Racer gets (`scripts/rt64_tvos.py`), including those to the frontend;
- calls the interpreter whenever the runtime copies cartridge data into RDRAM, so navjack's 32
  instruction patches in Cruis'n USA's overlay are applied as it loads (`n64interp_rom_loaded`);
- clears the runtime's overlay tables and the frontend's ROM search at each start, since the two
  games share them in one process;
- writes both games' interpreter tables (`scripts/generate-n64interp.py --prefix=cruisn_usa_` and
  `--prefix=cruisn_world_`). navjack's N64Recomp also has the runtime replace `osPiWriteIo` and
  `cruisnPiRomRead`. Cruis'n USA's configuration hooks 92 traces into the game for navjack's
  debugging; they and `trace_mode` are left out, and its 7 working hooks (Controller Pak and
  interrupt delivery in busy-wait loops) stay.

`experiments/cruisn/CMakeLists.txt` builds one framework for both games: their generated names start
with each game's prefix, `CruisnTables.cpp` is compiled once per game, and the interpreter clears the
previous game's tables when the other game starts (`n64interp_begin_game`). It takes SDL from the
shared runtime and uses Racer's shader tools, since its RT64 is Racer's. The runtime's memory window
is 1 GB (`RECOMP_MEM_SIZE_MB`), so game code reaching hardware registers (0xA4000000) and the
cartridge window (0xB0000000) lands in scratch memory instead of faulting.

`CruisnGame.cpp` replaces navjack's host program, which needs RecompFrontend's RmlUi interface: it
registers the game and runs it with Racer's frontend, with navjack's settings (one controller, the
games' EEPROM saves, and on Cruis'n USA the accelerator, the N64's Z trigger, on the right trigger).
`CruisnRuntime.mm` checks the ROM and links it into `Library/Caches/Nativecade/Games/CruisnUSA` or
`CruisnWorld` as `cruisnusa.z64` or `cruisnworld.z64`, where the runtime also keeps its settings and
saves. navjack's Controller Pak emulation is built in but, as in navjack's build, off unless
`CRUISN_CONTROLLER_PAK` is set.

## Cruis'n World's boot values

Cruis'n World's copy protection compares state that the cartridge's boot process leaves behind:
eight words in low RDRAM and the RSP's memories, and the cartridge's boot code itself. The runtime
starts the game without that boot process, so navjack's `cruisn_world_boot.cpp` writes the eight
words before the check. Five of them are instructions of the cartridge's boot code, so they are data
from the ROM.

By default the framework leaves them out: `CruisnGame.cpp` copies the boot code from the player's
ROM but writes none of the eight words, and World is expected to stop at its check. Configuring
`experiments/cruisn` with `-DRECOMPTV_CRUISN_WORLD_BOOT_WORDS=ON` compiles navjack's file instead.

## Checking it in the simulator

RT64 can't draw in the simulator (see [Shadows of the Empire](SOTE.md#checking-it-in-the-simulator)).
With `CRUISN_HEADLESS_SMOKE=1`, simulator builds give the games a renderer that only counts display
lists (`experiments/racer/HeadlessRenderer.cpp`, shared with Racer):

```sh
SIMCTL_CHILD_NATIVECADE_RESTART_PROBE=cruisnusa,cruisnworld SIMCTL_CHILD_CRUISN_HEADLESS_SMOKE=1 \
    xcrun simctl launch --console <simulator> com.smidley.nativecade
```

## Verification on 2026-10-30

- `NativecadeCruisn.framework` built for the tvOS simulator (12.9 MB) and Apple TV (12.7 MB), arm64,
  tvOS 17.0 minimum, from navjack's pins and Racer's runtime, renderer and frontend. It links the
  shared runtime and system frameworks only (no AppKit or OpenGL); from the shared runtime it uses 71
  SDL functions and `NativecadeSetPreparedGameRunner`.
- It exports only `NativecadePrepareCruisnUSA` and `NativecadePrepareCruisnWorld` among Nativecade's
  symbols, like Racer's framework, and its ImGui Objective-C classes have names no other framework
  uses. (Racer's and Cruis'n's both defined `MetalTexture`; each now renames it.)
- The app builds for the simulator with it, carries both ROM manifests, and starts; the app package's
  tests pass, including the two new identities.
- SotE's and Racer's interpreter tables are unchanged apart from the registration call
  (`n64interp_begin_game`), and Racer's restart check still passes with one start.
- The build reads no ROM, and World's boot values are left out by default.
- Not yet checked: everything with a ROM (neither is in the RomM library), a second start in one
  session (Racer's crashes, see [Racer](RACER.md)), and anything on a physical Apple TV.

## Licensing

navjack's setups are GPL-3.0, as is N64ModernRuntime; Racer's frontend, RT64 and N64Recomp are MIT.
The app's third-party notices include them.
