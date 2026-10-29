# Nativecade playable app and TestFlight

The **Nativecade** scheme in `RecompTV.xcodeproj` combines the SwiftUI library,
on-device Torch asset preparation, and Shipwright 9.3.1 with its Metal renderer.
Its bundle identifier is `com.smidley.nativecade`; App Store Connect app ID is
`6828252318`. The separate **RecompTV** scheme remains the lightweight diagnostics
and network-source harness used by CI. It does not require the game framework.

## Build from source

Use a Mac with Xcode, the tvOS SDK, CMake 3.26 or newer, Ninja, and Python 3.
Place clean checkouts at the exact revisions in `upstream/shipwright-baseline.json`
under `build/upstream/Shipwright`, `build/upstream/Torch`, and
`build/upstream/libultraship`. The preparation scripts patch generated copies;
they do not modify those checkouts or existing player data.

```sh
bash scripts/build-nativecade-runtime.sh
python3 scripts/prepare-nativecade-resources.py
swift scripts/package-nativecade-icons.swift
open RecompTV.xcodeproj
```

The runtime script builds arm64 `appletvsimulator` and `appletvos` slices and
matching debug symbols, then assembles `build/nativecade-runtime/NativecadeRuntime.xcframework`.
An explicit SDK argument builds just that slice. The resources script packs only
the port's own support assets, extraction definitions, and third-party notices.
It has no ROM argument and never reads `LocalData`. Both generated directories
are required before building Nativecade; neither belongs in Git.

Select **Nativecade** and an Apple TV simulator, resolve Swift packages, and Run.
For TestFlight, choose **Any tvOS Device (arm64)** and **Product → Archive**.
The tvOS Release configuration uses the existing team's Apple Distribution
certificate and **Nativecade tvOS App Store 2026-10-28** profile. A different
developer must select their own signing team/profile. Provisioning profiles,
certificates, private keys, and account credentials are not in the repository.
The deployment floor is tvOS 17; the intended performance target is Apple TV 4K
(3rd generation, A15). Older hardware and OS versions still need validation.

## Import and play

1. Connect RomM or an SMB share reachable from the Apple TV. Follow
   [Network sources](NETWORK_SOURCES.md), including its token permissions.
2. Browse a platform and import one supported Ocarina of Time ROM, or use the
   platform's bulk verification/import action. Other games are not playable yet.
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

The first version enters one game per app session. To return to the library,
close and reopen Nativecade. Game exit/resume and sustained hardware performance
remain part of the physical Apple TV test pass.

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

Torch emits some duplicate asset names. `ZIP_CHECKCONS` rejects those valid
archives with `ZIP_ER_EXISTS`; Nativecade instead opens them read-only, checks
the 9.3.1 version record, and reads every entry to validate its CRC.

Simulator rendering is not evidence of a sustained 4K/60 fps result on A15.
Physical Xbox input/rumble, audio quality, save recovery, RomM backup setup, and
background/resume must be checked on the user's Apple TV. The previous standalone
simulator experiment and its private saves are preserved.
