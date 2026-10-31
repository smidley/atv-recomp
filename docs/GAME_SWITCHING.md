# Switching games

Quit in a game's menu returns to the Nativecade library, and any game can then be
started again in the same app session. This was hard because every port assumes
it owns the process: on a PC, quitting a game ends the program, so nothing in
Shipwright, SpaghettiKart, Starship, Ghostship, Lighthouse or libultraship cleans up for a second start. This page
records what carried over between starts, how each case is handled, and how to
check a new game. Expect a new game to hit some of the same cases.

## How a game starts and ends

1. The app's `main` calls `NativecadeRunApplication`, which runs SDL's UIKit app
   delegate. The SwiftUI library is a separate window on top.
2. Play calls `NativecadeLaunchPreparedGame`. SDL's `postFinishLaunch` then calls
   `RunApplication` in `simulator-game/NativecadeRuntime.mm`, which hides the
   library and runs the game's `main` (`RecompTVShipwrightMain` for Ocarina,
   `NativecadeRunMarioKart` for Mario Kart, `NativecadeRunStarFox` for Star Fox,
   `NativecadeRunSuperMario` for Super Mario 64, `NativecadeRunBanjoKazooie` for
   Banjo-Kazooie, `NativecadeRunShadowsOfTheEmpire` for Shadows of the Empire,
   `NativecadeRunEpisodeOneRacer` for Racer, `NativecadeRunSuperSmashBros` for Super Smash Bros.,
   `NativecadeRunCruisnUSA` and `NativecadeRunCruisnWorld` for Cruis'n).
3. The red power button (Quit) in the game's menu closes libultraship's window, or
   holding View (or the Siri Remote's Play/Pause) for 1.5 seconds sends SDL's quit
   event, which every game handles (`ArmQuitButtons` in `NativecadeRuntime.mm`;
   [Controls and menus](CONTROLS_AND_MENUS.md)).
   The game's main loop ends, and its `main` returns.
4. `RunApplication` cleans up (below) and shows the library again. SDL keeps
   UIKit running, so nothing else needs restarting.

## What carries over, and how it is handled

| What carried over | What went wrong | Handling | Where |
|---|---|---|---|
| libultraship's context, a process-wide singleton the games never destroy | The next start got the old context back. The new window was never initialized, and the game crashed in `Interpreter::Destroy`. | `Ship::Context::DestroyInstance()` after each game | `NativecadeRuntime.mm` |
| SDL shutdown order | The window backend called `SDL_Quit()` while ImGui and the control deck still had game controllers open. They then closed freed controllers, corrupting the heap; the crash came later, in SwiftUI. | `metal/restart.patch` removes that call; the runtime calls `SDL_Quit()` after the context is destroyed. | `metal/restart.patch`, `NativecadeRuntime.mm` |
| spdlog logger names | libultraship registers its logger under the game's name, so a second start could not register it. `Context::Init` chains its steps with `&&` and stopped there: no window, GUI or audio. Mario Kart crashed loading its fonts. | Drop the logger and set a plain default logger after each game. | `NativecadeRuntime.mm` |
| The game data folder (`NATIVECADE_GAME_DIRECTORY`) | libultraship reads it as the game's data folder on Apple TV. It stayed set after Mario Kart, so Ocarina's settings and saves went into Mario Kart's folder. | Unset it after each game. | `NativecadeRuntime.mm` |
| The original game code's C globals | They kept their values. For example, `gPlayState` still pointed at freed memory and a startup hook walked it. | `GameStateSection.h` is force-included in each game's C files, which puts their globals in `__DATA,__game_data` and `__DATA,__game_bss`. Before each start, `ResetGameGlobals` restores the first from a copy taken before the game first ran, and maps fresh zero pages over the second, which costs no memory until used. | `GameStateSection.h`, each game's `CMakeLists.txt`, `NativecadeRuntime.mm` |
| Shipwright's game hooks | Hooks live in static tables, one per hook type. GUI windows register hooks that capture `this` and never remove them, so old hooks wrote into freed windows on the next scene load. | `RecompTVClearGameHooks()` empties every table after each game. `restart.patch` makes hook IDs unique across starts, so an old ID held by a `COND_HOOK` cannot remove a new hook. | `AppleTVGameplay.cpp`, `simulator-game/restart.patch` |
| Pointers cached in function-local statics | `GraveHoleJumps.cpp` cached a collision header from the first run. `CosmeticsEditor.cpp` caches the player twice. | `restart.patch` removes those `static` keywords. | `simulator-game/restart.patch` |
| Mario Kart's C++ globals that its startup does not rebuild | The world (cups, track, actors), the track editor's objects, item registry IDs, and the set that records which display lists mirror mode already flipped. | `NativecadeRunMarioKart` rebuilds them after Mario Kart ends, while its context still exists. `prepare-spaghettikart.py` makes `gModifiedGfxSet` visible to it. | `spaghettikart/KartRestart.cpp`, `scripts/prepare-spaghettikart.py` |
| Star Fox's event listeners | Starship v2.0.0 has its own process-wide event system, so the listeners registered at each start would pile up. | `prepare-starship.py` switches Star Fox to libultraship's event system, which the context owns, so `DestroyInstance` clears it. The event IDs are C globals and are restored with the others. | `scripts/prepare-starship.py` |
| Star Fox's C++ timer list and audio pacing counters | A timer still pending at Quit, such as the logo screen's, would fire during the next start and change a game variable at the wrong moment. | `NativecadeRunStarFox` calls `NativecadeStarshipReset`, which `prepare-starship.py` adds to `Engine.cpp`. | `starship/StarshipRestart.cpp`, `scripts/prepare-starship.py` |
| Banjo-Kazooie's emulated N64 threads, timers and graphics tasks | Lighthouse runs them on real threads, and their shutdown flags only go one way. On the next start, every game thread would leave at once and timers would never fire. A graphics task still pending at Quit pointed into game memory that the next start had reset, so the renderer read a null display list and crashed. | `NativecadeRunBanjoKazooie` calls reset functions that `prepare-lighthouse.py` adds to Lighthouse's `Game.cpp`, `OS_Threads.cpp`, `OS_RCP.cpp` and `OS_Timer.cpp`. | `lighthouse/LighthouseRestart.cpp`, `scripts/prepare-lighthouse.py` |
| Nativecade's own observers and hooks | The app-lifecycle observers and the save-backup hook were added again on every start. | Observers are installed once per app session. The hook is registered each start, since the tables are cleared. | `AppleTVGameplay.cpp` |

Sizes measured in the simulator build: Ocarina's game globals are 377 KB of
initialized data and 101 MB of zeroed data; Mario Kart's are 826 KB and 277 MB;
Star Fox's are 252 KB and 9.5 MB; Super Mario 64's are 283 KB and 3.7 MB; Banjo-Kazooie's
are 139 KB and 2.8 MB.

## Known issues

- Shadows of the Empire hasn't been through the restart check: in the simulator its
  renderer can't draw, so it never reaches Quit ([Shadows of the Empire](SOTE.md)).
  Its interpreter keeps its tables between starts; the game's code is read from RDRAM each time.
  N64ModernRuntime, its runtime, also expects a new process for each start.
- Racer's second start in one session crashes (SIGSEGV soon after the game starts again;
  [Racer](RACER.md)). Its runtime leaves the first run's game threads waiting, which is the
  likeliest cause but isn't confirmed. Cruis'n's runtime ends them at shutdown (navjack's patch);
  it hasn't been tried with a ROM.
