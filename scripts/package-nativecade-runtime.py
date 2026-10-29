"""Package locally built framework slices. Never include game ROMs or derived ROM assets."""
from pathlib import Path
import plistlib
import shutil

root = Path(__file__).resolve().parent.parent
build = root / "build/nativecade-runtime"
output = build / "NativecadeRuntime.xcframework"
output.mkdir(parents=True, exist_ok=True)
libraries = []
for sdk, identifier in (("appletvos", "tvos-arm64"), ("appletvsimulator", "tvos-arm64-simulator")):
    source = build / sdk / "NativecadeRuntime.framework"
    if not (source / "NativecadeRuntime").is_file():
        continue
    destination = output / identifier / source.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)
    headers = destination / "Headers"
    headers.mkdir(exist_ok=True)
    shutil.copy2(root / "experiments/shipwright/simulator-game/NativecadeRuntime.h", headers)
    shutil.copy2(root / "RecompTV/PrivacyInfo.xcprivacy", destination)
    modules = destination / "Modules"
    modules.mkdir(exist_ok=True)
    (modules / "module.modulemap").write_text('framework module NativecadeRuntime {\n  umbrella header "NativecadeRuntime.h"\n  export *\n}\n')
    info_path = destination / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleName="NativecadeRuntime", CFBundleDevelopmentRegion="en",
                CFBundleSupportedPlatforms=["AppleTVOS" if sdk == "appletvos" else "AppleTVSimulator"],
                MinimumOSVersion="17.0")
    info_path.write_bytes(plistlib.dumps(info))
    entry = dict(LibraryIdentifier=identifier, LibraryPath=source.name,
                 SupportedArchitectures=["arm64"], SupportedPlatform="tvos")
    if sdk == "appletvsimulator":
        entry["SupportedPlatformVariant"] = "simulator"
    symbols = build / sdk / "NativecadeRuntime.framework.dSYM"
    if symbols.exists():
        symbol_destination = output / identifier / "dSYMs" / symbols.name
        if symbol_destination.exists():
            shutil.rmtree(symbol_destination)
        shutil.copytree(symbols, symbol_destination)
        entry["DebugSymbolsPath"] = "dSYMs"
    libraries.append(entry)
if not libraries:
    raise SystemExit("Build at least one native runtime slice first.")
(output / "Info.plist").write_bytes(plistlib.dumps(dict(CFBundlePackageType="XFWK",
    XCFrameworkFormatVersion="1.0", AvailableLibraries=libraries)))
print(f"Packaged {len(libraries)} runtime slices: {output}")
