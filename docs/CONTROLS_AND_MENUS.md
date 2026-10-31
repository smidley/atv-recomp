# Controls and menus

Nativecade's games are played with a game controller paired with the Apple TV
(Xbox, PlayStation or another MFi controller). The Siri Remote can quit a game,
but the games and their menus need a controller.

## Quit to the library (every game)

Hold **View** (on a PlayStation controller, **Create**) for 1.5 seconds, or the
Siri Remote's **Play/Pause**. The game ends as when you switch off a console:
progress since the last save or autosave is lost. A shorter press of View does
what the game uses it for, which in most games is opening its menu.

## Open and use a game's settings menu

| Game | Open the menu | Move | Choose / back | Quit from the menu |
|---|---|---|---|---|
| Ocarina of Time, Mario Kart 64, Super Mario 64, Banjo-Kazooie, Super Smash Bros. | View | D-pad | A / B | The red power button, top right |
| Star Fox 64 | View shows the menu bar, then X moves into it | D-pad | A / B | Starship → Quit |
| Star Wars Episode I: Racer | View | D-pad | A / B | Quit game |
| Star Wars: Shadows of the Empire | Start, then the game's own Options screen | D-pad | A / B | None (hold View) |

On a PlayStation controller, A is Cross and B is Circle. Press View again to
close the menu; while it's open, the game ignores the controller. The left stick
scrolls a long page; the D-pad moves between items, across the menu's tabs,
sidebar and settings.

- **Menu Controller Navigation** (in the settings) stays on: Nativecade turns it
  back on at every start, because the menus can't be used with a controller
  without it.
- The menus' search field opens a text field, which hasn't been tried on an
  Apple TV yet.
- The Siri Remote's Menu/Back button acts as B and its touch surface as a stick;
  it can't open the settings menus.

## How it works

- libultraship keeps controller navigation on under tvOS
  (`experiments/shipwright/metal/menus.patch`, and the same change to Super
  Smash Bros.' own copy in `scripts/prepare-battleship.py`), so View opens the
  menu in every libultraship game.
- The ports' menus are nested regions; `scripts/tvos_menus.py` marks them
  `ImGuiChildFlags_NavFlattened`, so the D-pad crosses from one to the next
  without pressing A first.
- `ArmQuitButtons` in `experiments/shipwright/simulator-game/NativecadeRuntime.mm`
  watches View and Play/Pause through Apple's GameController framework while a
  game runs, and sends SDL's quit event, which every game handles.
- In the simulator, `NATIVECADE_MENU_PROBE=1` presses View and the D-pad with a
  virtual controller ([Switching games](GAME_SWITCHING.md#restart-check)).

## Verification

- 2026-10-30, tvOS 27.0 simulator: View opened Mario Kart 64's and
  Banjo-Kazooie's menus and Star Fox 64's menu bar, and three D-pad presses moved
  from Mario Kart's tabs into its sidebar. The simulator can't press the
  GameController buttons, so hold-to-quit is first tried on an Apple TV with
  TestFlight build 9.
- Before build 9, only Ocarina's menu opened, its D-pad stopped at the menu's
  region borders, and no game could be quit without that menu.
