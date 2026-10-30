"""Ad-hoc sign only the standalone tvOS Simulator game, with its own Keychain group."""
from pathlib import Path
import plistlib
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 scripts/sign-shipwright-simulator.py PATH_TO_APP")
app = Path(sys.argv[1]).resolve(strict=True)
info = plistlib.loads((app / "Info.plist").read_bytes())
bundle = "com.smidley.RecompTVShipwrightExperiment"
if (info.get("CFBundleIdentifier") != bundle or
        info.get("CFBundleExecutable") != "RecompTVShipwright" or
        info.get("CFBundleSupportedPlatforms") != ["AppleTVSimulator"]):
    raise SystemExit("Only the standalone Apple TV Simulator game can be signed by this helper")
load_commands = subprocess.check_output(["otool", "-l", str(app / "RecompTVShipwright")], text=True)
platforms = [line.split()[-1] for line in load_commands.splitlines() if line.strip().startswith("platform ")]
if not platforms or any(platform not in ("8", "TVOSSIMULATOR") for platform in platforms):
    raise SystemExit("The executable is not a tvOS Simulator build")
if "sectname __entitlements" not in load_commands or "sectname __ents_der" not in load_commands:
    raise SystemExit("Build with CMake's simulator Keychain entitlement sections before signing")
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
signed = subprocess.check_output(["codesign", "--display", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL)
if signed.strip():
    raise SystemExit("Simulator entitlements must be embedded in Mach-O, not the host signature")
print("Signed the simulator game with its private Keychain group.")
