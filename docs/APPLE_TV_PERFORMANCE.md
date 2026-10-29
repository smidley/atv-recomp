# Apple TV performance defaults

The simulator game now has Apple TV presets in **Settings > Graphics**. These
are starting points for device testing, not a claim of sustained performance on
any Apple TV model. The default targets the Apple TV 4K family; Apple TV HD has
not been qualified. Builds and validation remain simulator-only.

| Preset | Internal render resolution | Render target | Intended use |
| --- | --- | --- | --- |
| Performance (new-install default) | 720 pixels high | 60 FPS | Prioritize smooth motion and leave GPU headroom |
| Sharper | 1080 pixels high | 60 FPS | More image detail when the hardware has headroom |
| Low load | 720 pixels high | 30 FPS | Reduce CPU and GPU work when 60 FPS is unstable |

All presets enable VSync, disable matching arbitrary display refresh rates,
disable MSAA and supersampling, and use hardware bilinear texture filtering.
The fixed internal resolution avoids automatically rendering the game at 4K
just because it is attached to a 4K TV. Output and interface resolution remain
controlled by the platform. Aspect-ratio choices are retained. Frame interpolation
changes rendered motion, not the original game's logic rate.
Render targets are capped at 60 FPS and at the display's reported refresh rate;
for example, the 60 FPS preset targets 50 FPS on a 50 Hz display. The graphics
slider also stops at 60 FPS in the Apple TV build.

The existing individual graphics controls remain available. Presets only change
graphics settings; saves, controller bindings, audio, and gameplay options are
preserved. Existing custom graphics configurations are left intact on first
launch. Selecting a preset explicitly replaces its graphics options. Subsequent
launches preserve manual changes rather than reapplying the preset.

## Renderer changes

- Compile a shader's currently needed MSAA pipeline variant, and cache additional
  variants only if they are used. The previous renderer compiled every supported
  sample count the first time a shader appeared, even with MSAA disabled.
- Create the depth-query compute pipeline once and reuse it across frames.
- Release cached pipeline variants and their descriptor when a shader is evicted.
- Use the game's configured MSAA key consistently in the Metal backend.
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

Run `bash scripts/test-shipwright-performance.sh` for settings-preservation and
migration checks. Build the game using `scripts/check-shipwright-game.sh` as
described in `SHIPWRIGHT_SIMULATOR_GAME.md`.

For a development run, set `RECOMPTV_PERF_LOG=1` in the app's launch environment.
The game logs average, 95th-percentile, and maximum CPU frame-delivery intervals,
plus intervals over 100 ms, once every 300 rendered frames. It also logs shader
creation times. Logging is disabled by default and sends no telemetry. These
intervals include game work and frame limiting; they are not GPU timestamps or
proof of physical display delivery. A target change starts a new sample window.
Gaps over two seconds are logged separately as a possible stall or suspension,
then start a new window so a suspension does not contaminate the next sample.

Before changing defaults for actual devices, profile Release builds on each
supported Apple TV generation. Compare the same save, route, camera movement,
and display mode in Kokiri Forest, Hyrule Field, busy interiors, combat, pause
screens, and scene transitions. Include first-use and repeat visits, and a
sustained session long enough to expose thermal behavior. Record frame-time
percentiles, long stalls, GPU time, memory use, and audio interruptions.

Apple recommends using the Metal performance tools to identify the cause of
glitches and tune settings across devices:

- [Improving your game's graphics performance and settings](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings)
- [Analyzing the performance of your Metal app](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app)
- [Developing Metal apps that run in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator)

Simulator measurements validate behavior on the development Mac; they do not
predict Apple TV GPU throughput, thermal limits, or sustained frame rate.

## Local validation, 2026-10-28

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
