# RT64 Metal backend experiment

**Scope note:** [PR #3](https://github.com/smidley/atv-recomp/pull/3) merged after
[all RT64 checks passed at `a5e5525`](https://github.com/smidley/atv-recomp/actions/runs/40749764962).
The first game target is now [Shipwright](SHIPWRIGHT_PORT.md), which uses a
different renderer. Further RT64 integration is deferred; this experiment is
retained independently and is not linked into the app.

This continues the [runtime audit](RUNTIME_AUDIT.md) on the tvOS Simulator.
It builds RT64's actual Metal backend separately from its full renderer and the
Zelda runtime. The main RecompTV app remains the foundation harness.

The preceding core-services experiment passed for both simulator architectures
and its host input/audio tests at
[`94aa928`](https://github.com/smidley/atv-recomp/actions/runs/40743318116).
PR #2 was merged on 2026-10-28. Those results establish a starting point, not
graphics or game execution.

## Port boundary

The [reviewable patch](../experiments/rt64-metal/tvos.patch) is applied only to
copies under ignored `build/rt64-metal/source/`. Preparation verifies the clean
RT64 checkout and all three dependency commits against
[the audit baseline](../upstream/audit-baseline.json). The upstream checkout is
never patched in place.

| Change | Purpose |
| --- | --- |
| App-owned `WindowState` and `TVWindow` | Supply drawable pixel dimensions and observed refresh rate without AppKit, `NSWindow`, or SDL |
| Coherent, locked metric snapshots | Allow a future UI owner to update metrics while the render thread reads them |
| tvOS guards for desktop-only Metal paths | Avoid desktop vsync controls, managed-buffer notifications, device enumeration, and the desktop HDR-memory heuristic |
| Native Objective-C SDK contract | Check API availability directly; metal-cpp's dynamic selectors can otherwise hide unavailable methods |
| Separate native host-tool build | Run the pinned SPIRV-Cross converter on the Mac, not as a tvOS cross-compiled executable |
| Mobile MSL options and explicit simulator shader target | Generate shader libraries for the selected platform instead of reusing macOS output |

`RenderWindow.window` must point to a live `RecompTV::WindowState`;
`RenderWindow.view` must be the app-owned `CAMetalLayer`. The state must outlive
the swap chain. A future UIKit adapter will provide pixels, not points, and the
observed refresh rate. Zero dimensions mean an unavailable surface; zero refresh
rate means unknown. Values that cannot fit RT64's signed window attributes are
rejected. Fullscreen requests are left to the tvOS app host.

The patch preserves the upstream Mac2/Apple6 GPU-family gate and additionally
requires argument buffers tier 2 on tvOS. A simulator may fail that runtime
capability gate even when the source builds. No capability is fabricated to make
a simulator appear supported.

The experiment's tvOS path keeps system-managed vsync and uses an SDR preference.
It does not implement HDR, an uncapped presentation mode, or a new swap-chain
lifetime scheme. RT64's drawable ownership, semaphore ordering, and command
completion behavior still need execution tests before integration.

## Build and test

Requirements: Git, Python 3, CMake 3.20+, Make, and Xcode with the tvOS SDK and
Metal compiler installed. The portable window-state checks also run on Linux:

```sh
bash scripts/test-rt64-window.sh
```

From the repository root on a Mac, prepare the exact audited sources:

```sh
git clone --no-checkout https://github.com/rt64/rt64.git build/upstream/rt64
git -C build/upstream/rt64 checkout --detach 23cab603c4f9f4a8b369b38e036f1aa484603878
git -C build/upstream/rt64 submodule update --init --depth=1 src/contrib/xxHash src/contrib/spirv-cross src/contrib/dxc

bash scripts/check-rt64-metal.sh arm64 build/upstream/rt64
bash scripts/check-rt64-metal.sh x86_64 build/upstream/rt64
bash scripts/check-rt64-shaders.sh build/upstream/rt64
```

The DXC repository has moved from `rt64/dxc-bin` to `renderbag/dxc-bin`; the
audited commit is unchanged. The workflow uses the canonical location and
verifies the recorded gitlink revision. No floating release or branch is used.

The backend checks compile the full `rt64_metal.cpp` translation unit and link
its factory into a tvOS Simulator executable. Linking must resolve the backend's
symbols; no undefined-symbol bypass is enabled. `otool` checks that AppKit and
SDL did not enter the resulting framework dependencies. The executable is a link
fixture, not an installable simulator application, and the script does not run it.

The shader check builds RT64's SPIRV-Cross helper for the host, then processes
three unmodified upstream HLSL inputs through DXC, the mobile MSL converter, and
the tvOS Simulator Metal compiler:

- `FullScreenVS.hlsl`: fullscreen vertex stage.
- `TextureCopyPS.hlsl`: texture access and a push-constant block.
- `HistogramClearCS.hlsl`: writable buffer in a compute stage.

These are renderer sources, not game assets. Outputs stay under ignored
`build/rt64-metal/`; no ROM or generated game code is used or uploaded.

The [RT64 Metal workflow](../.github/workflows/rt64-metal.yml) reads the installed
tvOS SDK declarations and runs these checks. Use its result for the tested
commit; a workflow file alone is not evidence of a passing build.

## Evidence limits and next step

Successful compilation and linking do not demonstrate a rendered RT64 frame.
The shader subset does not cover all RT64 shaders, descriptor layouts, pixel
formats, resource residency, or real game rendering. The complete RT64 HLE
renderer, desktop inspection/dialog code, full `librecomp`, and game code are
outside this build.

The next execution experiment should instantiate the backend in a simulator app,
check the actual GPU capabilities, render a bounded offscreen fixture and inspect
its pixels, then exercise presentation, resizing, and teardown. Only after that
should it connect to the game runtime. Apple documents simulator-specific GPU
limits in [Developing Metal apps that run in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator).
Hardware validation remains deferred as requested.

The RT64 patch includes its [MIT license notice](../experiments/rt64-metal/UPSTREAM_LICENSE.txt).
The experiment also uses the separately pinned xxHash, DXC, and SPIRV-Cross
checkouts with their existing notices. This is not a completed distribution
license inventory or a change to the project's unselected license.
