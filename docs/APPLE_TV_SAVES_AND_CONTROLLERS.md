# Game saves, RomM backups, and controller vibration

These features belong to the separate **Shipwright Test** simulator game. The
RecompTV library launch flow is still pending; the game does not share credentials
with the library app. No physical Apple TV deployment is enabled by this change.

## Saving progress

Normal in-game saving writes Shipwright's three JSON save slots. Autosave is on
by default for new settings, runs at safe gameplay points every three minutes,
and also uses the upstream soft-reset hook. An existing explicit autosave choice
is preserved. This is ordinary game saving, not an emulator save-state snapshot.
The game's usual rules determine where Link resumes after loading.

Completed writes retain the upstream flush/fsync/atomic-replace behavior. Slot
copying now uses that same atomic write path, and erase waits for queued saves.
Backgrounding stops vibration and drains already queued local writes. It does
not force an unsafe snapshot in the middle of a cutscene or transaction, and
tvOS does not guarantee time for a final network upload after suspension.

Because tvOS can purge app files, the game also keeps compressed safety copies
in app preferences, capped at 256 KiB for the complete archive. It recovers
missing files at launch. Erase tombstones prevent deleted slots from being
resurrected. Existing files, including unknown future formats, are not silently
replaced. A capacity/write failure appears in **Backup status**; the ordinary
game file is retained. This copy does not survive uninstall or a device reset.

## Connect RomM

Open the port menu with **Escape** on a captured keyboard or the Xbox **View**
button. Controller menu navigation defaults to on if no preference exists;
an explicit existing preference is preserved. Select **Settings → Saves
and Controller → Set up RomM backups**.

1. Paste the standard RomM page address for this game's ROM, such as
   `https://romm.example/rom/123` (a reverse-proxy prefix is supported). Choose
   the same ROM edition used to build this game. Console-mode `/console/rom/…`
   addresses should be replaced with the standard `/rom/…` address.
2. Enter a RomM client API token with **assets.read** and **assets.write**.
   The library's existing ROM-only token may need those permissions. Enter the
   token in the game, not in chat, a settings file, or a launch argument.
3. Check **Backup status**. **Back up saved progress** retries immediately.

The token is stored in the game's Keychain. HTTPS is the default; plain HTTP
requires explicit local-network opt-in. Redirects are refused, including same-
origin redirects, to avoid forwarding credentials to an unexpected destination.
Request timeouts and response size limits are enforced. Server response bodies
and tokens are not included in user-facing diagnostics.

Each successful local save queues a background upload. Offline play continues
using the local files; the latest completed save in each slot is retried during
play, on foregrounding, and on a manual backup request. Uploads use RomM 5.4's
multipart `saveFile` API, the emulator label `recomptv-shipwright-9.3.1`, and
separate `recomptv-file1`, `recomptv-file2`, `recomptv-file3`, and
`recomptv-global` slots. The client creates new versions with unique filenames;
it never calls the update or delete APIs. RomM's server retention policy still
applies. If two clients save different progress, both uploaded versions can be
selected in the restore list, subject to that retention policy.

Only Shipwright 9.3.1's supported save format is accepted. These files are not
interchangeable with EmulatorJS, RetroArch, or ordinary N64 SRAM/EEPROM saves.
There is no automatic merge or overwrite from a second device.

## Restore and undo

**Restore from RomM** lists this game's compatible backups by slot and date.
After selecting and confirming a version, the game downloads and validates it.
Close and reopen the game to apply it. Restore never replaces a file underneath
a running game. Before replacement, the current file is preserved under
`Save/Recovery/<unique-id>/`, and a supported current save is also kept in the
preference archive for **Undo last restore**. Undo also takes effect next launch.
Erasing a slot cancels its pending restore. Reconfiguring RomM cancels pending
downloads for the previous connection. Disconnecting retains existing local
saves and server backups.

## Xbox controller vibration

The game's Rumble Pak commands use SDL's GameController/CoreHaptics path. Rumble
is on by default, and **Rumble strength** scales the existing per-motor mapping
intensities without changing controller bindings. **Test rumble** requests a
half-second effect and reports when no mapped, capable controller is available.
Xbox support depends on the connected model/firmware advertising haptics to tvOS.

Commands renew 250 ms pulses; stopping, disabling rumble, removing mappings,
leaving the game, or backgrounding clears the motors. CoreHaptics engines are
restarted on demand after an interruption. A simulator test can verify motor
commands and timing, but cannot establish how physical vibration feels.

## Validation

`bash scripts/test-shipwright-saves.sh` compiles the real Foundation/Keychain-
adapter client and tests against an isolated loopback RomM API fixture using
synthetic saves and an in-memory credential store. Coverage includes missing-
file recovery, erase, versioned upload, deduplication of unchanged local saves,
offline retry, deferred restore, undo, incompatible formats, credential isolation,
redirect refusal, denied access, and oversized responses. CI runs this on macOS.

The simulator build also supports explicit diagnostics:

- `RECOMPTV_SAVE_TEST_SERVER=http://127.0.0.1:<fixture-port>` runs the same suite
  in an isolated temporary directory and preferences suite inside the simulator.
- `RECOMPTV_CONTROLLER_SELF_TEST=1` tests SDL virtual-controller capabilities,
  strength scaling, pulse renewal, expiration, and immediate stop.
- `RECOMPTV_KEYCHAIN_PROBE_ACCOUNT=test-<unique-identifier>` writes a synthetic
  credential to a separate test account on the first launch, then verifies and
  deletes it on the second launch. It never reads the real backup token.

Both passed on the Apple TV 4K (3rd generation), tvOS 27.0 simulator. The existing
player saves, time-split data, and controller mappings were preserved. No live
RomM account or physical controller was used by the automated tests. Live backup
setup, interactive menu navigation, and physical Xbox vibration still need a
user check. The private simulator Keychain test also passed across a restart.
The CMake target embeds simulator entitlement sections as Xcode does; the signing
helper applies a normal ad-hoc signature and verifies the target is simulator-only.

API contract: [RomM 5.4.1 save endpoints](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/saves.py)
and [RomM save format guidance](https://docs.romm.app/5.4.0/using/saves-and-states/).
