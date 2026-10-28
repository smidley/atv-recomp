# Shipwright services and Metal simulator build

This experiment builds the complete pinned libultraship static library for tvOS
Simulator, then forces every library object through an executable link. The real
Metal backend and shader generator are included. It is the next build step for
[Shipwright](SHIPWRIGHT_PORT.md); the game itself and Torch are not linked yet.

The [patch](../experiments/shipwright/metal/tvos.patch) adds tvOS to libultraship's
existing mobile build path, removes the desktop OpenGL ImGui backend for tvOS,
and checks for a real Metal device instead of assuming one exists. The existing
libultraship `__IOS__` flag selects its shared mobile host code; the actual SDK
and compiler target remain tvOS Simulator. The iOS toolchain file is not used.

Scripting/TinyCC, dynamic native-library loading, MPQ archives and the graphics
disassembler are disabled. O2R/ZIP support, platform services, SDL2, ImGui, and
the actual Metal renderer remain in the build. SDL owns the experimental window
path; integration with the SwiftUI app host is still separate work. Mobile file
paths, controller behavior, audio, lifecycle, GPU execution, and saves are not
validated by this build.

## Reproduce

On a Mac with Xcode's tvOS SDK, Git, Python 3, CMake 3.24 or newer, and Make:

```sh
git clone --no-checkout https://github.com/kenix3/libultraship.git build/upstream/libultraship
git -C build/upstream/libultraship checkout --detach da6daf1a50a5e46d6641408d52227e31e85e46df
bash scripts/check-shipwright-metal.sh arm64 build/upstream/libultraship
bash scripts/check-shipwright-metal.sh x86_64 build/upstream/libultraship
```

Preparation checks the upstream commit and clean working tree, then patches
copies under ignored `build/shipwright-metal/source`. The upstream checkout is
left untouched. CMake builds each architecture in a separate directory and
fetches the dependencies named in
[libultraship-simulator.json](../upstream/libultraship-simulator.json).
Upstream tag references have been resolved to immutable commits; the fetched
checkouts are verified after linking. The existing stb download is checksum
verified. This is the selected build's dependency baseline, not a complete
Shipwright/Torch inventory.

The link fixture is not an installable game or a rendered-frame test. It checks
both complete symbol resolution and the Metal backend's presence, without
undefined-symbol bypasses. The script checks the Mach-O architecture, rejects
desktop/OpenGL frameworks, and checks that runtime scripting sources did not
enter the source list. Native Objective-C declarations also compile against the
tvOS SDK to check availability independently of metal-cpp's dynamic selectors.

## Evidence and next step

Use the [simulator workflow](../.github/workflows/shipwright-metal.yml) result
for the tested commit. A checked-in workflow or successful archive alone does
not establish a successful complete link.

After the build passes, exercise the renderer inside a simulator application,
verify pixels and repeated teardown, then add the game loop and the user's
validated assets. These steps must distinguish a missing simulator GPU from a
rendering defect. Physical Apple TV validation remains deferred.

The patch retains libultraship's [MIT notice](../experiments/shipwright/metal/UPSTREAM_LICENSE.txt).
Dependencies retain their own notices in the fetched source trees. No ROM or
extracted game asset is used or uploaded by this experiment.
