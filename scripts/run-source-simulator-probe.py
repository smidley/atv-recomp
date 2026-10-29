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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
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
            raise RuntimeError("This runner only signs the RecompTV tvOS Simulator app")
        run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b")
        run("codesign", "--force", "--deep", "--sign", "-", str(args.app))
        # CODE_SIGNING_ALLOWED=NO omits Xcode's normal application-identifier claim.
        # Give this disposable simulator build its own default Keychain group. Do not
        # change the project, a user's signing team, or any device provisioning profile.
        test_app_id = "RECOMPTV01." + bundle
        entitlements = args.output / "simulator-entitlements.plist"
        entitlements.write_bytes(plistlib.dumps({
            "application-identifier": test_app_id,
            "keychain-access-groups": [test_app_id],
        }))
        run("codesign", "--force", "--sign", "-", "--entitlements", str(entitlements), str(args.app))
        # The colon strips the binary entitlement-blob header, leaving a parseable plist.
        signature = subprocess.check_output(["codesign", "--display", "--entitlements", ":-", str(args.app)])
        if plistlib.loads(signature).get("keychain-access-groups") != [test_app_id]:
            raise RuntimeError("The simulator app's Keychain entitlement was not signed")
        run("xcrun", "simctl", "install", udid, str(args.app))
        container = pathlib.Path(run("xcrun", "simctl", "get_app_container", udid, bundle, "data"))
        report_file = container / "Documents" / "source-probe.json"
        for launch in range(2):
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
        print("PASS: two tvOS app launches verified Keychain and HTTP/SMB transfers with synthetic ROM hashing.")
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
