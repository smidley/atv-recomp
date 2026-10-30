# Star Wars Episode I: Racer

Nativecade includes [Racer](https://github.com/sp00nznet/racer), a static recompilation of the
Nintendo 64 game, at the release pinned in `upstream/racer-baseline.json`. Like
[Shadows of the Empire](SOTE.md), its code would normally be generated from the ROM, so Nativecade
runs it from the player's ROM with the [N64 interpreter](N64_INTERPRETER.md) instead. The build
contains Racer's own host program (`src/`, `frontend/`), N64ModernRuntime, RT64, and tables written
from Racer's configuration, symbol file and section table; none of it comes from the ROM.

## Supported game data

Racer accepts the USA release, whose header CRC it checks (`72F70398`):

| Release | SHA-1 |
|---|---|
| Star Wars Episode I - Racer (USA) | `3542d5597c8a56ea8f5c63bceae97a24c4c08d58` |

## Versions

Racer's setup clones its runtime, renderer and recompiler forks
([sp00nznet/N64ModernRuntime](https://github.com/sp00nznet/N64ModernRuntime),
[sp00nznet/rt64](https://github.com/sp00nznet/rt64),
[sp00nznet/N64Recomp](https://github.com/sp00nznet/N64Recomp)) at the tip of their `main` branches.
The version file pins the commits Nativecade builds as sources with a `branch`; updating Racer leaves
them alone, so check them by hand ([Updating game runtimes](UPDATING_UPSTREAM.md)).

## How it is adapted

`scripts/prepare-racer.py` copies Racer and the three forks to `build/racer/source` without changing
the checkouts, then:

- applies the tvOS changes Racer shares with SotE's runtime and renderer (`scripts/rt64_tvos.py`):
  RT64's Metal shaders for tvOS, plume's tvOS window and device code, no live recompiler, and the
  smaller memory reservation if tvOS lacks address space;
- draws into a full-screen SDL Metal view, returns to the library when the game ends instead of
  ending the process, and keeps RT64's data in the game folder;
- writes the interpreter's tables (`scripts/generate-n64interp.py`). Besides the symbol file, they
  take from Racer's own sources the functions N64Recomp split off at calls into other functions
  (`src/section_table.cpp`) and the two functions `tools/post_recomp_patches.py` sends to host code.

Racer's build chains a function that ends without returning into the function after it
(`tools/fix_fallthroughs.py`); the interpreter does that by running on, and runs the runtime's
replacement when it reaches one that way.

`experiments/racer/CMakeLists.txt` builds `NativecadeRacer.framework` as a project of its own,
because its runtime and renderer are other versions of SotE's with the same target names. It takes
SDL from the shared runtime's framework. Its shader tools are built from Racer's RT64
(`experiments/sote/host-tools`). `RacerRuntime.mm` checks the ROM and links it into
`Library/Caches/Nativecade/Games/EpisodeOneRacer` as `swe1racer.z64`, the name Racer's runtime keeps
it under, where Racer also keeps its settings and saves. `RacerGame.cpp` starts Racer without its
launcher window.

## Checking it in the simulator

RT64 can't draw in the simulator (see [Shadows of the Empire](SOTE.md#checking-it-in-the-simulator)).
With `SWE1R_HEADLESS_SMOKE=1`, simulator builds give Racer a renderer that only counts display
lists:

```sh
SIMCTL_CHILD_NATIVECADE_RESTART_PROBE=racer SIMCTL_CHILD_SWE1R_HEADLESS_SMOKE=1 \
    xcrun simctl launch --console <simulator> com.smidley.nativecade
```

## Verification on 2026-10-30

- `NativecadeRacer.framework` built for the tvOS simulator (12.6 MB), depending only on the shared
  runtime and system frameworks.
- In the tvOS 27.0 Apple TV 4K simulator, the restart check (`NATIVECADE_RESTART_PROBE=racer`) with
  the headless renderer started Racer from the library: it found the ROM in the game folder,
  started the game, and ran its game code and audio microcode for 30 seconds (about 110 display
  lists and 20 audio tasks a second) with no interpreter errors. Its Quit then returned to the
  library (`PASS: 1 games started in one session`).
- Racer's audio dump (`SWE1R_AUDIODUMP`) from such a run held 30 seconds of sound, with a peak of
  9,943 and a loudness that changes as music does.
- Not yet checked: anything on a physical Apple TV (picture, speed, controls, saves) and a second
  start in the same session.

## Licensing

Racer is MIT. N64ModernRuntime is GPL-3.0, RT64 and N64Recomp are MIT; the app's third-party notices
include them.
