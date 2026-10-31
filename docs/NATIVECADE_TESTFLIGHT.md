# Nativecade playable app and TestFlight

The **Nativecade** scheme in `RecompTV.xcodeproj` combines the SwiftUI library,
on-device Torch asset preparation, Shipwright 9.3.1, SpaghettiKart 1.0.0 and
Starship v2.0.0 (Star Fox 64, in progress), Ghostship 3.0.0 (Super Mario 64, in
progress), Lighthouse 1.2.2 (Banjo-Kazooie, in progress) and BattleShip v1.6 (Super Smash
Bros., in progress) with a shared Metal renderer, and the recompilations SotE-Recomp (Shadows of
the Empire) and Racer (Episode I: Racer) through the [N64 interpreter](N64_INTERPRETER.md).
Its bundle identifier is `com.smidley.nativecade`; App Store Connect app ID is
`6828252318`. The separate **RecompTV** scheme remains the lightweight diagnostics
and network-source harness used by CI. It does not require the game framework.

## Build from source

Use a Mac with Xcode, the tvOS SDK, CMake 3.26 or newer, Ninja, and Python 3.
The runtime script first downloads the upstream releases pinned in
`upstream/shipwright-baseline.json`, `upstream/spaghettikart-baseline.json`,
`upstream/starship-baseline.json`, `upstream/ghostship-baseline.json` and
`upstream/lighthouse-baseline.json` into `build/upstream/` (see [Updating game runtimes](UPDATING_UPSTREAM.md)).
The preparation scripts patch generated copies;
they do not modify those checkouts or existing player data.

```sh
bash scripts/build-nativecade-runtime.sh
python3 scripts/prepare-nativecade-resources.py
python3 scripts/prepare-spaghettikart-resources.py
python3 scripts/prepare-starship-resources.py
python3 scripts/prepare-ghostship-resources.py
python3 scripts/prepare-lighthouse-resources.py
swift scripts/package-nativecade-icons.swift
open RecompTV.xcodeproj
```

The runtime script builds arm64 `appletvsimulator` and `appletvos` slices and
matching debug symbols, then assembles `NativecadeRuntime.xcframework`,
`NativecadeSpaghetti.xcframework`, `NativecadeStarship.xcframework`,
`NativecadeGhostship.xcframework`, `NativecadeLighthouse.xcframework` and
`NativecadeSote.xcframework` under `build/nativecade-runtime`.
Shadows of the Empire's game code and audio microcode run through the
[N64 interpreter](N64_INTERPRETER.md) from the player's ROM, so its framework
contains nothing from a ROM ([Shadows of the Empire](SOTE.md)). The script stops
if an Apple TV build would compile code generated from a ROM.
An explicit SDK argument builds just that slice. The resources script packs only
the port's own support assets, extraction definitions, and third-party notices.
It has no ROM argument and never reads `LocalData`. Both generated directories
are required before building Nativecade; neither belongs in Git.

Select **Nativecade** and an Apple TV simulator, resolve Swift packages, and Run.
For TestFlight, choose **Any tvOS Device (arm64)** and **Product → Archive**, or
archive and upload from Terminal with the Apple ID signed in to Xcode:

```sh
archive="$HOME/Library/Developer/Xcode/Archives/$(date +%F)/Nativecade.xcarchive"
xcodebuild -project RecompTV.xcodeproj -scheme Nativecade -configuration Release \
    -destination 'generic/platform=tvOS' -archivePath "$archive" archive
xcodebuild -exportArchive -archivePath "$archive" -exportPath build/testflight \
    -exportOptionsPlist scripts/testflight-export-options.plist -allowProvisioningUpdates
```

Raise `CURRENT_PROJECT_VERSION` before each upload; App Store Connect rejects a
reused build number.
The tvOS Release configuration uses the existing team's Apple Distribution
certificate and **Nativecade tvOS App Store 2026-10-28** profile. A different
developer must select their own signing team/profile. Provisioning profiles,
certificates, private keys, and account credentials are not in the repository.
The deployment floor is tvOS 17; the intended performance target is Apple TV 4K
(3rd generation, A15). Older hardware and OS versions still need validation.

