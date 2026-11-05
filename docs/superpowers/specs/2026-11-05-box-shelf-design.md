# Box shelf: games as real boxes and cartridges

Date: 2026-11-05. Mockups, to open in a browser (drawn at 16:9, with stand-in cover art):
[shelf views](2026-11-05-box-shelf-mockup-shelves.html) and
[opening a box](2026-11-05-box-shelf-mockup-opening.html).

## Why

The owner likes the look of [Boxshelf](https://github.com/sassiestrhihno/boxshelf-source), a Windows and
Android game launcher: "things being 3D, like having the physical box and media for the game." Nativecade's
library shows flat cover art, as tiles on the home screen, a Cover Flow on a platform's page and a grid in
search. The owner wants every game to look like the real object: a Nintendo 64 box on a shelf, with its
cartridge inside.

Boxshelf's code can't be used. It is JavaScript (Electron and Capacitor) under the GPL-3.0, and Nativecade
is a SwiftUI tvOS app with no license of its own. The design is rebuilt from the idea; no Boxshelf code,
assets or 3D models are copied.

## Decided with the owner

1. **Where:** every screen that shows games uses shelves of 3D boxes: the home screen, a platform's page
   and search. Setup and Settings keep their current look.
2. **Two shelf views, both kept.** The player picks one in Settings.
   - **Facing you:** boxes stand face-out, like a store shelf. The focused box comes forward, and its
     cartridge rises partway out of the top of the box.
   - **Spines out:** boxes stand spine-out, like a collection. The boxes beside the focused one slide
     apart, and the focused box slides out and turns toward the viewer.
3. **Picking a game opens its box, "look first":**
   1. Select brings the box forward, larger, and the shelf behind it dims.
   2. Left and right on the remote turn the box: front, spine, back, the other side.
   3. Select opens it: the cartridge comes up out of the box toward the viewer, and the box dims.
   4. Select again starts the game.
   5. Back steps back one stage at a time: the cartridge goes back into the box, then the box goes back on
      the shelf.

   This replaces today's game page (`GameView`).
4. **The art comes from RomM:** each box's front, back and spine, and the cartridge (or disc) art. The
   owner's RomM 5.4.1 can supply them, but today it downloads only front covers, screenshots and manuals.
   The owner turns the rest on; Nativecade never changes RomM's settings or starts its scans. See
   [The owner's RomM steps](#the-owners-romm-steps).
5. **tvOS 26 and RealityKit:** Nativecade's deployment target goes from tvOS 17 to tvOS 26, so the
   shelves can be built with RealityKit, Apple's current 3D engine.

Switch games were considered in the same conversation and dropped; they are not part of this.

## Calls made in the conversation, not confirmed by the owner

Each of these was said to the owner without objection, or is a call made while writing this up. The owner
can override any of them.

- **Missing art is drawn,** so every game still appears as a box:
  - spine: the game's title on a dark band, under a stripe in a color taken from the cover;
  - back: the game's description and up to two screenshots from RomM;
  - cartridge label: the front cover, cropped to the label;
  - front: today's generated title art (`TitleArt`), when there is no cover at all, as with games from an
    SMB share.
- **Drawn art never imitates Nintendo's trademarks:** the platform is plain text ("Nintendo 64"), never a
  logo or the real boxes' trade dress.
- **Favorites** become a shelf, first on the home screen, in place of today's Cover Flow. In the picked
  view, "Add to Favorites" is a button under the box, reached by swiping down, so left and right always
  turn the box.
- **Today's game page details** move into the picked view: the title, revision and file name in a caption
  line under the box. The screenshots appear on the drawn back. When RomM has a scan of the real back,
  that scan is shown instead, and the screenshots don't appear separately.
- **A platform's page** is a wall of shelves holding all that platform's games, with Scan for games kept
  above it. **Search** shows its results as a shelf.
- **Facing you** is the default view.
- **The look** follows the mockups: a dark walnut shelf, soft light from above, a soft shadow under each
  box, on the app's ink-graphite page (`Palette.page`). The boxes and cartridges carry the color; the
  chrome (captions, buttons, the Nativecade wordmark) stays as today.
- **How smoothness is proven:** the owner can't pair the Apple TV, so the proof is a TestFlight build on
  their own library (10 games today). The shelf logs a summary of its frame times (the worst frame and
  the 95th percentile) where the owner can photograph it, the way build 19 logged RT64's frames. A
  50-box test shelf in the simulator checks that only the boxes on screen are drawn; the simulator says
  nothing about speed. No extra test switch goes into Settings.
- **Other platforms' media:** Nintendo 64 games get a cartridge. The object inside a box comes from the
  platform, so a disc-based platform added later gets a disc, using RomM's same cartridge-or-disc art.

## Goals

- Every game reads as a physical object: a box with depth, light and shadow, and a cartridge inside it.
- Smooth on the owner's Apple TV 4K (3rd generation, A15): 60 frames per second while moving along a
  shelf and while a box comes forward, turns and opens.
- The remote drives everything with the moves above: left and right, up and down between shelves,
  Select, Back. No other hidden gestures.
- Starting a game from a shelf takes three Select presses.

## Non-goals

- No change to setup or Settings, except the new choice between the two shelf views.
- No new art sources in Nativecade. RomM is the only source; Nativecade doesn't call LaunchBox or
  ScreenScraper itself.
- None of Boxshelf's other features: the museum wall and its lighting modes, manuals, the attract mode,
  trailers, achievements and disc-loading animations.
- No change to which games or platforms play.

## Anti-goals

These would make it a failure even if it works:

- Stutter, dropped frames or slow art loading on the Apple TV.
- Boxes that look like flat cards, or cheap placeholders.
- Starting a game becoming slower or more confusing than today's Play button.
- Drawn art that copies Nintendo's logos or box designs.

## Constraints

- **tvOS 26** becomes the deployment target of every target (tvOS 17 today), as the owner decided. The
  owner's Apple TV needs tvOS 26 or later.
- **Testing:** the owner tests on the Apple TV only through TestFlight builds; they won't pair it with the
  Mac. The simulator is fine for screenshots, but it isn't evidence of A15 performance.
- **No ROM data in builds** that leave the Mac (standing rule). Art is downloaded at runtime like today's
  covers.
- **RomM's data,** checked on 2026-11-05 against the owner's server's own API schema (`/openapi.json`,
  RomM 5.4.1) and RomM 5.4.1's source:
  - Both the list and the detail ROM responses (`SimpleRomSchema`, `DetailedRomSchema`) carry
    `ss_metadata` (from ScreenScraper) and `launchbox_metadata` (from LaunchBox).
  - Each of those can hold `box2d_path` (front), `box2d_back_path` (back), `box2d_side_path` (spine) and
    `box3d_path`. Only `ss_metadata` has `physical_path`, the cartridge or disc art.
  - A path is relative to RomM's resources, such as `roms/<platform id>/<rom id>/box2d_back/box2d_back.png`,
    and is served under `/assets/romm/resources/`.
  - RomM 5.4.1's own web app builds its 3D box from the same fields: ScreenScraper's first, then
    LaunchBox's, with the front falling back to the cover (`frontend/src/v2/composables/useBoxFaces`).
  - Nativecade decodes today's covers and screenshots in `RomMProvider` (`path_cover_small`,
    `path_cover_large`, `merged_screenshots`) and caches images in its Artwork cache.
