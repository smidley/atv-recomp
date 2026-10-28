# Build and Run the Native Foundation

This checkpoint contains a SwiftUI tvOS app, a C++17 static library exposed through a C-compatible header, and an on-demand Metal clear/present pass. It does not contain a game runtime or require a ROM.

## Open in Xcode

1. Open **RecompTV.xcodeproj** at the repository root.
2. Select the shared **RecompTV** scheme.
3. Select an Apple TV simulator and Run. Install a tvOS simulator runtime in Xcode Settings if none is available.
4. Expect **C++ returned 42**, **Metal frame 1 completed**, and a teal frame.
5. Select **Change test color** with the remote. Expect a purple frame and **Metal frame 2 completed**. Further selections cycle through amber and teal.

The color comes from C++, crosses the C/Swift boundary, and becomes the Metal render-pass clear color. The status changes to completed only after the GPU command buffer completes successfully. The colored area is an MTKView, not a SwiftUI background pretending to be GPU output.

The checked-in project opens without installing a generator. XcodeGen 2.45.3 was used to generate it from project.yml. If changing target configuration, update the specification and regenerate with:

```sh
xcodegen generate
```

Commit both project.yml and the generated project changes. Do not commit personal Xcode settings, signing credentials, or build outputs.

## Command-line validation

Use Xcode with the tvOS SDK selected as the active developer directory. List available simulators with:

```sh
xcrun simctl list devices available
```

Build the simulator app without development signing:

```sh
xcodebuild -project RecompTV.xcodeproj -scheme RecompTV \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Run the UI smoke test, replacing SIMULATOR_UDID with an available Apple TV simulator's identifier:

```sh
xcodebuild -project RecompTV.xcodeproj -scheme RecompTV \
  -destination 'platform=tvOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/RecompTV-smoke.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

Choose a new result-bundle path for subsequent runs if that path already exists. The test checks the displayed C++ result, successful GPU completion, and a second frame after a remote Select press; it also attaches a screenshot.

Compile the ARM64 device build without signing:

```sh
xcodebuild -project RecompTV.xcodeproj -scheme RecompTV \
  -configuration Release -destination 'generic/platform=tvOS' \
  -derivedDataPath build/DeviceDerivedData CODE_SIGNING_ALLOWED=NO build
```

An unsigned device build cannot be installed as-is and does not prove physical-device operation.

## Run on a physical Apple TV

1. Pair an Apple TV with Xcode and enable its development features as requested by Xcode.
2. In the RecompTV target's **Signing & Capabilities**, select your development team. Use a unique bundle identifier if needed. No team is committed to this project.
3. Select that Apple TV as the run destination and Run with signing enabled.
4. Repeat the C++ result and three-color checks. Record hardware model/chipset, tvOS version, Xcode version, and observations in [POC.md](POC.md).

The deployment target is provisionally tvOS 17.0. It is a build setting, not a tested minimum OS or hardware claim. The current verification environment is recorded in POC.md.

## Source map

| Path | Purpose |
| --- | --- |
| RecompCore/RecompCore.cpp | C++ calculation and three-color palette |
| RecompCore/RecompCore.h | Small C ABI shared with Swift |
| RecompTV/RecompTV-Bridging-Header.h | Imports the native interface into Swift |
| RecompTV/ContentView.swift | Visible probe result and remote-operated color control |
| RecompTV/MetalSurface.swift | MTKView lifecycle, clear/present pass, GPU completion/error status |
| RecompTVUITests/RecompTVUITests.swift | Integration smoke test |
| project.yml | Reproducible Xcode project specification |

The app explicitly links libc++ because its C++ static library is consumed by a Swift target. No shader compiler, custom shaders, or third-party runtime dependencies are required for a clear-only frame.

Metal presentation follows Apple's [MTKView](https://developer.apple.com/documentation/metalkit/mtkview) and [command-buffer completion](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler(_:)) APIs, hosted through [UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable).
