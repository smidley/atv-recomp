# Apple TV performance defaults

The simulator game now has Apple TV presets in **Settings > Graphics**. These
are starting points for device testing, not a claim of sustained performance on
any Apple TV model. The target is **Apple TV 4K, 3rd generation (A15)**, aiming
for 4K rendering at 60 FPS. Earlier generations and Apple TV HD have not been
qualified. Builds and validation remain simulator-only.

| Preset | Internal render resolution | Render target | Intended use |
| --- | --- | --- | --- |
| Automatic (new-install default) | Display resolution, up to 2160 pixels high; adapts down to 720 | 60 FPS | Start with the most visible detail and protect frame rate under sustained GPU load |
| 4K | 2160 pixels high | 60 FPS | Fixed maximum detail; can supersample a lower-resolution output |
| 1080p | 1080 pixels high | 60 FPS | Fixed Full HD rendering |
| 720p | 720 pixels high | 60 FPS | Fixed lower graphics load |
| Low load | 720 pixels high | 30 FPS | Reduce CPU and GPU work when 60 FPS is unstable |

All presets enable VSync, disable matching arbitrary display refresh rates,
disable MSAA and the extra resolution multiplier, and use hardware bilinear
texture filtering. This leaves the graphics budget for resolution and frame rate.
Automatic starts at the Metal output's actual pixel height, capped at 2160. It
does not limit a 4K output to 720p or 1080p. Output and interface resolution remain
controlled by the platform; rendering internally at 4K does not turn a 1080p
output into a 4K output. Aspect-ratio choices are retained. Frame interpolation
changes rendered motion, not the original game's logic rate.
Render targets are capped at 60 FPS and at the display's reported refresh rate;
for example, the 60 FPS preset targets 50 FPS on a 50 Hz display. The graphics
slider also stops at 60 FPS in the Apple TV build.

The existing individual graphics controls remain available. Presets only change
graphics settings; saves, controller bindings, audio, and gameplay options are
preserved. Existing custom graphics configurations are left intact on first
launch. Selecting a preset explicitly replaces its graphics options. Subsequent
launches preserve manual changes rather than reapplying the preset. Existing
720p configurations are not silently upgraded. Select **Automatic: up to 4K /
60 FPS** to opt into the new behavior. Manual resolution edits turn Automatic
off; selecting a fixed preset also turns it off.

## Automatic resolution

The controller uses completed Metal command buffers' GPU execution timestamps,
not the CPU frame interval. CPU loading stalls and timer delays therefore do not
make an otherwise fast scene blurry. It sums GPU durations for the frame's
rendering, depth queries, and readbacks. Polling occurs on the render thread,
without a completion callback or an added GPU wait. At most four frames of
timing buffers are retained; completed buffers are released before acquiring the
next drawable. Invalid or unavailable timestamps leave the resolution unchanged.

The available heights are 2160, 1800, 1440, 1080, and 720, limited by the actual
output height. The controller lowers one step when at least 45 of 60 samples use
more than 90% of the frame budget for two consecutive windows. It raises one
step after four windows whose 90th-percentile GPU time predicts the next size
will fit within 70% of the budget. A 60-sample cooldown follows startup and each
change. This leaves room for load variation and avoids reacting to isolated
hitches. Samples from the previous resolution are ignored.

Each new Automatic session starts at the output's maximum again. Resolution
adjustments stay in memory; they do not save settings to disk every frame. Other
settings saves may persist the current height, which Automatic reevaluates on
the next launch. If timestamps are unavailable, Automatic retains maximum
resolution and the fixed presets remain available. These thresholds are
starting values for physical-device profiling, not a hardware qualification.

## Renderer changes

- Compile a shader's currently needed MSAA pipeline variant, and cache additional
  variants only if they are used. The previous renderer compiled every supported
  sample count the first time a shader appeared, even with MSAA disabled.
- Create the depth-query compute pipeline once and reuse it across frames.
- Release cached pipeline variants and their descriptor when a shader is evicted.
- Preserve the shader cache when switching presets with the same texture filter.
  Changing only resolution or frame rate does not require recompilation.
- Use the game's configured MSAA key consistently in the Metal backend.
- Keep tvOS frame deadlines on an absolute cadence across small timer wake-up
  delays. Previously, delays over one millisecond could accumulate and lower the
  average frame rate. Long stalls reset the cadence without catch-up bursts.
- Skip redundant OpenGL swap and swap-interval calls in the tvOS Metal loop.
  Metal has already submitted presentation; the OpenGL call was setting an SDL
  error each frame.
- Leave the default depth-clipping behavior on Simulator and GPU families that
  lack depth-clamp control, instead of issuing an unsupported Metal command.
- Clear stale CMake CVar-name cache entries before configuring the game. The
  standalone Metal experiment uses generic names, while Shipwright uses names
  under `gSettings`. A one-time migration copies old values, including nested
  controller bindings, without replacing an existing value under the newer name.

These changes remove avoidable work. First-use shader compilation, loading a new
area, synchronous depth queries, host scheduling, and simulator overhead can
still cause a pause. Frame timings are needed to distinguish these causes.

