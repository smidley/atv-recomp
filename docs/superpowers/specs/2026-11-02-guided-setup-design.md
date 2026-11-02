# Guided setup and gradual support in Nativecade

Date: 2026-11-02. Mockups: [2026-11-02-guided-setup-mockups.html](2026-11-02-guided-setup-mockups.html)
(open in a browser; the Apple TV screens are drawn at 16:9).

## Why

Nativecade's home screen is a list of equal buttons: Add SMB share, Add RomM, Edit, Remove, Clear ROM
cache, Refresh artwork, Third-party notices, Last game log. A first-time user doesn't know what to do
first or which games will play. It also reads like an iPad screen: small type, many small targets,
little art. Support arrives a few games at a time (ten Nintendo 64 games today), and nothing tells the
user that, so a library that finds 10 of 34 games looks broken.

The owner wants a simple guided experience on the TV:

1. Connect RomM.
2. **Detect platforms**: see the platforms on the server and enable the supported ones. Only supported
   platforms are offered.
3. In each platform, **Scan for games** and add them.

And the app should say plainly that platforms and games are being added gradually.

## Goals

- First launch leads through three steps (Connect, Platforms, Games) with one obvious action per
  screen and a step indicator.
- Only supported platforms can be enabled. Unsupported platforms are counted, never listed:
  "Your server has 9 platforms. Nativecade plays 1 of them so far."
- On a platform's page, Scan for games reports what's playable and what isn't yet, in counts
  ("10 games are ready to play. 24 more aren't supported yet."), and one button adds the playable ones.
- The gradual rollout is always visible: a ribbon "Supported now: Nintendo 64 · Coming over time:
  more consoles and games, added with each update", and a dashed "More platforms are on the way" card
  beside the supported platforms.
- A TV-native look throughout setup and the library (below).
- People who already have games imported never see the welcome flow; their library stays as it is.

## Non-goals

- Supporting more games or platforms. The supported set stays `SupportedGame` (10 Nintendo 64 games).
- Per-game support levels ("works well", "early"). COMPATIBILITY.md proposes levels; not now.
- Changes to how games prepare or run, in-game menus, or the game log.
- An iPhone companion app or QR-code login.

## Anti-goals

- Listing unsupported platforms or games one by one: it reads as a list of things that don't work.
- Several buttons of equal weight on a setup screen.
- Losing or hiding an existing library, saved sources, credentials or favorites.

## The flow (decided with the owner)

Screens are in the mockups file, in order.

1. **Welcome** (first launch only): "Nativecade", one line ("Play the games on your RomM server,
   natively on Apple TV. Setup takes three steps."), focused **Connect RomM**, and a secondary
   **Use an SMB share**.
2. **Connect RomM**: two large fields, server and RomM API token, and **Connect** (decided with the
   owner: keep today's Client API token; no username or password). The screen says which permissions
   to give the token: `roms.read` and `platforms.read`. Entry uses the tvOS keyboard, which also offers
   the iPhone keyboard prompt for pasting the token.
3. **Find your platforms**: "Connected · server name", one focused **Detect platforms** button.
4. **Choose platforms**: one large card per supported platform found on the server, with its game
   count and an on/off state, then a dashed card "More platforms are on the way · They'll appear here
   when an update adds them." The header counts all platforms on the server. **Continue** goes to the
   first enabled platform.
5. **A platform's page** (step 3): **Scan for games**, then a featured game, the counts, a "Ready to
   play" shelf of covers, **Add all N** and **Scan again**.
6. **Library home** after setup: same look. Favorites stay in today's Cover Flow at the top (decided
   with the owner: keep Cover Flow), followed by one cover shelf per enabled platform.
7. **A platform's page after setup** keeps today's Cover Flow of its imported games (`PlatformView`),
   in the new look, with **Scan for games** / **Scan again** as its action. Scanning opens the scan
   results (screen 5) as their own screen; after **Add all N** it returns to the Cover Flow.

## Visual language (decided with the owner: mockup options A and C combined)

- Cinematic backdrop: blurred colors from the games' cover art behind every screen (a calm default
  gradient before any art exists).
- 10-foot type: titles around 76 pt at 1080p, body around 29 pt; content inside tvOS safe areas.
- One focused element at a time, lifted (scale and shadow, white outline); a few large targets; the
  tvOS focus engine drives everything (Siri Remote and controllers).
- Horizontal cover shelves that run off the right edge, on the home's platform rows and the scan
  results. Cover Flow stays for Favorites and each platform's games.
- Step pills (Connect, Platforms, Games) at the top while setting up; completed steps show a check.
- The "Supported now / Coming over time" ribbon at the bottom of setup screens and platform pages,
  generated from the supported-platform list so it updates itself when support grows.