- **Proportions:** a Nintendo 64 box front is landscape, about 1.37 to 1, like RomM's covers. A cartridge
  face is about 1.55 to 1, as drawn by today's `Cartridge` view.
- **Focus:** tvOS's focus engine doesn't know about objects inside a 3D scene, so the shelf probably
  handles the remote's moves, Select and Back itself. VoiceOver still needs each box as an element named
  for its game.
- **No GPL code** from Boxshelf.

## Left to the builder

- How the shelves are built with RealityKit. Checked in Xcode 27.2's tvOS SDK: RealityKit, with SwiftUI's
  `RealityView` and `MeshResource.generateBox`, is available from tvOS 26.0.
- Sizes, materials, lighting and animation timing, using the mockups as the reference and the app's one
  easing curve, `timingCurve(0.22, 1, 0.36, 1)`.
- How shelves scroll, how many boxes fit, and how dense the spines-out view is.
- Loading and caching the extra art, and drawing the missing faces (for example, rendering each drawn
  face once into an image and caching it).

## The owner's RomM steps

These are on the server, not in the app. Nativecade works without them, with drawn faces.

1. RomM's web app, Settings → Scan: turn on the back cover and box spine media types. LaunchBox, already
   on for this server, supplies them.
2. For cartridge art: add a free ScreenScraper account to RomM's container settings as
   `SCREENSCRAPER_USER` and `SCREENSCRAPER_PASSWORD`, then turn on the cartridge-or-disc media type on the
   same Scan page.
3. Re-scan the Nintendo 64 platform so RomM downloads the new art for games it already has.