## Import and play

1. Connect RomM or an SMB share reachable from the Apple TV. Follow
   [Network sources](NETWORK_SOURCES.md), including its token permissions.
2. Browse a platform and import a supported Ocarina of Time ROM, Mario Kart 64
   (USA), Star Fox 64 (USA), Super Mario 64 (USA), Banjo-Kazooie, Shadows of the Empire
   (USA Rev 2), Episode I: Racer (USA) or Super Smash Bros. (USA), or use the
   platform's bulk verification/import action. RomM covers and screenshots appear
   while browsing, and imported games retain their cover art. Each playable game
   has its own pinned ROM allowlist; see [Mario Kart](SPAGHETTIKART.md) and
   [Star Fox](STARSHIP.md), [Super Mario 64](GHOSTSHIP.md) and [Banjo-Kazooie](LIGHTHOUSE.md).
3. Connect a compatible game controller. On the home screen, open the game's
   platform (or **Favorites**), choose the game, and select **Play**. The game's
   page can also add it to Favorites. A RomM game page shows **Play** once that
   game is imported. **Search**, at the top right of the home screen, finds an
   imported game by title. It ignores case, accents and word order, and accepts
   one typo in longer words or initials such as "sm64".
4. Keep Nativecade open during its first preparation. It rechecks the cached
   ROM, extracts assets locally, checks the archive version and every entry's CRC,
   then enters the native game. Later launches reuse that ROM's prepared archive.

ROMs and derived archives stay in the app's private storage. No commercial ROM,
extracted game archive, save, or server credential is bundled with the app.
tvOS gives apps only caches and preferences as local storage, so each game's
settings and saves live in `Library/Caches/Nativecade/Games`. tvOS can purge
cached game data; reimport if needed. Prepared assets are kept per game release and
Torch version in `Library/Caches/Nativecade/Prepared`; when an update changes either, the
game's next preparation deletes its earlier copy first. Ocarina keeps safety copies of its saves in
preferences; Mario Kart, Star Fox, Super Mario 64 and Banjo-Kazooie saves don't have them yet. Save recovery and optional
RomM backups are separate from the ROM cache. See
[Saves and controllers](APPLE_TV_SAVES_AND_CONTROLLERS.md) and
[Apple TV performance](APPLE_TV_PERFORMANCE.md).

To return to the library from any game, hold the controller's View button (on a
PlayStation controller, Create), or the Siri Remote's Play/Pause, for 1.5 seconds.
Progress since the last save or autosave is lost, as when switching off a console.
Any game can then be started again in the same session.

A press of View opens the settings menu of the games built on libultraship
(Ocarina of Time, Mario Kart 64, Star Fox 64's menu bar, Super Mario 64,
Banjo-Kazooie, Super Smash Bros.) and of Racer. The D-pad moves through it, A
selects and B goes back; its red power button (Quit) also returns to the library.
In Star Fox 64, View shows the menu bar and X moves into it, as ImGui's controller
layout does for menu bars.
Shadows of the Empire keeps its settings in the game's own Options screen (Start).
[Controls and menus](CONTROLS_AND_MENUS.md) has the details for each game.
Before build 9, only Ocarina's menu opened, and it couldn't be navigated: the
menus' regions stopped the D-pad at their borders. Quitting and the menus on a
physical Apple TV remain part of the hardware test pass.

When a game fails on the Apple TV (a crash, or a screen that stays black), open
**Diagnostics → Last game log**. While a game runs, its console output goes to
`Library/Caches/Nativecade/Logs/last-game.log` instead of the console; a crash adds
the signal and a backtrace, and the log stays open until the next game starts, so a
crash on the way back to the library is recorded too. The screen shows the end of
the log, a line per focus step. Its addresses can be matched against the archive's
debug symbols on the Mac (`atos`), which is how hardware failures are diagnosed
without pairing the Apple TV.

Neither port was written to start twice in one process.
[Switching games](GAME_SWITCHING.md) explains what Nativecade resets between games,
the small upstream changes this needed, and how to check a new game.