- On 2026-10-30, the sequence `banjo,oot,kart,fox,mario,banjo` stalled in two of
  three runs: Banjo-Kazooie's second start waited in `osRecvMesg` for a controller
  message during `game_init`. The third run passed, as did one run with the
  stand-in Shadows of the Empire framework, and `banjo,banjo` plus Banjo-Kazooie
  around each other game on its own. The cause isn't known yet.

## Adding a game

- Compile the game's original C sources with `GameStateSection.h`, as each game's
  `CMakeLists.txt` does.
- Wrap its `main` like `NativecadeRunMarioKart` to rebuild C++ state that its own
  startup does not. Look for:
  - global C++ objects, such as `World sWorldInstance;` or `Registry<...> gItems;`;
  - timer or task lists that hold pointers into game globals, such as Starship's
    `gTimerTasks`;
  - function-local statics that cache pointers, such as
    `static T* x = GetResource(...);`;
  - static tables of callbacks or hooks that capture objects;
  - static "already done" sets tied to loaded resources;
  - singletons created with `new` at startup and never freed.
- If the port carries its own copy of something libultraship now provides, such
  as Starship's event system, use libultraship's: it belongs to the context.
- Remember that one failed step in libultraship's `Context::Init` skips all
  later steps.
- Set the game's data folder for its own run only.
- Run the restart check with the new game in every position: before and after
  each other game, and twice in a row. Then run it with Address Sanitizer.

## Tools

### Restart check

Debug simulator builds start each game listed in `NATIVECADE_RESTART_PROBE`
(`oot`, `kart`, `fox`, `mario`, `banjo`, `sote`, `racer`, `smash`, `cruisnusa` or `cruisnworld`), one each time the library appears, and end each game
after 30 seconds as Quit does. The timer applies to every game started in that
app session, including one started with Play:

```sh
SIMCTL_CHILD_NATIVECADE_RESTART_PROBE=oot,kart,oot,kart,kart,oot xcrun simctl launch <simulator> com.smidley.nativecade
xcrun simctl spawn <simulator> log show --last 5m --predicate 'eventMessage CONTAINS "RestartProbe"'
```

