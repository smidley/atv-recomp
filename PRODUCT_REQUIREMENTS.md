# Product Requirements

**Baseline:** 2026-10-28. These requirements describe the intended product; none is a claim of current implementation. Agreed scope comes from the project discussion. Detailed acceptance criteria below are proposed for implementation and review.

## Product goal

Let an Apple TV user browse games already stored on a network share or in RomM, identify which titles this app can run, and launch a supported game locally with a controller.

The user should not need a new server application, a custom Docker container, or a second computer rendering gameplay. An existing SMB server is sufficient; an existing RomM installation is an optional alternative or additional source.

## Intended users

- A player with ROM files on a NAS or Unraid SMB share.
- A RomM user who wants an Apple TV client for their existing catalog.
- A developer validating whether a specific recompilation project can run on tvOS.

The development proof of concept is smaller than the player-facing MVP. Its local ROM provisioning is a development step, not the final library-import experience.

## Agreed MVP scope

| Capability | Requirement |
| --- | --- |
| Native launcher | SwiftUI interface suited to TV viewing and controller navigation |
| SMB source | Connect to a share, browse/select folders, and discover candidate game files without RomM |
| RomM source | Authenticate to an existing instance and import catalog metadata, artwork, and download references |
| Unified library | Present source entries with compatibility information and a way to find eligible games |
| Native runtime | Include one game-specific runtime proven on physical Apple TV |
| ROM validation | Verify accepted revision/hash before starting game code |
| Local cache | Acquire selected game data on demand and show download/validation progress |
| Input and lifecycle | Navigate the launcher, control the game, and return to the library |
| Saves | Support the runtime's game saves and define a recovery policy for tvOS storage |

Majora's Mask is the first feasibility target, subject to [POC.md](POC.md). The MVP must not promise support before that experiment passes.

## User flows

### Connect an SMB source

1. Enter a server/share and credentials where required.
2. Test access and select the folder to discover.
3. List candidate files and expose scan progress or actionable connection errors.
4. Keep the source usable without a RomM account or installation.

Proposed initial behavior: read-only access to ROM folders, with no changes to source files. The SMB implementation and supported protocol/authentication combinations remain open.

### Connect a RomM source

1. Enter the existing instance URL.
2. Authenticate using a method verified against that server version.
3. Import the catalog and available artwork/descriptions.
4. Keep unverified and unsupported entries visibly distinct from launchable games.

Client-token or pairing authentication is a candidate, not a requirement that every RomM version supports the same flow. Minimum server version, scopes, and endpoints must be documented during integration.

### Launch a game

1. Select a library item and inspect its current eligibility.
2. Confirm that a runtime exists in this app build and is eligible for the device.
3. Download/read the required ROM into app-managed staging storage, or select an intact cached copy.
4. Validate the format, size, and authoritative hash against the runtime's accepted revisions.
5. Start the bundled native runtime using the validated local data.
6. Play with a controller, save through the runtime, and return to the launcher.

Show meaningful progress while fetching and validating. A filename, extension, or RomM title match must not bypass byte-level validation.

### Recover from failure

- A missing file or offline source offers retry/reconnect instead of a misleading Play action.
- A wrong revision explains that this runtime needs a different validated revision.
- Interrupted downloads never become launchable cache entries.
- A missing cached ROM can be fetched again when its source is available.
- Save recovery follows the documented storage policy; missing local data must not silently erase a remote backup.

## Proposed acceptance criteria

- On a physical Apple TV, browse a RomM catalog, select the supported game, validate its ROM, and launch native gameplay.
- Repeat the launch from SMB with no RomM dependency.
- Browse and operate the library using the remote or controller; use a supported game controller for gameplay.
- Missing artwork has a usable placeholder; catalog refreshes preserve useful focus.
- Unsupported titles remain discoverable but cannot start an incompatible runtime.
- Wrong hashes, changed files, insufficient space, expired credentials, and interrupted transfers produce clear errors.
- Repeated game launch/exit and controller disconnect/reconnect do not strand the user in the runtime.
- Demonstrate save creation and reload, and resolve the durable-save release gate in [DECISIONS_AND_RISKS.md](DECISIONS_AND_RISKS.md).
- Record actual frame timing, memory use, startup time, and device configuration before setting performance promises.

## Later work

- Additional bundled game runtimes and, potentially, other consoles.
- Optional RomM save synchronization after format and conflict behavior are validated.
- Per-game settings, performance enhancements, and richer library features.
- Additional providers through the same library boundary.

Emulator fallback remains undecided and outside the MVP. Mods, downloadable executable plugins, arbitrary ROM recompilation, and gameplay streaming are not initial requirements.

## Quality and data handling

Use credentials only for the configured provider and keep them out of logs and catalog records. Prefer secure connections, bounded downloads, and recoverable file writes. Provide readable text, predictable focus, and explicit compatibility/error states.

Offline play is conditional on a complete validated cache, available saves, and an eligible runtime/device. It is not a guarantee that tvOS will retain downloaded files indefinitely.

See [ARCHITECTURE.md](ARCHITECTURE.md) for proposed components and [COMPATIBILITY.md](COMPATIBILITY.md) for the validation model.
