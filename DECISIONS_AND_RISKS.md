# Decisions and Risks

**Baseline:** 2026-10-28. This register separates agreed project direction from implementation proposals and unanswered feasibility questions. A foundation app/bridge/Metal probe is implemented; no game runtime, game renderer, provider integration, or physical Apple TV result has been demonstrated.

## Foundation implementation note — 2026-10-28

The first source harness uses a C ABI backed by C++17, Swift 6 complete concurrency checking, and MetalKit's standard command-buffer presentation path. It uses the tvOS 17 APIs needed for Observation as a provisional development floor. These choices avoid importing the game runtime before the basic app/bridge/presentation checks exist. They do not resolve the minimum supported Apple TV, upstream dependency selection, runtime threading, or P01's device-evidence requirement. See [the harness instructions](docs/FOUNDATION_HARNESS.md); all device gates remain open.

## Agreed decisions

| ID | Decision | Consequence |
| --- | --- | --- |
| D01 | RecompTV is the working name; smidley/atv-recomp is the project repository | Naming can be revisited before release |
| D02 | Build a native Apple TV app with SwiftUI and native game code | tvOS and physical hardware are the target environment |
| D03 | Games execute locally on Apple TV | The server supplies files/metadata, not rendered gameplay |
| D04 | Require no custom server software or additional container | Use existing SMB storage and optional RomM |
| D05 | SMB works independently of RomM | Neither provider may become a hidden dependency of the other |
| D06 | Bundle game-specific compiled runtimes in the app | New runtime code ships through an app build |
| D07 | Users supply game data; the project does not distribute commercial ROMs/assets | Keep game data out of source and public artifacts |
| D08 | Exact ROM identity determines compatibility | Discovery and metadata are insufficient for launch |
| D09 | Acquire/cache selected games as needed | No requirement to mirror an entire collection |
| D10 | Validate native recompilation before the full launcher | Runtime/renderer feasibility drives the roadmap |
| D11 | Majora's Mask is the first POC candidate | It is not a confirmed supported title |
| D12 | Preserve modular providers and runtimes | Other games/consoles remain possible future work |
| D13 | Optional save synchronization and expanded compatibility come later | The initial project must still address safe save handling |

## Proposed implementation choices

These choices make the plan actionable but are not yet adopted or proven.

| ID | Proposal | Evidence needed |
| --- | --- | --- |
| P01 | A narrow Swift/C/C++ runtime boundary with explicit host services | A working device bridge and lifecycle experiment |
| P02 | Staged ROM transfers, content validation, then cache promotion | Interruption, changed-file, and low-space behavior |
| P03 | SHA-256 identification with a documented canonical representation | Pinned upstream revision and normalization tests |
| P04 | Read-only SMB ROM access | Library compatibility and independent-source tests |
| P05 | RomM client tokens/pairing where supported | Actual server-version/authentication integration |
| P06 | Separate game saves from replaceable caches | Save/reload and durable recovery tests |

## Open decisions

| Question | Resolve by |
| --- | --- |
| Which Apple TV model and tvOS version form the minimum baseline? | POC measurements, before advertising support |
| Which upstream commit and dependency revisions should be pinned? | Start of the game integration experiment |
| Can the renderer's required features and shaders work on tvOS? | POC dependency/rendering checkpoints |
| Which SMB client meets platform and licensing needs? | Before SMB integration |
| Which RomM versions, scopes, and authentication flows are supported? | Before RomM integration |
| What is the exact accepted ROM region/revision/format/hash set? | Before the first game launch |
| How will local saves survive purge, reinstall, or device loss? | Before a player-facing release |
| Which project license and redistribution model are appropriate? | Before importing/distributing dependencies |
| Which distribution route is practical: development installs, testing, or App Store? | After feasibility and license/policy review |
| What performance and stability targets are realistic? | After device measurements |
| Should emulator fallback ever be included? | Separate future scope decision |

## Risk register

| Risk | Impact | Next action / exit evidence |
| --- | --- | --- |
| Runtime or dependencies assume desktop APIs | Prevents tvOS integration | Pin revisions, audit host/runtime dependencies, and compile a minimal device target |
| Renderer needs unsupported GPU features or shader behavior | No output, visual defects, or unusable performance | Test required features and real game scenes on physical Apple TV |
| Desktop ARM64 success is mistaken for tvOS success | Misleading feasibility/support claims | Keep platform-specific evidence in the POC and compatibility matrix |
| tvOS storage cannot preserve saves as assumed | Loss of player progress | Verify current storage behavior and select/test durable backup and recovery before release |
| Interrupted downloads or altered ROM data bypass validation | Runtime failures or wrong game behavior | Stage transfers, validate bytes, and reject stale or mismatched content |
| SMB implementation lacks required platform/authentication support | Share cannot be used | Evaluate a small read-only spike against the actual intended server |
| RomM API/authentication differs by deployment | Catalog/download failures | Use a versioned integration and each server's published API schema |
| Save formats or concurrent edits conflict during future sync | Progress overwritten or unreadable | Verify formats and retain conflicting copies before enabling synchronization |
| Runtime crashes or mishandles suspension | App exits or state is lost | Repeated launch/exit and lifecycle tests, recoverable writes |
| Native runtime updates grow app size and maintenance work | Slow releases and compatibility regressions | Add one runtime at a time with pinned dependencies and regression evidence |
| Licensing or distribution restrictions conflict with the chosen package | Release cannot proceed as designed | Inventory licenses and review the intended distribution package before release |
| Apple review treatment of a recomp launcher is uncertain | Public distribution may be unavailable | Evaluate the actual binary/content model under current guidelines; do not promise approval |

## Source-backed observations

Sources below were checked on 2026-10-28. Recheck them when selecting versions or preparing a release.

- [Zelda 64: Recompiled](https://github.com/Zelda64Recomp/Zelda64Recomp) describes static recompilation of Majora's Mask, use of RT64, desktop platforms including macOS, and a requirement for user game data. Its repository identifies GPL-3.0 licensing. These observations establish a candidate starting point, not tvOS compatibility. Consult its [contribution policy](https://github.com/Zelda64Recomp/Zelda64Recomp/blob/dev/CONTRIBUTING.md) before considering any upstream contribution.
- [RomM's API reference](https://docs.romm.app/latest/developers/api-reference/) points developers to the API specification served by each instance. Its [client API token documentation](https://docs.romm.app/latest/developers/client-api-tokens/) describes scoped tokens and pairing. RecompTV still needs to select and test an integration baseline.
- Apple's [archived tvOS programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/index.html) describes purgeable local app data. It is historical guidance; confirm current SDK/device behavior rather than copying its numeric limits into requirements.
- Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) address downloaded code in section 2.5.2, emulator/game offerings in section 4.7, and intellectual property in section 5.2. Whether this specific recompilation design qualifies for distribution remains unresolved. Bundling code and requiring user ROM data do not by themselves establish approval or legal clearance.

## Decision discipline

When resolving an open question, record the date, chosen option, rejected alternatives that materially affected the choice, and supporting build/test/source evidence. Update the requirements, architecture, roadmap, and compatibility matrix together when the choice changes scope.

Document a blocker concretely instead of turning an assumption into a product promise. The immediate next action is the device-based experiment in [POC.md](POC.md).
