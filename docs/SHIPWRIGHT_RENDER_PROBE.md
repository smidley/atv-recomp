# Shipwright Metal execution fixture

PRs [#4](https://github.com/smidley/atv-recomp/pull/4) and
[#5](https://github.com/smidley/atv-recomp/pull/5) merged into `main` at
`b8acc768ec1e2944fbed535a3377b0c4bfc1ffbc`. The
[previous build checks](https://github.com/smidley/atv-recomp/actions/runs/40761274247)
compiled and linked libultraship for both tvOS Simulator architectures. They
did not execute it. This separate simulator app adds that execution test.

The fixture uses the pinned SDL UIKit bootstrap, libultraship resource manager,
Prism shader generator, and `GfxRenderingAPIMetal`. It packages only the pinned
open-source Metal template and its license into a small O2R archive. There is
no ROM, extracted game data, Torch invocation, or replacement renderer.

## What it checks

Each process creates and destroys three renderer instances. They draw red,
green, and blue triangles in turn, with two frames per instance for the
backend's deferred screen readback. The fixture waits for the actual frame
command buffer to complete successfully, checks five interior pixels and four
cleared exterior pixels, and records the RGBA5551 samples. Changing the color
rejects a stale frame. The host repeats the test in a fresh process, using a
unique run ID so an old report cannot count as a new pass.

The lifecycle patch initializes Metal pointer members, drains queues before
destruction, releases owned resources, and leaves SDL's borrowed drawable
texture alone. It also checks missing drawables, shader compilation errors,
and failed or resized readbacks. SDL's final surface stays visible after the
last backend is destroyed so the host can save a simulator screenshot.

The script enables Metal API validation **before** device creation. Drawables
have `framebufferOnly` disabled specifically for this readback test. Production
rendering should keep it enabled when readback is unnecessary. Presentation
uses the existing command-buffer `presentDrawable`/`commit` path; it does not
use tvOS-unavailable presentation callbacks or mix in Metal 4 queue APIs.

The first execution attempt reached Metal but API validation rejected upstream's
depth-clamp request (`Depth Clip Mode is not supported on this device`). tvOS
Simulator therefore retains Metal's [default depth clipping](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setdepthclipmode(_:)).
The fixture's vertices have depth 0.5, inside the clip range. This fallback does
not establish equivalent game rendering near the near/far planes; that needs a
separate fidelity test and GPU trace review when the game is integrated. The
non-simulator upstream clamp path remains unchanged and untested here.

GPU completion and pixel readback are automated evidence. Screenshots are
saved for visual review, not treated as proof of a presentation timestamp.
This does not exercise the game loop, display-list interpretation, textures,
controller input, audio, saves, SwiftUI hosting, or physical Apple TV hardware.
Repeated teardown is a functional test, not a memory-profile or leak-free claim.

## Run on a Mac

Use the pinned checkout setup in [the build instructions](SHIPWRIGHT_METAL_BUILD.md).
With Xcode and an installed tvOS Simulator runtime:

```sh
probe_arch=$(uname -m)
bash scripts/check-shipwright-metal.sh "$probe_arch" build/upstream/libultraship
probe_build="build/shipwright-metal/simulator-$probe_arch"
IFS= read -r probe_app < "$probe_build/render-probe-path.txt"
python3 scripts/run-shipwright-render-probe.py "$probe_app" \
    --output "$probe_build/render-evidence" --keep-simulator
```

`--keep-simulator` leaves the created simulator and final frame available for
inspection in Simulator.app. Omit it for automatic cleanup. The script only
removes the simulator it created, never an existing user simulator.

Exit **0** means both launches passed; **1** means a test/build-environment
failure; **77** means the required runtime or GPU is unavailable. Reports,
app logs, environment details, and screenshots are written under
`render-evidence`. A missing GPU is reported before renderer initialization.

## CI evidence

The [workflow](../.github/workflows/shipwright-metal.yml) compiles both simulator
architectures, including the app, and executes the architecture matching the
runner. It saves reports, logs, and screenshots as `shipwright-render-*` artifacts.
An explicitly reported `unavailable` result may leave the compilation gate
green in hosted CI; **it is never a GPU-rendering pass**. Rendering failures,
crashes, stale reports, missing lifecycle evidence, and timeouts fail the job.
Read the renderer-result step and `render-evidence/result.json`, not just the
workflow's overall green check. Local runs are strict by default.

Nine host tests cover evidence classification, rejection of stale or incomplete
reports, and deterministic packaging of only the allowed shader/license files.
These tests are separate from GPU execution. No real ROM is needed for this stage.