Large libraries stay smooth: a platform page draws only the covers near the
selected game, and the library is sorted and indexed for search once per change,
not on every swipe. To try thousands of games, Debug simulator builds add that
many placeholder games (titles only, no ROM, kept in memory):

```sh
SIMCTL_CHILD_NATIVECADE_SYNTHETIC_LIBRARY=5000 xcrun simctl launch <simulator> com.smidley.nativecade
```

## Verification recorded on 2026-10-28

- Native runtime linked for both Apple TV and Apple TV Simulator without desktop
  or OpenGL framework dependencies. Device archive has matching runtime dSYMs.
- Nativecade Debug built and launched on the tvOS 27.0 Apple TV 4K simulator.
  The imported NTSC 1.0 US ROM was extracted inside the app in about nine seconds,
  passed validation, and rendered the game's animated title screen.
- The launcher responds to remote focus navigation and its Play action starts
  preparation. The game also has an explicit Debug/simulator-only
  `--nativecade-play-cached-rom` smoke-test argument. It uses an already verified
  cache and is excluded from device and Release builds.
- Network-source/cache tests passed: 18 tests, including revalidation immediately
  before the native handoff and rejection of tampered or unindexed cache files.
- The signed device archive passed deep signature verification and a scan for
  ROMs/extracted game archives. It contains the app/runtime privacy manifests
  and upstream notices.
- The RecompTV diagnostics/library harness still builds independently.
- Xcode reported a successful internal TestFlight upload of version **0.1.0 (1)**.
  App Store Connect processing and tester availability are separate checks.

Build **0.1.0 (2)** adds RomM covers, screenshots, bounded offline artwork caching,
artwork refresh for earlier imports, and Mario Kart 64 through SpaghettiKart.
Its simulator build and 26 host tests passed; the earlier tvOS source/artwork
probe also passed. Mario Kart's real menu and race input path passed an SDL
virtual-controller test; [details and limitations](SPAGHETTIKART.md).
On 2026-10-29, build 2 was archived from commit `a11ac1a` (merged with `main`)
and uploaded to App Store Connect. Its embedded runtime frameworks match their
debug symbols, and the archive contains no ROMs, extracted game archives, saves,
or debug launch options. Build 1 does not include artwork or Mario Kart.

Build **0.1.0 (3)** finds artwork for games imported before build 2, and Quit now
returns to the library so any game can start again
([Switching games](GAME_SWITCHING.md)). On 2026-10-29 it was archived from commit
`2854e54` with the build number raised to 3, and uploaded to App Store Connect. Its
runtime frameworks match their debug symbols, and the archive contains no ROMs,
extracted game archives, saves, or simulator test options.

Build **0.1.0 (4)** shows only what Nativecade can play: RomM lists the platforms
that hold a supported game, with RomM's platform icon, and one card per game
([Network sources](NETWORK_SOURCES.md)). Each platform and game opens its own
screen, and Release builds no longer show a one-tab bar that caught focus. On
2026-10-29 it was archived from commit `4c0a17c` with the build number raised to
4, and uploaded to App Store Connect.
Its runtime frameworks are build 3's (identical apart from code signatures) and
match their debug symbols; the archive contains no ROMs, extracted game archives,
saves, or simulator test options. Back on the Siri Remote still needs a check on
the Apple TV, because the simulator tools cannot press Menu.

Build **0.1.0 (5)** fixes "not enough storage" when preparing a game on the Apple
TV: each game now keeps its files in `Library/Caches/Nativecade/Games`. Its home
screen shows Favorites and one card per platform; a platform lists its games, and
each game's page has Play and a favorite toggle. It also adds Star Fox 64. On
2026-10-29 it was archived from commit `92eba87` with Xcode 27.2 (27B52), whose
update had arrived through the Mac App Store that evening. Its runtime frameworks
match their debug symbols, and the archive contains no ROMs, extracted game
archives, saves, or simulator test options. App Store Connect rejected the upload
("Unsupported SDK or Xcode version"); builds 1 to 4 used Xcode 27.1. In the tvOS 27.0 simulator,
the restart check passed twice with all three games, each game's archives were
hard links in its own `Games` folder with no leftover temporary files, and a
favorite appeared on the home screen and persisted across launches. The fix
itself needs the Apple TV: the simulator also allowed `Documents`.

