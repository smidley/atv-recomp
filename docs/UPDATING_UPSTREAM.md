# Updating game runtimes

Each game in Nativecade is built from its maintainers' upstream project plus our
tvOS changes. Upstream code is not copied into this repository: a version file
pins it, and the build downloads exactly those commits. Updating a game means
changing its version file, fixing any of our patches that no longer apply, and
testing.

## What is pinned

Each game has one version file, `upstream/<game>-baseline.json`:

- `release`: the upstream release Nativecade builds.
- `sources`: the game's own repository, plus libraries taken from that release's
  submodules (`gitlink`). Library versions always follow the game release.
- `prepare`: the scripts that apply our tvOS patches to generated copies.
- Game-specific data, such as Shipwright's supported-ROM list.

| Game | Upstream | Also supplies |
|------|----------|---------------|
| Ocarina of Time | [Shipwright](https://github.com/HarbourMasters/Shipwright) (`shipwright`) | |
| Mario Kart 64 | [SpaghettiKart](https://github.com/HarbourMasters/SpaghettiKart) (`spaghettikart`) | |
| Star Fox 64 | [Starship](https://github.com/HarbourMasters/Starship) (`starship`) | |
| Super Mario 64 | [Ghostship](https://github.com/HarbourMasters/Ghostship) (`ghostship`) | |
| Banjo-Kazooie | [Lighthouse](https://github.com/HarbourMasters/Lighthouse) (`lighthouse`) | libultraship and Torch, shared with the other games |
| Star Wars: Shadows of the Empire | [SotE-Recomp](https://github.com/GTTeancum/SotE-Recomp) (`sote`) | Its own N64ModernRuntime, RT64 and N64Recomp, from the pinned commit's submodules |
| Star Wars Episode I: Racer | [Racer](https://github.com/sp00nznet/racer) (`racer`) | Its own N64ModernRuntime, RT64 and N64Recomp forks, pinned separately |
| Super Smash Bros. | [BattleShip](https://github.com/JRickey/BattleShip) (`battleship`) | Its own libultraship and Torch forks and the ssb-decomp-re decompilation, from the release's submodules |

The libultraship games build against one libultraship and one Torch, so exactly one game's
release supplies them (`scripts/UpstreamTests.py` checks this). BattleShip is the exception: it
needs its own forks of both, which only it uses ([Super Smash Bros.](BATTLESHIP.md)). That is
Lighthouse, because it needs the newest of both: Torch's Banjo-Kazooie
extraction and the libultraship branch that draws N64 mipmaps
([JeodC/libultraship](https://github.com/JeodC/libultraship), which Lighthouse
ships). Updating Lighthouse therefore moves the libraries for every game. If
another game's release needs a newer library first, move both `gitlink`
sources to that game's version file and change the readers that name
`lighthouse-baseline.json` (`upstream/pins.cmake` and the prepare scripts).

SotE-Recomp is pinned to a commit on upstream's `main` after its 0.9.7 tag (see
`integration` in its version file), and `update sote` pins a tag, so check that a
new release still has the SDL host code before updating ([Shadows of the Empire](SOTE.md)).

Racer's setup clones its runtime, renderer and recompiler forks at the tip of their `main` branches
instead of submodules. Its version file pins them as sources with a `branch`, which `update racer`
leaves alone: move them by hand to the commits a new release was tested with ([Racer](RACER.md)).

Everything else reads these files: the build scripts, CMake through
`upstream/pins.cmake`, the app's prepared-asset folders and extraction version,
and CI. `upstream/libultraship-simulator.json` additionally pins the libraries
that libultraship downloads for the tvOS build.

Only what the tvOS build compiles is pinned and downloaded. Other platforms'
submodules, packaging and tools are never fetched, and CI builds only Apple TV
and Simulator. A release that changes only Windows, Linux or console code still
needs the version bump, but nothing else.

`python3 scripts/upstream.py fetch` checks out every pinned source under
`build/upstream/`; `scripts/build-nativecade-runtime.sh` runs it first. It never
overwrites a checkout with local changes.

## Hearing about a release

The weekly **Upstream game releases** workflow opens one issue per game whose
latest GitHub release differs from its pin. The issue links the release notes
and the full comparison, counts the changed commits and files, and says whether
the shared libraries changed. Pre-releases and development branches are
ignored. `python3 scripts/upstream.py releases` runs the same check locally.

## Updating

1. On a branch, run `python3 scripts/upstream.py update <game> <release>`, for
   example `python3 scripts/upstream.py update shipwright 9.4.0`. It pins the
   release (and, for Lighthouse, the libultraship and Torch commits that release
   ships with), refreshes the supported-ROM list (both copies), and fetches the
   sources. It then runs every game's patch steps, because a shared library can
   break another game. Each changed source is printed with a comparison link, and each
   patch step as `ok` or `FAIL`.
2. Fix each failing patch, keeping it limited to what tvOS needs. For a
   `.patch` file, commit the old upstream copy in a scratch Git repository, apply
   and commit the patch, cherry-pick it onto the new upstream copy, resolve the
   conflicts, and save the diff. Mario Kart's, Star Fox's, Super Mario 64's and Banjo-Kazooie's adapters
   are the text substitutions in `scripts/prepare-spaghettikart.py`,
   `scripts/prepare-starship.py`, `scripts/prepare-ghostship.py` and
   `scripts/prepare-lighthouse.py`; update the anchors that moved.
   `prepare-ghostship.py` and `prepare-lighthouse.py` stop with an error when
   one of their anchors is gone.
3. If libultraship changed, run
   `bash scripts/check-shipwright-metal.sh arm64 build/upstream/libultraship --record-dependencies`,
   review what changed in `upstream/libultraship-simulator.json`, and commit it.
4. Run `bash scripts/build-nativecade-runtime.sh`,
   `python3 scripts/prepare-nativecade-resources.py`,
   `python3 scripts/prepare-spaghettikart-resources.py`,
   `python3 scripts/prepare-starship-resources.py`,
   `python3 scripts/prepare-ghostship-resources.py`, and
   `python3 scripts/prepare-lighthouse-resources.py`, then build the
   **Nativecade** scheme.
5. Open a pull request. CI builds every game runtime for Apple TV and
   Simulator, the Metal renderer test, and the version-file and ROM-list tests.
   ROMs never leave your machine, so gameplay is checked locally.

## Release checklist

- [ ] Ocarina reaches its title screen in the simulator:
  `xcrun simctl launch <simulator> com.smidley.nativecade --nativecade-play-cached-rom`.
- [ ] Mario Kart passes its controller test:
  `SIMCTL_CHILD_NATIVECADE_KART_INPUT_PROBE=1 xcrun simctl launch --stderr=<log> <simulator> com.smidley.nativecade --nativecade-play-mario-kart`,
  then look for `PASS` in the log.
- [ ] Games restart in one session:
  `SIMCTL_CHILD_NATIVECADE_RESTART_PROBE=oot,kart,oot,kart xcrun simctl launch <simulator> com.smidley.nativecade`
  runs each game for 30 seconds and returns to the library between them. Then
  `xcrun simctl spawn <simulator> log show --last 5m --predicate 'eventMessage CONTAINS "RestartProbe"'`
  must end with `PASS`. New hooks or cached pointers upstream can break restarts.
- [ ] The first launch prepares game assets again, because prepared assets are
  stored per release and Torch version, removes the game's earlier prepared
  assets, and existing saves still load.
- [ ] Save identifiers are unchanged unless the save format changed. RomM
  backups use `recomptv-shipwright-9.3.1`; renaming it hides older backups.
- [ ] The renderer test passes ([instructions](SHIPWRIGHT_RENDER_PROBE.md)).
- [ ] Each updated game plays on the Apple TV: controls, audio and saves.
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the
  Nativecade target, then archive and upload ([TestFlight](NATIVECADE_TESTFLIGHT.md)).
  List the upstream releases in the TestFlight notes.

## Adding a game

A new game must also survive switching games in one app session; follow the
checklist in [Switching games](GAME_SWITCHING.md).

Add `upstream/<game>-baseline.json` with `release`, `sources` and `prepare`.
`upstream.py fetch`, `update` and the weekly check pick it up automatically. A
game that shares libultraship or Torch must use the same commit as the game that
supplies it; `upstream.py` refuses two pins for one checkout. Add any versions
the build needs to `upstream/pins.cmake`.

## Carrying fewer patches

Offer our tvOS and Metal fixes to libultraship, Shipwright and SpaghettiKart.
Every fix accepted upstream is one less patch to update.
