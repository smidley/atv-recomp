#!/usr/bin/env python3
"""Install and run the real app against loopback fixtures in a fresh tvOS Simulator."""
import argparse
import json
import os
import pathlib
import plistlib
import re
import subprocess
import time
import uuid


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


# Guided setup screens the app's fixture preview draws (--setup-fixture-step).
SETUP_STEPS = ["welcome", "connect", "detect", "platforms", "games", "results", "home", "settings", "box-faces", "shelf-facing", "shelf-spines"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--screens", help="comma-separated setup steps to screenshot, skipping the source probe")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    tvos = [r for r in runtimes if r.get("isAvailable") and "tvOS" in r["name"]]
    if not tvos:
        raise RuntimeError("No tvOS Simulator runtime is available")
    runtime = max(tvos, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
    types = json.loads(run("xcrun", "simctl", "list", "devicetypes", "--json"))["devicetypes"]
    device = next(d for d in types if d["name"] == "Apple TV 4K (3rd generation) (at 1080p)")
    udid = run("xcrun", "simctl", "create", "RecompTV Network " + str(uuid.uuid4()), device["identifier"], runtime["identifier"])
    bundle = "com.smidley.RecompTVHarness"
    try:
        with (args.app / "Info.plist").open("rb") as info_file:
            info = plistlib.load(info_file)
        if info.get("CFBundleIdentifier") != bundle or "AppleTVSimulator" not in info.get("CFBundleSupportedPlatforms", []):
            raise RuntimeError("This runner only installs the RecompTV tvOS Simulator app")
        run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b")
        # Install Xcode's Simulator signature unchanged. Its simulated application
        # identifier supplies the default Keychain group; re-signing that claim into
        # an ad hoc code signature stops the app from launching.
        run("xcrun", "simctl", "install", udid, str(args.app))
        container = pathlib.Path(run("xcrun", "simctl", "get_app_container", udid, bundle, "data"))
        report_file = container / "Documents" / "source-probe.json"
        for launch in range(0 if args.screens else 2):
            run_id = str(uuid.uuid4())
            env = dict(os.environ, SIMCTL_CHILD_RECOMPTV_PROBE_ID=run_id)
            output = run("xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle, "--source-fixture-probe", env=env)
            pid_match = re.search(r": (\d+)$", output)
            if not pid_match:
                raise RuntimeError("Simulator did not report the app process")
            pid = int(pid_match.group(1))
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                os.kill(pid, 0)
                if report_file.exists():
                    report = json.loads(report_file.read_text())
                    if report.get("run_id") == run_id:
                        (args.output / f"launch-{launch + 1}.json").write_text(json.dumps(report, indent=2))
                        if report.get("passed") is not True or report.get("steps") != ["keychain", "romm-artwork", "romm", "smb", "platform-batch"]:
                            raise RuntimeError("Source probe failed: " + str(report))
                        break
                time.sleep(0.25)
            else:
                raise RuntimeError("Timed out waiting for source probe output")
            run("xcrun", "simctl", "io", udid, "screenshot", str(args.output / f"library-{launch + 1}.png"))
            run("xcrun", "simctl", "terminate", udid, bundle)
        if not args.screens:
            print("PASS: two tvOS app launches verified Keychain and HTTP/SMB transfers with synthetic ROM hashing.")
        steps = args.screens.split(",") if args.screens else SETUP_STEPS
        for step in steps:
            # A launch right after the previous one ends can start behind the home screen.
            subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], check=False, capture_output=True)
            time.sleep(2)
            # Synthetic Ocarina records, three by default, so a scan shows a game that's already in the
            # library; NATIVECADE_PROBE_SYNTHETIC=50 fills a shelf.
            synthetic = os.environ.get("NATIVECADE_PROBE_SYNTHETIC", "3")
            env = dict(os.environ, SIMCTL_CHILD_NATIVECADE_SYNTHETIC_LIBRARY=synthetic)
            run("xcrun", "simctl", "launch", udid, bundle, "--setup-fixture-step", step, env=env)
            time.sleep(8)
            run("xcrun", "simctl", "io", udid, "screenshot", str(args.output / f"setup-{step}.png"))
        print(f"Saved {len(steps)} guided setup screenshots in {args.output}.")
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False, capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", udid], check=False, capture_output=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        summary = "Source simulator probe failed: " + str(error).replace("\n", " ")
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write("diagnostic=" + summary[:1000] + "\n")
        raise
