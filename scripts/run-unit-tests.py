#!/usr/bin/env python3
"""Run the WhoGaveWhatTests unit suite on an iOS Simulator and check the built app's resources.

The app is built before the Simulator boots: a freshly booted Simulator keeps the CPU busy for minutes, which more
than doubled the build on GitHub's three-core runners. `--app-archive` keeps the tested Debug app as a tarball (the
`simulator-app` artifact that scripts/simulator-app.sh downloads); `--source-packages` and `--compilation-cache` put
the Swift packages and Xcode's compilation cache outside DerivedData so CI can cache them between runs.
"""
import argparse
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

_spec = importlib.util.spec_from_file_location("simulator_tools", Path(__file__).with_name("simulator_tools.py"))
tools = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tools)

ROOT = Path(__file__).resolve().parents[1]
UNIT_TEST_TARGET = "WhoGaveWhatTests"
BUILD_TIMEOUT_SECONDS = 1200
TEST_TIMEOUT_SECONDS = 900
# Only this invocation's outputs are cleared, so unrelated files in the directory survive.
GENERATED_OUTPUTS = ("Tests.xcresult", "DerivedData", "metadata.json")
GENERATED_LOG_PREFIXES = ("simulator-", "xcodebuild-", "bundle-", "localization-check")
APP_RELATIVE_PATH = Path("DerivedData/Build/Products/Debug-iphonesimulator/WhoGaveWhat.app")
# Upper bound for Xcode's on-disk compilation cache; Xcode prunes it after the build. GitHub keeps 10 GB of caches per
# repository, so this leaves room for the Swift packages and a few branches.
COMPILATION_CACHE_LIMIT = "2G"


def clear_previous_outputs(directory):
    logs = [path for path in directory.glob("*.log") if path.name.startswith(GENERATED_LOG_PREFIXES)]
    for path in [directory / name for name in GENERATED_OUTPUTS] + logs:
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)


def verify_built_app_names(directory, metadata):
    """Check the compiled resources, not only the source strings and build settings."""
    bundle = directory / APP_RELATIVE_PATH
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


def archive_app(directory, archive):
    """Write the tested Debug app to `archive` as a gzipped tarball without the hosted test bundles.

    tar keeps the executable bits that upload-artifact drops. The archive holds `WhoGaveWhat.app` at its root.
    """
    bundle = directory / APP_RELATIVE_PATH
    if not bundle.is_dir():
        raise ValueError(f"No built app at {bundle}")
    archive.parent.mkdir(parents=True, exist_ok=True)

    def without_tests(info):
        parts = Path(info.name).parts
        if len(parts) >= 3 and parts[1] == "PlugIns" and parts[2].endswith((".xctest", ".xctest.dSYM")):
            return None
        return info

    with tarfile.open(archive, "w:gz") as output:
        output.add(bundle, arcname=bundle.name, filter=without_tests)


def build_settings(source_packages=None, compilation_cache=None):
    """xcodebuild arguments that move the Swift packages and the compilation cache to cacheable folders."""
    arguments = []
    if source_packages is not None:
        arguments += ["-clonedSourcePackagesDirPath", str(Path(source_packages).resolve())]
    if compilation_cache is not None:
        arguments += ["COMPILATION_CACHE_ENABLE_CACHING=YES",
                      f"COMPILATION_CACHE_CAS_PATH={Path(compilation_cache).resolve()}",
                      f"COMPILATION_CACHE_LIMIT_SIZE={COMPILATION_CACHE_LIMIT}"]
    return arguments


def run(directory, runtime=None, device_name=None, fresh_ci_simulator=False, app_archive=None,
        source_packages=None, compilation_cache=None):
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
        packages = build_settings(source_packages)
        target = ["-project", "WhoGaveWhat.xcodeproj", "-scheme", "WhoGaveWhat",
                  "-destination", f"platform=iOS Simulator,id={simulator_id}",
                  "-derivedDataPath", str(directory / "DerivedData"), "-parallel-testing-enabled", "NO", *packages]
        # Every asset scale and idiom stays in the app, so the archived app looks right on any Simulator model.
        signing = ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "ENABLE_ONLY_ACTIVE_RESOURCES=NO"]
        caching = build_settings(compilation_cache=compilation_cache)
        # Building the whole scheme keeps the UI test target (store screenshots) compiling, but only
        # the unit suite runs: XCUITest journeys hang on Simulator keyboard and animation stalls.
        tools.run_command(directory, "xcodebuild-build", [
            "xcodebuild", "build-for-testing", *target, *signing, *caching, "-showBuildTimingSummary"],
            BUILD_TIMEOUT_SECONDS, cwd=ROOT)
        # Booted only now: a booting Simulator competes with the compiler for the runner's few cores.
        if simulator.get("state") != "Booted":
            tools.run_command(directory, "simulator-boot", ["xcrun", "simctl", "boot", simulator_id], 60)
        tools.run_command(directory, "simulator-bootstatus", ["xcrun", "simctl", "bootstatus", simulator_id, "-b"],
                          tools.COLD_BOOT_TIMEOUT_SECONDS)
        # Default diagnostics collection (sysdiagnose) can outlive the tests and lose the result bundle.
        tools.run_command(directory, "xcodebuild-test", [
            "xcodebuild", "test-without-building", *target, "-resultBundlePath", str(result_bundle),
            "-collect-test-diagnostics", "never", f"-only-testing:{UNIT_TEST_TARGET}", *signing],
            TEST_TIMEOUT_SECONDS, cwd=ROOT)
        verify_built_app_names(directory, metadata)
        tools.run_command(directory, "localization-check", [
            sys.executable, str(ROOT / "scripts/sync-localizations.py"), "--derived-data",
            str(directory / "DerivedData"), "--check"], 60, cwd=ROOT)
        if app_archive is not None:
            archive_app(directory, Path(app_archive))
            metadata["app_archive"] = str(app_archive)
        metadata["outcome"] = "success"
    except (tools.NativeCommandError, OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError,
            tarfile.TarError) as error:
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
    parser.add_argument("--app-archive", type=Path, metavar="TAR_GZ",
                        help="After a passing run, write the tested Debug WhoGaveWhat.app to this .tar.gz")
    parser.add_argument("--source-packages", type=Path, metavar="DIR",
                        help="Folder for the resolved Swift packages (xcodebuild -clonedSourcePackagesDirPath)")
    parser.add_argument("--compilation-cache", type=Path, metavar="DIR",
                        help="Enable Xcode's compilation cache and keep it in this folder")
    args = parser.parse_args()
    run(args.directory, args.runtime, args.device, args.fresh_ci_simulator, args.app_archive,
        args.source_packages, args.compilation_cache)


if __name__ == "__main__":
    main()
