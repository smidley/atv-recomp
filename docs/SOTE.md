# Star Wars: Shadows of the Empire / SotE-Recomp

Nativecade can include [Shadows of the Empire: Recompiled](https://github.com/GTTeancum/SotE-Recomp),
a static recompilation of the Nintendo 64 game, at the commit pinned in
`upstream/sote-baseline.json`. Unlike the other five games, which compile
published source code, a recompilation turns the game's own code into C. That
code is generated from the player's ROM on the Mac that builds Nativecade, so:

- it is never committed, uploaded, or built in CI;
- only simulator builds on the Mac that generated it contain it;
- Apple TV builds, which TestFlight archives use, never contain it:
  `experiments/sote/CMakeLists.txt` stops with an error if asked to.

Everywhere else, the `NativecadeSote` framework is a stand-in that reports the
game isn't included in this build.

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

1. Import the ROM in Nativecade or the RecompTV app, or have the file at hand.
2. Generate the game's code on the Mac:

   ```sh
   bash scripts/generate-sote-code.sh PATH_TO_ROM
   ```

   The script prepares the pinned source, builds N64Recomp and RSPRecomp for the
   Mac, installs the extractor's two Python packages (`unicorn`, `xxhash`) into
   `build/sote/python`, checks the ROM's SHA-256, decompresses the game's boot
   image, and writes the recompiled code to `build/sote/source/generated`. Git
   ignores that folder.
3. Build as usual ([Nativecade and TestFlight](NATIVECADE_TESTFLIGHT.md)).
   `build-nativecade-runtime.sh` notices the generated code and builds the real
   framework for the simulator only. RT64 compiles its shaders while it builds, which needs
   Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`).

## How it is adapted

`scripts/upstream.py fetch` clones SotE-Recomp at its pin into
`build/upstream/SotE-Recomp`, and `scripts/prepare-sote.py` writes an adapted
copy to `build/sote/source` without changing the checkout. The pin is upstream's
`main` after the 0.9.7 tag: those commits add the SDL host code of the Linux
0.9.7 package, while the tag itself builds only for Windows. The script:

- checks out only the submodules the tvOS build and the Mac's generators use;
- applies SotE-Recomp's own patches to N64ModernRuntime, RT64 and plume, as its
  `build.ps1` does;
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
- leaves out the PC cutscene decoder (LGPL-2.1 `sandec`), since Apple TV has no
  PC game files; the N64 cutscenes play;
- keeps the process's output instead of sending it to SotE's log files.

`experiments/sote/CMakeLists.txt` builds `NativecadeSote.framework` inside the
shared runtime build, with the game code, N64ModernRuntime and RT64 hidden and
SDL taken from the shared runtime. `SoteRuntime.mm` checks the ROM and links it
into `Library/Caches/Nativecade/Games/ShadowsOfTheEmpire` as `sote.us.v1.2.z64`,
where SotE also keeps its settings and saves; nothing is extracted, because the
recompiled code reads the cartridge while it runs.

## Licensing

SotE-Recomp's own code is MIT. N64ModernRuntime, which it links, is GPL-3.0, so
an app build that includes Shadows of the Empire is a combined work under
GPL-3.0 when it is distributed. RT64, plume and N64Recomp are MIT. Builds that
leave this Mac never include them, so the app's third-party notices don't list them.

## Verification on 2026-10-30

- The game's code was generated on the build Mac from the user's ROM, imported
  from RomM and verified: 1,170 recompiled functions and the audio microcode.
- `NativecadeSote.framework` compiled and linked for the tvOS simulator (12 MB,
  depending only on the shared runtime and system frameworks). The Apple TV
  slice built for this check is the stand-in, and the app also links for Apple TV.
- In the tvOS 27.0 Apple TV 4K simulator, Play started the game: SotE found and
  validated the ROM, decompressed the game's boot image (527,872 bytes), started
  its two game threads, opened audio at 22,050 Hz, found the controller, and
  RT64 processed the game's first three frames.
- RT64 can't draw in the simulator. Its raster shaders use an array of 8,192
  textures and 18 samplers, which need tier-2 argument buffers. The simulator
  rejects those pipelines (it allows 16 samplers and 31 textures), the GPU work
  that depends on them never finishes, and the screen stays black with the game
  waiting. Starting Shadows of the Empire in the simulator therefore leaves the
  app stuck until it is closed. The Apple TV 4K (3rd generation, A15) supports
  tier-2 argument buffers, as do the Macs RT64 runs on, but Apple TV builds
  can't contain code generated from a ROM, so in this form the game can't be
  tested there. Running it on the Apple TV needs its code read from the
  player's ROM while it runs, as the other games' assets are.
- Not yet checked: any picture, controls, sound quality, saves, Quit and a
  second start in the same session ([Switching games](GAME_SWITCHING.md)), and
  anything on a physical Apple TV.

