# Foundation harness

This is the first implementation step for [M1](../ROADMAP.md). It contains a
native tvOS application, a C ABI implemented in C++, and an on-demand Metal
clear pass. It does not contain Zelda 64: Recompiled, RT64, ROM loading, game
assets, audio, or library providers.

The maintainer [confirmed the simulator bridge and visible color checks](SIMULATOR_PROGRESS.md)
on 2026-10-28. Development continues on the simulator for now. See the
[runtime audit](RUNTIME_AUDIT.md) for the next dependency experiment; physical
Apple TV validation is deferred.

## Open and run

1. On a Mac with Xcode 16 or newer and a tvOS SDK installed, open
   `RecompTV.xcodeproj`. No project generator is required. Allow Swift Package Manager to resolve the launcher's network dependencies, then open the **Diagnostics** tab.
2. Select the shared **RecompTV** scheme.
3. For a simulator check, select an installed Apple TV simulator and Run.
4. For physical validation, pair your Apple TV with Xcode, select it as the run
   destination, and choose your development team under **Signing & Capabilities**.
   Change `com.smidley.RecompTVHarness` if your signing account needs a unique
   bundle identifier. Build and Run.

The target's tvOS 17 deployment setting is a provisional harness floor so it can
use Observation. It is not a supported-device or final product baseline. The
project uses Swift 6 with complete concurrency checking, explicitly nonisolated
default isolation and explicit main-actor UI/rendering ownership. No additional
concurrency features are enabled. Library providers use a separate Swift package;
see [Network sources](NETWORK_SOURCES.md).

## What to check on the TV

- **C++ bridge returned 42:** Swift called `RTVBridgeAdd(19, 23)` through a C
  bridging header and received the expected result from the `.cpp` implementation.
- **Solid blue surface:** an actual `MTKView` clear pass, using a color returned
  by C++. **Next test color** cycles through green, red, and blue. The native
  buttons use tvOS focus navigation with the remote or a controller; this is not
  a game-controller mapping implementation.
- **Confirm blue/green/red frame:** becomes available after successful GPU
  command completion. Check that the surface actually shows the expected color,
  then select this button with the remote. The status explicitly records your
  visual confirmation. GPU submission or completion alone never passes the
  display check; tvOS does not expose a drawable presentation callback.
- **Rerun check:** starts a fresh attempt. Old callbacks cannot mark it passed or
  failed. Backgrounding invalidates the current attempt; returning to the active
  app requests a new frame. Test repeated suspend/resume on physical hardware.

The renderer uses `MTLCommandQueue` and `MTLCommandBuffer.present` followed by
`commit`, not the Metal 4 queue API. There is no shader pipeline or claim about
the eventual game's renderer. Drawable references stay local to the draw call.
MetalKit owns resizing. The view is paused with `enableSetNeedsDisplay = true`,
so it redraws only on requests/layout changes instead of running a game loop.

If no drawable is available, keep the app visible and rerun the check. If the GPU
completion arrives but the expected color is not visible, leave the visual check
unconfirmed and record the failure. A simulator may expose different GPU/presentation
behavior from Apple TV. No Metal device, failed queue/encoder allocation, and GPU
errors are displayed explicitly. Repeated failures are evidence to investigate,
not a reason to bypass the checks.

## Automated checks

Run the portable C/C++ ABI check on Linux or macOS:

```sh
sh scripts/test-native.sh
```

It compiles the consumer as C17 and the implementation as C++17, links them, and
checks the returned arithmetic and RGBA structs, including boundary indices.
Compilers default to `cc`/`c++`; `CC`/`CXX` can select other compiler executables.

On a host with Swift 6, test the presentation evidence state:

```sh
sh scripts/test-evidence.sh
```

These tests cover completion without visual confirmation, premature or stale
confirmation, persistent failures, and fresh attempts. They do not
create a Metal device or simulate actual presentation.

The **Foundation harness** GitHub workflow runs these checks and builds Debug
for the tvOS Simulator and Release for Apple TV without signing. Builds validate
compilation/linking, not device execution or graphics output. Inspect the workflow
result for the exact commit; the presence of a workflow file is not a passing run.

## Physical evidence still required

Use the result record in [POC.md](../POC.md), including:

| Item | Record |
| --- | --- |
| App revision | Exact Git commit being tested |
| Toolchain | Xcode build number, tvOS SDK, signing setup |
| Hardware | Apple TV model/chipset, installed tvOS, remote/controller |
| Native bridge | Visible result; unexpected values or errors |
| Metal | GPU name, drawable size, GPU completion, user-confirmed blue/green/red |
| Lifecycle | Rerun and suspend/resume outcomes, reproduction steps for failures |
| Next gate | Core/renderer adaptation from the pinned runtime audit; hardware validation remains deferred |

No game or device is marked supported by this harness. Passing it does not
complete M1's dependency audit or M2's game boot/gameplay criteria.

## Presentation references

- [Apple: MTKView](https://developer.apple.com/documentation/metalkit/mtkview)
- [Apple: currentDrawable](https://developer.apple.com/documentation/metalkit/mtkview/currentdrawable)
- [Apple: addCompletedHandler](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler(_:))

The tvOS SDK does not provide `MTKView.colorspace` or the drawable presentation
handler. The harness uses a BGRA8 sRGB render target with system-managed
presentation, reports GPU completion, and requires a separate user visual check.
It does not synthesize a display timestamp or treat command completion as proof
that a frame was visible. Record the SDK and physical device used for validation.
