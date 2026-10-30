# N64 interpreter

Recompiled N64 games, such as [Shadows of the Empire](SOTE.md), are built from C
that [N64Recomp](https://github.com/N64Recomp/N64Recomp) generates from the game's
ROM. That code can't go into a build that leaves this Mac. `experiments/n64interp`
runs the same game code from the ROM in memory while the game plays instead, so a
build holds only the project's own code and tables written from its configuration.

## How it works

The game's host program, N64ModernRuntime and the project's hooks stay as they are.
Only the generated code is replaced:

- `N64Interpreter.cpp` runs MIPS III code from RDRAM. Each instruction does what
  N64Recomp's generated C does for it, with N64Recomp's own `recomp.h` macros, so
  results match the recompiled code on the same CPU: the floating-point modes, the
  odd single-precision registers, division by zero as ARM64 computes it, and calls
  that return through `$ra` like C calls. A jump or call to a function the runtime
  replaces (such as `osRecvMesg`) runs the replacement, and a hook runs before the
  instruction it is attached to.
- `scripts/generate-n64interp.py` writes the files N64Recomp would (`funcs.h`,
  `recomp_overlays.inl`, `lookup.cpp`) and `n64interp_game.c`: for every game
  function, a C function that interprets it, so the runtime and hooks can call it
  by name; the replacements; and the configuration's hooks as functions. It reads
  only the project's N64Recomp configuration and symbol file, and N64Recomp's lists
  of libultra functions. It handles `stubs`, `ignored`, `renamed` and `hook`
  patches and fixed sections; overlays (relocatable sections) aren't supported yet.
- `N64RspInterpreter.cpp` runs RSP microcode from RDRAM, as rspboot loads it into
  IMEM, following RSPRecomp's generated code with N64ModernRuntime's vector unit,
  DMEM and DMA. A game can replace one instruction with a patch, as SotE does for
  its audio command dispatcher.

## Checking it

- `DecompressorSpike.cpp` interprets SotE's boot decompressor from a ROM and
  compares the result with the image SotE-Recomp's extractor wrote.
- `RspSpike.cpp` runs audio tasks saved in the simulator (`N64INTERP_RSP_CAPTURE`)
  through the RSP interpreter and through RSPRecomp's code, and compares memory afterwards.
- In the simulator, SotE's headless smoke test plays without the renderer
  ([Shadows of the Empire](SOTE.md#checking-it-in-the-simulator)).

## Speed

On the build Mac the CPU interpreter runs about 275 million instructions a second,
a few times what an N64 game needs, and an SotE audio task takes about 280 µs.
The Apple TV 4K's A15 should be somewhat slower; that is checked with TestFlight.