Build **0.1.0 (6)** browses games in a cover flow and adds Super Mario 64. It was
archived on 2026-10-29 from commit `e0ef217` and was never uploaded, for the same
reason; build 7 replaces it.

Build **0.1.0 (7)** adds game search with fuzzy matching, keeps large libraries
smooth to browse, and adds Banjo-Kazooie. Every game now uses the newer
libultraship and Torch that Lighthouse ships, so Mario Kart, Star Fox and Super
Mario 64 prepare their assets again on first launch, and each game deletes its
outdated prepared assets first. On 2026-10-30 it was archived from commit
`91de927` with Xcode 27.2 (27B52) and the tvOS 27.2 SDK. All five runtime
frameworks match their debug symbols, and the archive contains no ROMs,
extracted game archives, saves, or simulator test options. App Store Connect
first rejected the upload ("Unsupported SDK or Xcode version"), probably because
Apple's [releases page](https://developer.apple.com/news/releases/) still listed
Xcode 27.2 RC (27B48) as the newest Xcode. The same archive was uploaded again
every 30 minutes, and on 2026-10-30 at 10:35 App Store Connect accepted it and
began processing it. Builds 5 and 6 were never accepted; build 7 replaces them.
In the tvOS simulator, every game started and switched in one session, and
Banjo-Kazooie played its opening.

Build **0.1.0 (8)** adds Star Wars: Shadows of the Empire, whose game code and
audio microcode run through the [N64 interpreter](N64_INTERPRETER.md) from the
player's ROM ([Shadows of the Empire](SOTE.md)). On 2026-10-30 it was archived
from commit `0b91b17` with Xcode 27.2 (27B52) and uploaded; App Store Connect
accepted it at 14:33. Besides the usual checks (no ROMs, extracted game archives,
saves, or simulator test options), every binary in the archive was compared with
the SotE ROM and its decompressed executable: the only shared 32-byte runs are
SotE-Recomp's own copy of the game's legal notice and short counting sequences in
the shared runtime. The SotE framework contains the interpreters and none of the
generated code. In the simulator SotE plays only headless, so its picture, speed
and controls need this build on the Apple TV.

Build **0.1.0 (9)** adds Star Wars Episode I: Racer, through the same N64
interpreter ([Racer](RACER.md)), and Super Smash Bros. through BattleShip
([Super Smash Bros.](BATTLESHIP.md)). It also makes every game's settings menu
reachable and navigable with a controller, and lets holding View (or the Siri
Remote's Play/Pause) for 1.5 seconds quit any game; in build 8 only Ocarina's
menu opened, it couldn't be navigated, and no game could be quit without it. On
2026-10-30 it was archived with Xcode 27.2 (27B52). Besides the usual checks, every
binary in the archive was compared with the Shadows of the Empire and Racer ROMs:
the only shared 32-byte runs are counting sequences and SotE-Recomp's copy of the
game's legal notice. The first upload stopped because Xcode's Apple Account needed
signing in again; the next was refused because Racer's framework gave its version
as `v0.3.0`, and App Store Connect takes only numbers. With `0.3.0` (its CMake
now strips the tag's `v`), the archive was made again and App Store Connect
accepted it at 17:17. Super Smash Bros. hasn't run with a ROM yet.

Torch emits some duplicate asset names. `ZIP_CHECKCONS` rejects those valid
archives with `ZIP_ER_EXISTS`; Nativecade instead opens them read-only, checks
the 9.3.1 version record, and reads every entry to validate its CRC.

Simulator rendering is not evidence of a sustained 4K/60 fps result on A15.
Physical Xbox input/rumble, audio quality, save recovery, RomM backup setup, and
background/resume must be checked on the user's Apple TV. The previous standalone
simulator experiment and its private saves are preserved.
