"""Package locally built frameworks. Never include ROMs or derived ROM assets."""
from pathlib import Path
import plistlib
import shutil

root = Path(__file__).resolve().parent.parent
build = root / "build/nativecade-runtime"
frameworks = (
    ("NativecadeRuntime", Path("."), "experiments/shipwright/simulator-game/NativecadeRuntime.h"),
    ("NativecadeSpaghetti", Path("spaghettikart"), "experiments/spaghettikart/SpaghettiRuntime.h"),
)
for name, folder, header in frameworks:
    output = build / f"{name}.xcframework"
    output.mkdir(parents=True, exist_ok=True)
    libraries = []
    for sdk, identifier in (("appletvos", "tvos-arm64"), ("appletvsimulator", "tvos-arm64-simulator")):
        source = build / sdk / folder / f"{name}.framework"
        if not (source / name).is_file():
            continue
        destination = output / identifier / source.name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination, symlinks=True)
        headers = destination / "Headers"
        headers.mkdir(exist_ok=True)
        shutil.copy2(root / header, headers)
        shutil.copy2(root / "RecompTV/PrivacyInfo.xcprivacy", destination)
        modules = destination / "Modules"
        modules.mkdir(exist_ok=True)
        (modules / "module.modulemap").write_text(
            f'framework module {name} {{\n  umbrella header "{Path(header).name}"\n  export *\n}}\n')
        info_path = destination / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info.update(CFBundleName=name, CFBundleDevelopmentRegion="en",
                    CFBundleSupportedPlatforms=["AppleTVOS" if sdk == "appletvos" else "AppleTVSimulator"],
                    MinimumOSVersion="17.0")
        info_path.write_bytes(plistlib.dumps(info))
        entry = dict(LibraryIdentifier=identifier, LibraryPath=source.name,
                     SupportedArchitectures=["arm64"], SupportedPlatform="tvos")
        if sdk == "appletvsimulator":
            entry["SupportedPlatformVariant"] = "simulator"
        symbols = source.with_suffix(".framework.dSYM")
        if symbols.exists():
            symbol_destination = output / identifier / "dSYMs" / symbols.name
            if symbol_destination.exists():
                shutil.rmtree(symbol_destination)
            shutil.copytree(symbols, symbol_destination)
            entry["DebugSymbolsPath"] = "dSYMs"
        libraries.append(entry)
    if not libraries:
        raise SystemExit(f"Build at least one {name} slice first.")
    (output / "Info.plist").write_bytes(plistlib.dumps(dict(CFBundlePackageType="XFWK",
        XCFrameworkFormatVersion="1.0", AvailableLibraries=libraries)))
    print(f"Packaged {len(libraries)} slices: {output}")