The log ends with `[RestartProbe] PASS` when every game started and returned to
the library. To capture standard error, `simctl launch --stderr=<file>` works when
the file is inside the app's data container.

With `NATIVECADE_MENU_PROBE=1`, a virtual controller presses View 12 seconds into each
game and then moves through its menu with the D-pad (down three times, right, down),
so screenshots taken meanwhile show the menu opening and the focus moving.

Mario Kart's controller test (`NATIVECADE_KART_INPUT_PROBE=1`) only runs when SDL
sees no other joystick. After another game has run, SDL already knows the Siri
Remote, so the test skips itself; it cannot check input after a restart.

### Address Sanitizer

Address Sanitizer is a compiler mode that stops at the first invalid memory
access and shows where it happened. It found the SDL shutdown order and the
stale hooks, which otherwise crashed far from their cause. Build the simulator
runtime in its own folder:

```sh
asan="-fsanitize=address -fno-omit-frame-pointer"; opt="-O1 -gline-tables-only -DNDEBUG"
cmake -S experiments/shipwright/simulator-game -B build/nativecade-runtime/appletvsimulator-asan -G Ninja \
  <the options from scripts/build-nativecade-runtime.sh> \
  -DCMAKE_C_FLAGS="$asan" -DCMAKE_CXX_FLAGS="$asan" -DCMAKE_OBJC_FLAGS="$asan" -DCMAKE_OBJCXX_FLAGS="$asan" \
  -DCMAKE_C_FLAGS_RELWITHDEBINFO="$opt" -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="$opt" \
  -DCMAKE_OBJC_FLAGS_RELWITHDEBINFO="$opt" -DCMAKE_OBJCXX_FLAGS_RELWITHDEBINFO="$opt" \
  -DCMAKE_SHARED_LINKER_FLAGS=-fsanitize=address -DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address
ninja -C build/nativecade-runtime/appletvsimulator-asan NativecadeSpaghetti
```

Copy its `NativecadeRuntime` and `NativecadeSpaghetti` binaries over the
`tvos-arm64-simulator` slices in `build/nativecade-runtime/*.xcframework`. Build
the app with `xcodebuild ... -enableAddressSanitizer YES` into a separate
`-derivedDataPath`. Launch it with the restart check and:

```sh
SIMCTL_CHILD_ASAN_OPTIONS="halt_on_error=1:detect_leaks=0:detect_container_overflow=0:replace_intrin=0:log_path=<app container>/tmp/asan"
```

The report is written to `<app container>/tmp/asan.<pid>`. Run
`python3 scripts/package-nativecade-runtime.py` afterwards to restore the normal
simulator slices. The build takes about 10 minutes and 2.5 GB.

Two reports are not restart bugs:
- `container-overflow` inside the standard library while prism parses shaders is
  a known false alarm. `detect_container_overflow=0` turns it off.
- Mario Kart's `gfx_load_tlut_handler_rdp` reads a 256-byte palette past the end
  of a 464-byte texture in normal play. It reads only, so at worst colors are
  wrong, but it should be reported upstream. Until it is fixed,
  `replace_intrin=0` skips `memcpy` and `memset` range checks so the run can
  continue. Ordinary reads and writes are still checked.

### Other evidence

- Crash reports: `~/Library/Logs/DiagnosticReports/Nativecade-*.ips`. macOS
  stops writing them after many crashes in one day; the sanitizer still reports.
- Each game's libultraship log is in `logs` inside its data folder,
  `Library/Caches/Nativecade/Games/OcarinaOfTime`, `.../MarioKart64`,
  `.../StarFox64`, `.../SuperMario64` or `.../BanjoKazooie`.
- Builds can be killed (exit code 137) when the Mac runs low on memory and swap.
  Shutting down the simulator during builds and running `ninja` directly, rather
  than `cmake --build`, helped.

## Not yet verified

- Quitting with a physical controller, controller input after a restart, and
  restarts on a physical Apple TV.
- Star Fox under Address Sanitizer. The restart check passed on 2026-10-29 with
  Star Fox three times among the other games (`fox,oot,fox,kart,fox`), and with
  Super Mario 64 three times (`mario,oot,mario,kart,fox,mario`). Super Mario 64 needed
  no reset of its own so far; its startup rebuilds its engine object each time.
  On 2026-10-30 it passed with Banjo-Kazooie four times, twice in a row
  (`banjo,banjo,oot,banjo,kart,fox,mario,banjo`); Banjo-Kazooie hasn't run under
  Address Sanitizer either.
- Memory use after many restarts. Shipwright's startup creates new singletons
  each time without freeing the old ones; the amount has not been measured.
- Ocarina asks before quitting; Mario Kart quits at once. Either way, progress
  since the last save or autosave is lost.
