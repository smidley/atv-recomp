"""Run a bounded, ROM-free libultraship pixel fixture in a fresh tvOS Simulator.

Exit 0: verified. Exit 1: failure. Exit 77: unavailable environment.
CI may explicitly allow 77, but the report/output still says 'unavailable'.
"""

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import uuid

BUNDLE = "com.smidley.RecompTV.ShipwrightProbe"


def validate_report(report, run_id):
    if report.get("schema_version") != 1 or report.get("run_id") != run_id:
        raise ValueError("Stale or invalid renderer report")
    status = report.get("status")
    if status not in ("running", "passed", "failed", "unavailable"):
        raise ValueError("Unknown renderer result")
    if status == "passed":
        expected = {"completed_frames": 6, "verified_cycles": 3, "destroyed_renderers": 3}
        if any(type(report.get(k)) is not int or report[k] != v for k, v in expected.items()):
            raise ValueError("Incomplete renderer lifecycle evidence")
        if not report.get("metal_device") or not all(type(report.get(k)) is int and 0 < report[k] <= 4096 for k in ("width", "height")):
            raise ValueError("Missing Metal device or drawable evidence")
        samples = report.get("rgba5551_samples")
        if not isinstance(samples, list) or len(samples) != 3:
            raise ValueError("Missing pixel samples for the three renderer lifecycles")
        for values, color in zip(samples, (0xF801, 0x07C1, 0x003F)):
            # The clear must be black; its alpha is not part of this screen test.
            if not isinstance(values, list) or len(values) != 9 or values[:5] != [color] * 5 or any(v not in (0, 1) for v in values[5:]):
                raise ValueError("Recorded triangle/clear pixels do not match the expected frame")
    return status


def run_probe(app, output, keep_simulator=False):
    output.mkdir(parents=True, exist_ok=True)
    logs = output / "host-commands.log"
    simulator = None

    def command(*args, timeout=90, check=True, env=None):
        result = subprocess.run(args, text=True, capture_output=True, timeout=timeout, env=env)
        with logs.open("a") as log:
            log.write("$ " + " ".join(map(str, args)) + "\n" + result.stdout + result.stderr + "\n")
        if check and result.returncode:
            raise RuntimeError(f"{' '.join(map(str, args[:4]))}: {result.stderr.strip() or result.stdout.strip()}")
        return result.stdout.strip()

    try:
        if platform.system() != "Darwin":
            return "unavailable", "macOS and an installed tvOS Simulator runtime are required"
        listing = json.loads(command("xcrun", "simctl", "list", "-j"))
        runtimes = [r for r in listing["runtimes"] if r.get("isAvailable") and "tvOS" in r["identifier"]]
        if not runtimes:
            return "unavailable", "No available tvOS Simulator runtime is installed"
        runtime = max(runtimes, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
        types = [d for d in listing["devicetypes"] if "Apple-TV" in d["identifier"] or "AppleTV" in d["identifier"]]
        if not types:
            return "unavailable", "No Apple TV simulator device type is installed"
        device = next((d for d in reversed(types) if "1080" in d["identifier"]), types[-1])
        (output / "environment.json").write_text(json.dumps({"host_architecture": platform.machine(), "runtime": runtime, "device_type": device}, indent=2))
        simulator = command("xcrun", "simctl", "create", "RecompTV-render-" + uuid.uuid4().hex[:8], device["identifier"], runtime["identifier"])
        command("xcrun", "simctl", "boot", simulator)
        command("xcrun", "simctl", "bootstatus", simulator, "-b", timeout=240)
        command("xcrun", "simctl", "install", simulator, str(app))
        container = Path(command("xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"))
        result_path = container / "Documents/shipwright-render-result.json"
        for attempt in (1, 2):
            run_id = uuid.uuid4().hex
            result_path.unlink(missing_ok=True)
            environment = os.environ.copy()
            environment.update(SIMCTL_CHILD_RECOMPTV_PROBE_RUN=run_id, SIMCTL_CHILD_MTL_DEBUG_LAYER="1")
            command("xcrun", "simctl", "launch", "--terminate-running-process",
                    "--stdout=" + str(output / f"launch-{attempt}.stdout.log"),
                    "--stderr=" + str(output / f"launch-{attempt}.stderr.log"),
                    simulator, BUNDLE, env=environment)
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                if result_path.is_file():
                    report = json.loads(result_path.read_text())
                    status = validate_report(report, run_id)
                    if status != "running":
                        shutil.copyfile(result_path, output / f"launch-{attempt}.json")
                        if status != "passed":
                            return status, report.get("detail", "No renderer diagnostic")
                        break
                time.sleep(1)
            else:
                raise RuntimeError("Renderer did not finish within 120 seconds; inspect the captured app logs")
            command("xcrun", "simctl", "io", simulator, "screenshot", str(output / f"launch-{attempt}.png"))
            if attempt != 2 or not keep_simulator:
                command("xcrun", "simctl", "terminate", simulator, BUNDLE)
        return "passed", "Two app launches, six renderer lifecycles, twelve GPU-completed frames, and pixel checks passed"
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
        return "failed", str(error)
    finally:
        if simulator and not keep_simulator:
            # Only the simulator created by this invocation may be removed.
            for action in ("shutdown", "delete"):
                try:
                    command("xcrun", "simctl", action, simulator, check=False)
                except (OSError, subprocess.TimeoutExpired) as error:
                    print(f"warning: Could not {action} probe simulator {simulator}: {error}", file=sys.stderr)
        elif simulator:
            print("Kept probe simulator: " + simulator)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--allow-unavailable", action="store_true", help="CI only: report unavailable explicitly without failing the compilation gate")
    parser.add_argument("--keep-simulator", action="store_true", help="Keep this invocation's simulator and final frame for manual inspection")
    args = parser.parse_args()
    if not args.app.is_dir() or args.app.suffix != ".app":
        parser.error("app must be the built simulator .app bundle")
    output = args.output.resolve()
    status, detail = run_probe(args.app.resolve(), output, args.keep_simulator)
    (output / "result.json").write_text(json.dumps({"status": status, "detail": detail}, indent=2) + "\n")
    print(f"Renderer result: {status}: {detail}", flush=True)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            stream.write("render_status=" + status + "\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(f"### Shipwright renderer: {status}\n\n{detail}\n\nA build or unavailable result is not GPU rendering evidence.\n")
    if status == "unavailable":
        print("::warning::" + detail)
        return 0 if args.allow_unavailable else 77
    if status != "passed":
        print("error: " + detail, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
