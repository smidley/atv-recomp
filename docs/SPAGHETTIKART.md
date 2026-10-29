# Mario Kart 64 / SpaghettiKart

Nativecade includes the [SpaghettiKart source port](https://github.com/HarbourMasters/SpaghettiKart)
at the release pinned in `upstream/spaghettikart-baseline.json` (1.0.0 on 2026-10-28;
see [Updating game runtimes](UPDATING_UPSTREAM.md)). It runs compiled game code
locally and prepares game assets from the user's imported ROM. No ROM or
extracted game archive is distributed.

## Supported game data

Only **Mario Kart 64 (USA)** is accepted: normalized SHA-1
`579c48e211ae952530ffc8738709f078d5dd215e`, 12,582,912 bytes. Import an
uncompressed `.z64`, `.v64`, or `.n64` from RomM or SMB. The file's bytes determine
its identity and byte order; its name and server metadata do not select a runtime.
Platform-wide import now recognizes both this revision and the existing
Shipwright revisions. RomM artwork uses the same authenticated image cache.

## Building

Follow [Nativecade and TestFlight](NATIVECADE_TESTFLIGHT.md), including the pinned
Shipwright, libultraship and Torch trees. Add the clean SpaghettiKart checkout at
`build/upstream/SpaghettiKart`, using `upstream/spaghettikart-baseline.json`.
The native build prepares generated copies, builds both game frameworks, and
packages arm64 device and simulator slices. Prepare both games' support resources
before building the Nativecade scheme.

`NativecadeRuntime.framework` owns SDL, UIKit, Metal, libultraship and Torch.
`NativecadeSpaghetti.framework` hides its game symbols and links that shared
runtime, avoiding duplicate SDL windows and conflicting N64 game globals.
The XML display-list factory is compiled separately with Mario Kart's F3DEX
encoding. The shared extractor enables MK64 and NAudio, maps three legacy VRAM
definitions explicitly, and preserves SpaghettiKart 1.0.0's hash-based display
list and texture references. It also preserves the full decoded length of
individually compressed MIO0/TKMK00 textures. These adaptations leave the upstream
checkouts intact.

The shared renderer also bounds N64 segment indices before translation. Mario
Kart's byte-aligned raw I8 textures can have odd host addresses; treating their
low bit as a segment tag previously caused an intermittent intro crash.

Preparation rechecks the actual ROM hash, validates support files, extracts into
a staging directory, and checks archive CRCs, required audio entries, and the
title background's decoded size before
installation. Its versioned cache also identifies the extraction adapter, so an
older incompatible result is not reused. Failed preparation does not replace
player saves or another game's ROM cache.

## Storage and controls

Mario Kart uses `Documents/MarioKart64` for its configuration, `default.sav`
EEPROM, and `controllerPak_*.sav` files. Ocarina of Time's save directory remains
separate. Nativecade enters one game per process; close and reopen it to choose
another game.

The default Xbox mapping uses A to accelerate/select, X to brake, left trigger
for items, right shoulder/trigger for hopping and drifting, left stick to steer,
Menu to pause, and View for the port settings. Physical controller behavior,
multiplayer and rumble still require Apple TV testing. Mario Kart's original
save and Controller Pak formats are distinct from Shipwright's JSON saves;
the existing RomM backup UI currently applies to Ocarina of Time only.

The Apple TV performance policy targets 60 FPS with automatic internal
resolution up to 2160p, VSync and no MSAA. Actual resolution depends on GPU load
and the display; this is not a measured performance guarantee on physical A15 hardware.

## Development checks

The Debug simulator launcher accepts `--nativecade-play-mario-kart` to play an
already verified cache entry. `--import-mario-kart-from-romm` is an explicit
simulator-only integration helper that uses a configured RomM account and normal
provider/verification paths. It writes a sanitized success report and never
exports Keychain credentials. Neither Swift helper is included in device or
Release builds.

For an automated simulator input check, launch the cached Mario Kart ROM with
`NATIVECADE_KART_INPUT_PROBE=1`. With no other controller attached, this creates an
SDL virtual controller, presses the normal menu buttons, and holds the
accelerator briefly. It logs PASS only after a non-demo race has begun and the
player's speed increases. It does not write game-state variables. The virtual
controller implementation is excluded from device binaries and is inactive
without the explicit environment flag.

## Verification on 2026-10-28

- Nativecade built and launched on the Apple TV 4K simulator running tvOS 27.0.
- The configured RomM account supplied a USA ROM, verified by its actual bytes.
  Both fresh extraction and reuse of prepared assets reached a race.
- Title screens and the track demo rendered. The SDL virtual-controller test
  navigated the real menus, selected Mario, started Luigi Raceway, and accelerated
  during a non-demo race. This is an input-path smoke test, not a full cup test.
- The 512-byte local EEPROM file persisted unchanged across relaunches. Saving
  a completed cup, time-trial records, and Controller Pak ghosts still need
  functional validation; no Mario Kart RomM backup is claimed.
- Ocarina of Time still rendered its animated title screen with the shared
  renderer changes. Its imported ROM and saves were preserved.
- Both native frameworks linked for arm64 Apple TV and Simulator with matching
  debug symbols and no desktop/OpenGL dependencies. The built app's file scan
  found no ROMs, extracted game archives, or saves.
- All 26 library/network tests passed with HTTP and SMB fixtures, including
  verified runtime selection, byte-order normalization, and artwork caching.

The device frameworks are built, but this Mario Kart revision has not been
uploaded to TestFlight. Physical A15 performance, Xbox input/rumble, audio quality,
multiplayer, saves, and background/resume remain unverified.
