# Star Wars: Shadows of the Empire / SotE-Recomp

Nativecade includes [Shadows of the Empire: Recompiled](https://github.com/GTTeancum/SotE-Recomp),
a static recompilation of the Nintendo 64 game, at the commit pinned in
`upstream/sote-baseline.json`. A recompilation normally turns the game's own code
into C, generated from a ROM. A build that leaves this Mac, including every
TestFlight build, must not contain a ROM or anything generated from one. So
Nativecade runs the game's code from the player's ROM while it plays, with the
[N64 interpreter](N64_INTERPRETER.md), as the other games read their assets from it.

The build contains SotE-Recomp's own host code and hooks, N64ModernRuntime, RT64,
and tables written from SotE-Recomp's configuration: the names, addresses and
sizes of the game's functions, which libultra functions the runtime replaces, and
where SotE's hooks go. None of it comes from the ROM.

## Supported game data

SotE-Recomp accepts one release, the USA cartridge revision it calls 1.2:

| Release | Normalized SHA-1 | SHA-256 (SotE-Recomp) |
|---|---|---|
| Star Wars - Shadows of the Empire (USA) (Rev 2) | `9ab85626c27372ee614b7c5301c2c4eb187fd9f6` | `e7085e013123537f34e0edec8801318016da4dbac424172d6dc5f3b67d98642c` |

The SHA-1 comes from the No-Intro entry with the CRC32 SotE-Recomp names
(`E8727549`). SotE-Recomp also accepts a pack copy that differs by one byte
(SHA-256 `2802bf41…`); its SHA-1 isn't published, so Nativecade doesn't accept it
yet.

## Building

Build as usual ([Nativecade and TestFlight](NATIVECADE_TESTFLIGHT.md)); no ROM is
needed. `build-nativecade-runtime.sh` prepares SotE and builds its framework for
the simulator and the Apple TV. RT64 compiles its shaders while it builds, which
needs Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`).

To compare the interpreter with the recompiled code, generate that code from a
ROM on the Mac and build the simulator runtime with `-DRECOMPTV_SOTE_RECOMPILED=ON`:

```sh
bash scripts/generate-sote-code.sh PATH_TO_ROM
```

The script builds N64Recomp and RSPRecomp for the Mac, installs the extractor's
two Python packages (`unicorn`, `xxhash`) into `build/sote/python`, checks the
ROM's SHA-256, decompresses the game's boot image, and writes the code to
`build/sote/source/generated`, which Git ignores. `experiments/sote/CMakeLists.txt`
stops with an error if an Apple TV build is asked to compile it, and
`build-nativecade-runtime.sh` stops if its Apple TV build files mention it.

## How it is adapted

`scripts/upstream.py fetch` clones SotE-Recomp at its pin into
`build/upstream/SotE-Recomp`, and `scripts/prepare-sote.py` writes an adapted
copy to `build/sote/source` without changing the checkout. The pin is upstream's
`main` after the 0.9.7 tag: those commits add the SDL host code of the Linux
0.9.7 package, while the tag itself builds only for Windows. The script:

- checks out only the submodules the tvOS build and the Mac's generators use;
- applies SotE-Recomp's own patches to N64ModernRuntime, RT64 and plume, as its
  `build.ps1` does;
- writes the interpreter's tables to `build/sote/source/interpreter`
  (`scripts/generate-n64interp.py`, from `sote.toml` and its symbol file);
- builds RT64's shader tools for the Mac (`experiments/sote/host-tools`) and
  compiles RT64's Metal shaders for tvOS instead of macOS, in the iOS dialect of
  the Metal shading language;
- replaces plume's AppKit window code with `experiments/sote/plume_apple_tvos.mm`,
  which reads the size of the SDL Metal view's layer without waiting for the main
  thread (N64ModernRuntime's main thread waits while RT64 creates its swap chain);
- leaves out RT64's file dialog and texture tools;
- treats tvOS like iOS in plume's Metal device setup, uses the Apple TV's one
  built-in GPU instead of the macOS device list, and skips GPU timestamps where
  the device has none (the simulator);
- draws into an SDL Metal view with Metal instead of Vulkan;
- leaves out N64ModernRuntime's live recompiler, which compiles mods to native
  code while the game runs, something tvOS doesn't allow; code mods fail to load;
- reserves only the game's 512 MB of memory if the Apple TV can't give the runtime
  the 4 GB of address space it asks for (the rest only catches stray addresses);
- leaves out the PC cutscene decoder (LGPL-2.1 `sandec`), since Apple TV has no
  PC game files; the N64 cutscenes play;
- keeps the process's output instead of sending it to SotE's log files.

`experiments/sote/CMakeLists.txt` builds `NativecadeSote.framework` inside the
shared runtime build, with the interpreter, N64ModernRuntime and RT64 hidden and
SDL taken from the shared runtime. The audio microcode runs through the RSP
interpreter (`SoteAudioMicrocode.cpp`), which also applies SotE-Recomp's fix to
its command dispatcher (`tools/patch_rsp_audio.py`). `SoteRuntime.mm` checks the
ROM and links it into `Library/Caches/Nativecade/Games/ShadowsOfTheEmpire` as
`sote.us.v1.2.z64`, where SotE also keeps its settings and saves; nothing is
extracted, because the game's code and data are read from the cartridge while
it runs.

## Checking it in the simulator

RT64 can't draw in the simulator: its raster shaders use an array of 8,192
textures and 18 samplers, which need tier-2 argument buffers. The simulator
rejects those pipelines (it allows 16 samplers and 31 textures), the GPU work
that depends on them never finishes, and the screen stays black with the game
waiting, so the app has to be closed. The Apple TV 4K (3rd generation, A15)
supports tier-2 argument buffers.

Upstream's smoke test plays without RT64, and simulator builds start it when
`SOTE_HEADLESS_SMOKE` is set. It runs for `SOTE_SMOKE_VIS` frames (600 by
default), and `SOTE_INPUT_SCRIPT` presses buttons at given frames:

```sh
SIMCTL_CHILD_NATIVECADE_RESTART_PROBE=sote SIMCTL_CHILD_SOTE_HEADLESS_SMOKE=1 \
SIMCTL_CHILD_SOTE_SMOKE_VIS=6000 SIMCTL_CHILD_SOTE_INPUT_SCRIPT=120:5:start,300:5:start,660:5:start,900:5:a \
    xcrun simctl launch --console <simulator> com.smidley.nativecade
```

With `N64INTERP_RSP_CAPTURE=DIRECTORY`, simulator builds also save the state 16 audio
tasks start from, 120 tasks apart. `experiments/n64interp/RspSpike.cpp` runs
them through the RSP interpreter and through the generated microcode and
compares DMEM and RDRAM; its header shows how to build it. The captures and the
generated code stay on the Mac.

## Licensing

SotE-Recomp's own code is MIT. N64ModernRuntime, which it links, is GPL-3.0, so
an app build that includes Shadows of the Empire is a combined work under
GPL-3.0 when it is distributed. RT64, plume and N64Recomp are MIT. The app's
third-party notices list them and include their license files.

## Verification on 2026-10-30

- The interpreter decompressed the game's boot image from the ROM exactly as
  SotE-Recomp's extractor does: 0xEC880 bytes, identical, at about 275 million
  instructions a second on the build Mac.
- In the tvOS 27.0 Apple TV 4K simulator, Play started the interpreted game as
  far as the recompiled build gets there: SotE validated the ROM, decompressed
  the boot image (527,872 bytes), started its two game threads, opened audio, and
  RT64 processed the first frames before stalling as described above.
- Headless, with the inputs above, the interpreted game ran its 6,000 frames at
  full speed (about 60 game frames a second) with no errors, and reported the
  Battle of Hoth level state throughout.
- Audio: seven tasks saved from that run, six of them writing about 4,800 bytes
  of sound, gave byte-identical DMEM and RDRAM through the RSP interpreter and the
  generated microcode. The interpreter takes about 280 µs a task on the Mac, against
  about 110 µs for the generated code.
- Not yet checked: anything on a physical Apple TV (picture, speed, controls,
  sound, saves), and Quit and a second start in the same session
  ([Switching games](GAME_SWITCHING.md)).
