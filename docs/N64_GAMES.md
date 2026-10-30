# Nintendo 64 games

Where each Nintendo 64 game stands in Nativecade. Nintendo 64 is the only
platform being worked on so far. For every N64 project in the community,
including the recompilations, source ports and decompilations Nativecade could
build on, see the [recomp.fyi board](https://recomp.fyi/#board). On 2026-10-30
it listed 276 N64 projects: 154 recompilations, 88 decompilations and 34 source
ports.

Nativecade runs native ports: the game's code is compiled for Apple TV, and the
game's assets are prepared on the device from the player's own ROM. No ROM or
extracted game data is included in the app or this repository.

## Playable in Nativecade

All five run in the tvOS simulator and can be switched between in one session.
None has been tested on a physical Apple TV yet.

| Game | Runs through | Accepted ROMs | Checked in the simulator | Still to check | TestFlight |
| --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time | [Shipwright](https://github.com/HarbourMasters/Shipwright) 9.3.1 | [19 revisions](../upstream/shipwright-supported-roms.json) | Rendering in the app; gameplay and controls confirmed earlier by the maintainer | Apple TV | Builds 1 to 4 |
| Mario Kart 64 | [SpaghettiKart](https://github.com/HarbourMasters/SpaghettiKart) 1.0.0 | USA | Title, demo, menus and a race with a virtual controller | Full cups and time-trial saves, Apple TV | Builds 2 to 4 |
| Star Fox 64 | [Starship](https://github.com/HarbourMasters/Starship) v2.0.0 | USA 1.0 and 1.1 | Startup and opening | Controller play, Apple TV | Build 5 onward, not yet accepted |
| Super Mario 64 | [Ghostship](https://github.com/HarbourMasters/Ghostship) 3.0.0 | USA | Title screen | Controller play, Apple TV | Build 7, not yet accepted |
| Banjo-Kazooie | [Lighthouse](https://github.com/HarbourMasters/Lighthouse) 1.2.2 | USA 1.0 and 1.1, Europe, Japan | Opening scene | Controller play, Apple TV | Build 7, not yet accepted |

App Store Connect currently rejects builds made with Xcode 27.2, so builds 5 to 7
haven't reached TestFlight; see [Nativecade and TestFlight](NATIVECADE_TESTFLIGHT.md).
Each game has its own page: [Ocarina of Time](SHIPWRIGHT_PORT.md),
[Mario Kart 64](SPAGHETTIKART.md), [Star Fox 64](STARSHIP.md),
[Super Mario 64](GHOSTSHIP.md) and [Banjo-Kazooie](LIGHTHOUSE.md).

## Next candidates

| Game | Project | Kind | What it would take |
| --- | --- | --- | --- |
| Star Wars: Shadows of the Empire | [SotE-Recomp](https://github.com/GTTeancum/SotE-Recomp) 0.9.7 | Recompilation (N64Recomp and RT64) | Work started 2026-10-30; nothing runs yet. Its game code is generated from the player's ROM when Nativecade is built, so it can only be built on a Mac that has the ROM, not in CI. Its runtime library, [N64ModernRuntime](https://github.com/N64Recomp/N64ModernRuntime), is GPL-3.0, and its renderer, [RT64](https://github.com/rt64/rt64), hasn't run on Apple TV yet. |
| The Legend of Zelda: Majora's Mask | [2 Ship 2 Harkinian](https://github.com/2ship2harkinian/2ship2harkinian) 5.0.1 | Source port (libultraship) | Builds on the same graphics library as the other ports; its asset extractor (ZAPD) would need to run on Apple TV. |
| Paper Mario | [PaperBoat](https://github.com/HarbourMasters/PaperBoat) 1.0.3 | Source port (libultraship and Torch) | Uses the same asset extractor, but a branch of the graphics library that has diverged from the shared one. |

## How a game is added

Source ports built on [libultraship](https://github.com/Kenix3/libultraship) are
the quickest to add, because every Nativecade game shares one copy of it and one
copy of the Torch asset extractor. Each new port gets a preparation script that
adapts a copy of its source, a framework that runs it, and a check that it can
start again in the same session ([Switching games](GAME_SWITCHING.md)).

Recompilations made with [N64Recomp](https://github.com/N64Recomp/N64Recomp)
use a different runtime and the RT64 renderer. An earlier
[runtime audit](RUNTIME_AUDIT.md) and the [RT64 Metal experiment](RT64_METAL_EXPERIMENT.md)
built parts of that stack for the tvOS simulator, but no recompiled game has run
in Nativecade yet.

Supported ROM revisions, their hashes and how imports are verified are in
[Compatibility](../COMPATIBILITY.md).
