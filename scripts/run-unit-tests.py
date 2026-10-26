#!/usr/bin/env python3
"""Run the WhoGaveWhatTests unit suite on an iOS Simulator and check the built app's resources."""
import argparse
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location("simulator_tools", Path(__file__).with_name("simulator_tools.py"))
tools = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tools)

ROOT = Path(__file__).resolve().parents[1]
UNIT_TEST_TARGET = "WhoGaveWhatTests"
TEST_TIMEOUT_SECONDS = 1800
# Only this invocation's outputs are cleared, so unrelated files in the directory survive.
GENERATED_OUTPUTS = ("Tests.xcresult", "DerivedData", "metadata.json")


def clear_previous_outputs(directory):
    for name in GENERATED_OUTPUTS:
        path = directory / name
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    for log in directory.glob("*.log"):
        log.unlink()


def verify_built_app_names(directory, metadata):
    """Check the compiled resources, not only the source strings and build settings."""
    bundle = directory / "DerivedData/Build/Products/Debug-iphonesimulator/WhoGaveWhat.app"
    names = {}
    for language, expected in (("en", "Who Gave"), ("ru", "кто че")):
        output = tools.run_command(directory, f"bundle-names-{language}", [
            "plutil", "-convert", "xml1", "-o", "-", str(bundle / f"{language}.lproj/InfoPlist.strings")], 30)
        info = plistlib.loads(output.stdout.encode())
        if any(info.get(key) != expected for key in ("CFBundleDisplayName", "CFBundleName")):
            raise ValueError(f"Built {language} app names do not match {expected!r}")
        names[language] = expected
        output = tools.run_command(directory, f"bundle-spotlight-name-{language}", [
            "plutil", "-convert", "xml1", "-o", "-", str(bundle / f"{language}.lproj/Localizable.strings")], 30)
        if plistlib.loads(output.stdout.encode()).get("app-discovery.display-name") != "Who Gave · кто че":
            raise ValueError(f"Built {language} Spotlight display name does not preserve both public names")
    output = tools.run_command(directory, "bundle-info", [
        "plutil", "-convert", "xml1", "-o", "-", str(bundle / "Info.plist")], 30)
    if plistlib.loads(output.stdout.encode()).get("NSUserActivityTypes") != ["com.apple.corespotlightitem"]:
        raise ValueError("Built app does not declare its Spotlight activity type")
    metadata["bundle_names"] = names


def run(directory, runtime=None, device_name=None, fresh_ci_simulator=False):
    """Build and run the unit tests, then verify the built app's names and String Catalog."""
    if fresh_ci_simulator and (os.environ.get("GITHUB_ACTIONS") != "true" or runtime is None):
        raise ValueError("Fresh CI Simulator requires GitHub Actions and an explicit --runtime")
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    clear_previous_outputs(directory)
    head_sha = os.environ.get("HEAD_SHA") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True, cwd=ROOT).strip()
    metadata = {
        "head_sha": head_sha, "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"),
        "requested_runtime": runtime, "requested_device": device_name,
        "native_test": f"{UNIT_TEST_TARGET} only", "outcome": "failure",
    }
    result_bundle = directory / "Tests.xcresult"
    try:
        listing = tools.run_command(directory, "simulator-list", [
            "xcrun", "simctl", "list", "devices", "available", "--json"], 30)
        payload = json.loads(listing.stdout)
        if fresh_ci_simulator:
            simulator = tools.create_ci_simulator(directory, payload, runtime, metadata,
                                                  device_name or tools.DEFAULT_DEVICE)
        else:
            simulator = tools.select_simulator(payload, requested_runtime=runtime, device_name=device_name)
        simulator_id = simulator["udid"]
        metadata.update(device=simulator["name"], simulator_id=simulator_id, runtime=simulator["runtime"])
        if simulator.get("state") != "Booted":
            tools.run_command(directory, "simulator-boot", ["xcrun", "simctl", "boot", simulator_id], 60)
        tools.run_command(directory, "simulator-bootstatus", ["xcrun", "simctl", "bootstatus", simulator_id, "-b"],
                          tools.COLD_BOOT_TIMEOUT_SECONDS)
        # The UI test target still builds, so the store screenshot test cannot rot, but only the
        # unit suite runs: XCUITest journeys hang on Simulator keyboard and animation stalls.
        # Default diagnostics collection (sysdiagnose) can outlive the tests and lose the result bundle.
        tools.run_command(directory, "xcodebuild-test", [
            "xcodebuild", "test", "-project", "WhoGaveWhat.xcodeproj", "-scheme", "WhoGaveWhat",
            "-destination", f"platform=iOS Simulator,id={simulator_id}",
            "-derivedDataPath", str(directory / "DerivedData"), "-parallel-testing-enabled", "NO",
            "-resultBundlePath", str(result_bundle), "-collect-test-diagnostics", "never",
            f"-only-testing:{UNIT_TEST_TARGET}", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"],
            TEST_TIMEOUT_SECONDS, cwd=ROOT)
        verify_built_app_names(directory, metadata)
        tools.run_command(directory, "localization-check", [
            sys.executable, str(ROOT / "scripts/sync-localizations.py"), "--derived-data",
            str(directory / "DerivedData"), "--check"], 60, cwd=ROOT)
        metadata["outcome"] = "success"
    except (tools.NativeCommandError, OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError,
            plistlib.InvalidFileException) as error:
        metadata["error"] = str(error)
        raise
    finally:
        try:
            tools.cleanup_ci_simulator(directory, metadata)
        finally:
            try:
                (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
            finally:
                shutil.rmtree(directory / "DerivedData", ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Output directory for logs, metadata.json and Tests.xcresult")
    parser.add_argument("--runtime", help="Require a canonical runtime such as 'iOS 27.1'; reject conflicting booted iPhones")
    parser.add_argument("--device", help=f"Simulator model to reuse or create (default: a booted iPhone, else {tools.DEFAULT_DEVICE})")
    parser.add_argument("--fresh-ci-simulator", action="store_true",
                        help="On GitHub Actions, create a disposable Simulator of the model and delete it afterwards")
    args = parser.parse_args()
    run(args.directory, args.runtime, args.device, args.fresh_ci_simulator)


if __name__ == "__main__":
    main()
