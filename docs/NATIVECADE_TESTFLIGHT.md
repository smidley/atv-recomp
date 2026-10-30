# Nativecade playable app and TestFlight

The **Nativecade** scheme in `RecompTV.xcodeproj` combines the SwiftUI library,
on-device Torch asset preparation, Shipwright 9.3.1, and SpaghettiKart 1.0.0
with a shared Metal renderer.
Its bundle identifier is `com.smidley.nativecade`; App Store Connect app ID is
`6828252318`. The separate **RecompTV** scheme remains the lightweight diagnostics
and network-source harness used by CI. It does not require the game framework.

## Build from source

Use a Mac with Xcode, the tvOS SDK, CMake 3.26 or newer, Ninja, and Python 3.
The runtime script first downloads the upstream releases pinned in
`upstream/shipwright-baseline.json` and `upstream/spaghettikart-baseline.json`
into `build/upstream/` (see [Updating game runtimes](UPDATING_UPSTREAM.md)).
The preparation scripts patch generated copies;
they do not modify those checkouts or existing player data.

```sh
bash scripts/build-nativecade-runtime.sh
python3 scripts/prepare-nativecade-resources.py
python3 scripts/prepare-spaghettikart-resources.py
swift scripts/package-nativecade-icons.swift
open RecompTV.xcodeproj
```

The runtime script builds arm64 `appletvsimulator` and `appletvos` slices and
matching debug symbols, then assembles `NativecadeRuntime.xcframework` and
`NativecadeSpaghetti.xcframework` under `build/nativecade-runtime`.
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
2. Browse a platform and import a supported Ocarina of Time ROM or Mario Kart 64
   (USA), or use the
   platform's bulk verification/import action. RomM covers and screenshots appear
   while browsing, and imported games retain their cover art. Each playable game
   has its own pinned ROM allowlist; see [Mario Kart](SPAGHETTIKART.md).
3. Connect a compatible game controller and select **Play** on a verified ROM.
4. Keep Nativecade open during its first preparation. It rechecks the cached
   ROM, extracts assets locally, checks the archive version and every entry's CRC,
   then enters the native game. Later launches reuse that ROM's prepared archive.

ROMs and derived archives stay in the app's private storage. No commercial ROM,
extracted game archive, save, or server credential is bundled with the app.
tvOS can purge cached game data; reimport if needed. Save recovery and optional
RomM backups are separate from the ROM cache. See
[Saves and controllers](APPLE_TV_SAVES_AND_CONTROLLERS.md) and
[Apple TV performance](APPLE_TV_PERFORMANCE.md).

To return to the library, open the game's menu with the controller's View button
and select its red power button (Quit). Progress since the last save or autosave
is lost, as when switching off a console. Any game can then be started again in
the same session. Quitting with a physical controller and sustained hardware
performance remain part of the physical Apple TV test pass.

Neither port was written to start twice in one process.
[Switching games](GAME_SWITCHING.md) explains what Nativecade resets between games,
the small upstream changes this needed, and how to check a new game.

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
On 2026-10-29, build 2 was archived from commit `469bfda` (merged with `main`)
and uploaded to App Store Connect. Its embedded runtime frameworks match their
debug symbols, and the archive contains no ROMs, extracted game archives, saves,
or debug launch options. Build 1 does not include artwork or Mario Kart.

Build **0.1.0 (3)** finds artwork for games imported before build 2, and Quit now
returns to the library so any game can start again
([Switching games](GAME_SWITCHING.md)). On 2026-10-29 it was archived from commit
`da3089a` with the build number raised to 3, and uploaded to App Store Connect. Its
runtime frameworks match their debug symbols, and the archive contains no ROMs,
extracted game archives, saves, or simulator test options.

Build **0.1.0 (4)** shows only what Nativecade can play: RomM lists the platforms
that hold a supported game, with RomM's platform icon, and one card per game
([Network sources](NETWORK_SOURCES.md)). Each platform and game opens its own
screen, and Release builds no longer show a one-tab bar that caught focus. On
2026-10-29 it was archived from commit `5bd89b7` with the build number raised to
4, and uploaded to App Store Connect.
Its runtime frameworks are build 3's (identical apart from code signatures) and
match their debug symbols; the archive contains no ROMs, extracted game archives,
saves, or simulator test options. Back on the Siri Remote still needs a check on
the Apple TV, because the simulator tools cannot press Menu.

Torch emits some duplicate asset names. `ZIP_CHECKCONS` rejects those valid
archives with `ZIP_ER_EXISTS`; Nativecade instead opens them read-only, checks
the 9.3.1 version record, and reads every entry to validate its CRC.

Simulator rendering is not evidence of a sustained 4K/60 fps result on A15.
Physical Xbox input/rumble, audio quality, save recovery, RomM backup setup, and
background/resume must be checked on the user's Apple TV. The previous standalone
simulator experiment and its private saves are preserved.