## Reproduce and measure

Run `bash scripts/test-shipwright-performance.sh` for settings preservation,
migration, resolution adaptation, and timer-cadence checks. The **Shipwright
performance policy** workflow runs these without a ROM or Apple SDK. Build the
game using `scripts/check-shipwright-game.sh` as described in
`SHIPWRIGHT_SIMULATOR_GAME.md`.

For a development run, set `RECOMPTV_PERF_LOG=1` in the app's launch environment.
The game logs average, 95th-percentile, and maximum CPU frame-delivery intervals,
plus intervals over 100 ms, once every 300 rendered frames. It also logs the
internal render size, actual output size, latest available GPU execution time,
automatic resolution changes, and shader creation times. Logging is disabled by
default and sends no telemetry. The CPU intervals include game work and frame
limiting; they are not GPU timestamps or
proof of physical display delivery. A target change starts a new sample window.
Gaps over two seconds are logged separately as a possible stall or suspension,
then start a new window so a suspension does not contaminate the next sample.

Before qualifying the A15 target, profile Release builds on the physical Apple
TV 4K (3rd generation). Compare the same save, route, camera movement,
and display mode in Kokiri Forest, Hyrule Field, busy interiors, combat, pause
screens, and scene transitions. Include first-use and repeat visits, and a
sustained session long enough to expose thermal behavior. Record frame-time
percentiles, long stalls, GPU time, memory use, and audio interruptions.

Apple recommends using the Metal performance tools to identify the cause of
glitches and tune settings across devices:

- [Improving your game's graphics performance and settings](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings)
- [Analyzing the performance of your Metal app](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app)
- [Developing Metal apps that run in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator)
- [Metal command-buffer GPU execution timestamps](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime)

Simulator measurements validate behavior on the development Mac; they do not
predict Apple TV GPU throughput, thermal limits, or sustained frame rate.

## 4K and Automatic validation, 2026-10-28

- The Release arm64 simulator build passed. Policy tests cover sustained GPU
  overload, recovery to maximum detail, isolated spikes, stale/invalid timings,
  display limits, manual configurations, and timer drift.
- Metal API validation rendered 4,800 frames in Automatic and 4,500 frames at
  fixed 4K without a validation assertion or error. GPU timestamps were available.
- This simulator exposes a 1920×1080 output. Automatic correctly chose 1080p;
  fixed 4K rendered at 3840×2160 and scaled down to that output. This is not a
  physical 4K-display test. Automatic overload/recovery was tested with synthetic
  GPU timing sequences; the simulator did not need to lower resolution.
- A 3,000-frame 4K title/opening sample with API validation disabled averaged
  16.95 ms between rendered frames (about 59 FPS), with a worst per-window 95th
  percentile of 17.58 ms. It included three intervals over 100 ms and a 282.50 ms
  maximum. Most five-second windows averaged close to the 16.67 ms target.
- A separate 3,000-frame Automatic sample, also with validation disabled,
  averaged 16.85 ms, with a worst per-window 95th percentile of 17.65 ms,
  one interval over 100 ms, and a 330.93 ms maximum. These sequential samples
  have different shader-cache histories and are not a controlled A/B benchmark.
- A longer diagnostic run caught a first-use shader creation taking 954.46 ms.
  Pipeline caching reduces repeated work, but first-use shader compilation still
  happens on the render thread. Shader prewarming/background compilation remains
  further work; these changes do not eliminate all hitches.
- Controller mappings and all three saved-game files remained unchanged.

The development Mac remained locked, so interactive preset switching and actual
gameplay routes still need a manual pass. A15 throughput, real 4K output, and
thermal behavior remain unmeasured. No physical device was accessed.

## Earlier 720p validation, 2026-10-28

- The Release arm64 tvOS Simulator game built and launched successfully.
- Settings tests passed for defaults, each preset, display-rate limits, custom
  graphics settings, legacy key migration, and preserving controller mappings.
- The existing controller mappings and all three save files were preserved
  through installation and migration.
- Metal API validation rendered 2,400 frames with MSAA off and 4,200 frames with
  2x MSAA without a validation assertion or error. The first validation run
  exposed the simulator's unsupported depth-clamp command; the capability guard
  was added before these successful runs.
- Both normal-run samples below use the 720p/60 FPS preset and the opening/title
  sequence, with API validation disabled. Each covers 3,000 recorded frames.

| CPU delivery interval | Before renderer changes | Updated build |
| --- | --- | --- |
| Mean | 18.63 ms | 18.10 ms |
| Worst per-window 95th percentile | 17.70 ms | 18.70 ms |
| Maximum | 817.36 ms | 43.22 ms |
| Intervals longer than 100 ms | 17 | 0 |

These are sequential observations with different shader-cache warm-up histories,
not a controlled cold-cache performance comparison. They confirm the reported
stall can occur and that it did not recur in this short repeat sample; they do
not establish the improvement attributable to each change. The updated mean
corresponds to about 55 rendered frames per second in this simulator run, so a
sustained 60 FPS claim is not warranted. The menu and live preset switching still
need an interactive check because the development Mac was locked.