## How it fits the current code

- **Detect platforms needs a new RomM call.** `RomMProvider` (Packages/RecompSources) never asks for
  the server's platforms; `list(.root)` runs one `search_term` query per supported game and groups
  the matches. Detection should call RomM's platform list (`GET /api/platforms`, which returns each
  platform's id, slug, name and ROM count in current RomM) and match supported platforms by RomM slug
  (`n64` for Nintendo 64), keeping that table next to `SupportedGame` so a new platform is one entry.
- **Token permissions.** RomM guards `GET /api/platforms` with the `platforms.read` scope, which
  tokens made under today's instructions (`roms.read` only, docs/NETWORK_SOURCES.md) lack. When the
  platform list returns 401/403, Detect platforms falls back to today's per-game search: it still
  offers the supported platforms it finds, drops the "your server has N platforms" count, and says in
  one line that adding `platforms.read` to the token shows the full count. The connection editor,
  its error text and docs/NETWORK_SOURCES.md ask for both scopes.
- **Scan counts and verification.** A game is only proven playable after `ROMBatchImporter` downloads
  it and checks its SHA-1 against the game's manifest. My call: Scan for games finds *candidates*
  quickly (list the platform's ROMs; match by the hashes RomM reports where present, else by the
  existing title search), and the counts on the page are candidates ("ready to play"); **Add all N**
  runs the existing verified import, then shows a short result ("9 added · 1 is a different version")
  in the same style. The "aren't supported yet" count is the platform's ROM count minus candidates.
- **SMB** has no platforms. My call: Use an SMB share goes Connect → Scan for games directly, treating
  every match as its supported game's platform; the platform step is skipped for SMB-only setups.
- **Settings screen.** Everything on today's home that isn't the library moves to one Settings screen
  reached from a gear next to Search: connections (add, edit, remove, including SMB), Clear ROM cache,
  Refresh artwork, Third-party notices, Last game log. Release builds keep no Diagnostics tab.
- **First run vs existing users.** There is no first-run state today, and the home screen shows its
  empty state until `restoreCache()` finishes re-hashing every cached ROM. The welcome flow must not
  flash for existing users: persist a setup-complete flag, set it after the first platform is added,
  and treat anyone with saved sources or a non-empty ROM cache as already set up (enabling the
  platforms of their imported games). Show a neutral loading state until the cache is restored.
- **New persisted state.** Enabled platforms and the setup-complete flag, in UserDefaults next to the
  existing `library.sources.v1` and `library.favorites.v1` keys (versioned names). Sources, Keychain
  credentials, favorites and the ROM cache are untouched.
- **Disabling a platform** hides its shelf; it doesn't delete imported games.
- **Several connections** (my call). Enabled platforms are stored per supported platform, not per
  server. Detect platforms during setup uses the connection just made; **Scan again** on a platform
  page scans every saved connection that can hold that platform (RomM servers by platform, SMB shares
  by file). "Ready to play" counts each supported game once however many connections hold it; the
  "aren't supported yet" count adds up RomM's ROM counts only, since an SMB share has none. A
  connection added later in Settings is included in the next scan.
- **Platforms after setup** (my call). Choose platforms is a reusable screen, reached from Settings
  ("Platforms"), which also keeps the dashed "More platforms are on the way" card. When an update adds
  a supported platform, the home shows a one-time banner ("New: <platform> is now supported") that
  opens that screen.
- **The connection browser stays** (my call), under Settings → a connection, for importing one
  particular file, revision or SMB folder, restyled to match. Choosing a cover on the "Ready to play"
  shelf before it's added offers **Add this game**.
- **Plain HTTP** (my call). Connect keeps today's per-connection opt-in for `http://` servers; typing
  `http://` alone doesn't allow it.

## Constraints

- tvOS 17+, SwiftUI, Swift Testing for package tests. App behaviour is checked in the simulator.
- Builds that leave the Mac contain no ROMs or ROM-derived data; covers come from RomM at runtime.
- The game runtimes' own menus and controls are out of scope.

## Left to the builder

- Layout metrics, animation, focus details and component structure within the visual language above.
- Exact copy, keeping the tone and the "counted, never listed" rule.
- How Scan matches candidates (RomM hashes when present, title search otherwise), paging, and
  caching platform detection results.
- Test coverage: package tests for platform detection (RomM platform JSON fixtures), the slug table,
  candidate matching and the setup-complete migration; extend `scripts/network-fixtures.py` so its
  fake RomM answers the platform list; simulator screenshots of each setup screen.
