#!/usr/bin/env python3
"""Capture the plain App Store screenshots in every store language and lay them out for fastlane deliver.

The Debug app runs with its sample data on a fresh 6.9-inch iPhone Simulator, once per language, through
WhoGaveWhatUITests/StoreScreenshotsUITests. The result is `<out>/screenshots/<locale>/NN_slug.png`, plus
metadata.json and an index.html contact sheet.
"""
import argparse
import contextlib
import html
import importlib.util
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

_spec = importlib.util.spec_from_file_location("run_app_smoke", Path(__file__).with_name("run-app-smoke.py"))
smoke = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(smoke)

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ("en-US", "ru")
# Apple's accepted portrait sizes for the 6.9-inch iPhone screenshot set.
ALLOWED_SIZES = {(1320, 2868), (1290, 2796), (1260, 2736)}
MIN_SHOTS = 5
MAX_SHOTS = 10  # App Store Connect accepts at most ten screenshots per set.
STATUS_BAR_ARGUMENTS = (
    "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
    "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100")
TEST_CLASS = "WhoGaveWhatUITests/StoreScreenshotsUITests"
# xcodebuild forwards TEST_RUNNER_<NAME> to the test runner as <NAME>; the test is skipped without them.
ATTACHMENT_NAME = re.compile(r"store-(?P<locale>en-US|ru)-(?P<number>\d{2})-(?P<slug>[a-z0-9]+(?:-[a-z0-9]+)*)")
PREFERRED_DEVICE = "iPhone 18 Pro Max"
FALLBACK_DEVICE_PATTERNS = (r"iPhone (\d+) Pro Max", r"iPhone (\d+) Plus")
BUILD_TIMEOUT_SECONDS = 1800
TEST_TIMEOUT_SECONDS = 900


# MARK: Device selection

def _ios_runtimes(payload):
    return [runtime for runtime in payload.get("runtimes", [])
            if runtime.get("isAvailable") and str(runtime.get("name", "")).startswith("iOS")]


def _device_preference(name):
    """Sort key for a 6.9-inch candidate: the preferred model, then other Pro Max, then Plus; newest first."""
    if name == PREFERRED_DEVICE:
        return (0, 0)
    for group, pattern in enumerate(FALLBACK_DEVICE_PATTERNS, start=1):
        match = re.fullmatch(pattern, name)
        if match:
            return (group, -int(match.group(1)))
    return None


def choose_device(payload, device=None, runtime=None):
    """Pick the 6.9-inch iPhone model and the newest available iOS runtime that supports it.

    `payload` is the JSON of `simctl list runtimes available` (or `simctl list -j`). Without `device` only the
    preferred model and other Pro Max and Plus models qualify; iPhone Duo is never accepted.
    """
    runtimes = _ios_runtimes(payload)
    if runtime is not None:
        runtimes = [item for item in runtimes if item.get("name") == runtime]
    supported = {}
    for item in runtimes:
        for device_type in item.get("supportedDeviceTypes", []):
            supported.setdefault(device_type.get("name", ""), []).append(item)
    if device is not None:
        if "Duo" in device:
            raise ValueError("iPhone Duo does not produce App Store screenshot sizes")
        names = [device] if device in supported else []
    else:
        names = sorted((name for name in supported if _device_preference(name) is not None), key=_device_preference)
    if not names:
        available = ", ".join(sorted(name for name in supported if name.startswith("iPhone"))) or "none"
        raise ValueError(
            f"No available {device or '6.9-inch (Pro Max or Plus) iPhone'} Simulator"
            f"{f' on {runtime}' if runtime else ''}; available iPhones: {available}")
    name = names[0]
    chosen = max(supported[name], key=lambda item: smoke._runtime_version(item["name"]))
    return {"device": name, "runtime": chosen["name"], "runtime_identifier": chosen.get("identifier")}


# MARK: Attachments and layout

def output_name(number, slug):
    return f"{number:02d}_{slug}.png"


def plan_outputs(manifest, locale):
    """Map `number -> (slug, exported file)` for this locale from an xcresulttool attachment manifest.

    A retried test attaches the same shot again; the last attachment wins. Other attachments are ignored.
    """
    shots = {}
    for test in manifest:
        for attachment in test.get("attachments", []):
            filename = attachment.get("exportedFileName", "")
            match = ATTACHMENT_NAME.search(attachment.get("suggestedHumanReadableName", ""))
            if not match or match["locale"] != locale or not filename.lower().endswith(".png"):
                continue
            shots[int(match["number"])] = (match["slug"], filename)
    if not shots:
        raise ValueError(f"The {locale} run exported no store screenshots")
    return shots


def png_size(path):
    """Read width and height from the PNG IHDR chunk."""
    with Path(path).open("rb") as image:
        header = image.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a PNG image")
    return struct.unpack(">II", header[16:24])


def validate_size(width, height, name):
    if width >= height:
        raise ValueError(f"{name} is {width}x{height}; store screenshots must be portrait")
    if (width, height) not in ALLOWED_SIZES:
        allowed = ", ".join(f"{w}x{h}" for w, h in sorted(ALLOWED_SIZES, reverse=True))
        raise ValueError(f"{name} is {width}x{height}; the 6.9-inch sizes are {allowed}")


def validate_set(shots_by_locale):
    """Check numbering, locale parity and sizes. `shots_by_locale` maps locale -> [(number, slug, (w, h))]."""
    reference = None
    sizes = set()
    for locale, shots in shots_by_locale.items():
        numbers = [number for number, _slug, _size in shots]
        if numbers != list(range(1, len(shots) + 1)):
            raise ValueError(f"{locale} screenshots are not numbered 01..{len(shots):02d} without gaps: {numbers}")
        if not MIN_SHOTS <= len(shots) <= MAX_SHOTS:
            raise ValueError(f"{locale} has {len(shots)} screenshots; expected {MIN_SHOTS} to {MAX_SHOTS}")
        names = [(number, slug) for number, slug, _size in shots]
        if reference is None:
            reference = (locale, names)
        elif names != reference[1]:
            raise ValueError(f"{locale} screenshots {names} differ from {reference[0]} {reference[1]}")
        for number, slug, (width, height) in shots:
            validate_size(width, height, f"{locale}/{output_name(number, slug)}")
            sizes.add((width, height))
    if len(sizes) > 1:
        raise ValueError(f"Screenshots mix sizes: {sorted(sizes)}")
    return next(iter(sizes)) if sizes else None


def export_locale(directory, locale, result_bundle):
    """Export one run's attachments and copy its store screenshots to `screenshots/<locale>/`."""
    attachments = directory / f"attachments-{locale}"
    smoke._export_xcresult_attachments(result_bundle, attachments, directory)
    manifest_path = attachments / "manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"The {locale} xcresult has no attachment manifest")
    plan = plan_outputs(json.loads(manifest_path.read_text()), locale)
    target = directory / "screenshots" / locale
    target.mkdir(parents=True, exist_ok=True)
    result = []
    for number, (slug, filename) in sorted(plan.items()):
        source = attachments / filename
        if not source.is_file() or not source.stat().st_size:
            raise ValueError(f"Exported {locale} screenshot {filename} is missing or empty")
        shutil.copy2(source, target / output_name(number, slug))
        result.append((number, slug, png_size(source)))
    return result


# MARK: Reports

def render_index(shots_by_locale, title="WhoGaveWhat App Store screenshots"):
    parts = ['<!doctype html><html lang="en"><meta charset="utf-8">',
             '<meta name="viewport" content="width=device-width, initial-scale=1">',
             f"<title>{html.escape(title)}</title>",
             "<style>body{font:16px/1.5 system-ui;margin:24px auto;max-width:1400px;padding:0 16px}"
             ".row{display:flex;flex-wrap:wrap;gap:16px}figure{margin:0;width:220px}"
             "img{width:100%;border:1px solid #ccc;border-radius:12px}figcaption{overflow-wrap:anywhere;font-size:13px}"
             "</style>", f"<h1>{html.escape(title)}</h1>"]
    for locale, shots in shots_by_locale.items():
        parts.append(f"<h2>{html.escape(locale)}</h2><div class=\"row\">")
        for number, slug, (width, height) in shots:
            relative = quote(f"screenshots/{locale}/{output_name(number, slug)}")
            caption = html.escape(f"{output_name(number, slug)} ({width}x{height})")
            parts.append(f'<figure><a href="{relative}"><img loading="lazy" src="{relative}" alt="{caption}"></a>'
                         f"<figcaption>{caption}</figcaption></figure>")
        parts.append("</div>")
    return "\n".join(parts) + "\n"


def clear_previous_outputs(directory):
    """Remove only this runner's products before reusing its output folder."""
    for name in ("screenshots", "DerivedData", *(f"attachments-{locale}" for locale in LOCALES),
                 *(f"{locale}.xcresult" for locale in LOCALES)):
        path = directory / name
        if path.is_symlink() or (path.exists() and not path.is_dir()):
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
    for name in ("metadata.json", "index.html"):
        path = directory / name
        if path.is_symlink() or path.exists():
            path.unlink()
    for path in directory.glob("*.log"):
        path.unlink()


@contextlib.contextmanager
def environment(**values):
    """Set environment variables for child processes started inside the block."""
    saved = {key: os.environ.get(key) for key in values}
    os.environ.update(values)
    try:
        yield
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


# MARK: Run

def run(directory, device=None, runtime=None, locales=LOCALES):
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    clear_previous_outputs(directory)
    head = os.environ.get("HEAD_SHA") or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, cwd=ROOT).strip()
    metadata = {"head_sha": head, "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
                "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"), "locales": list(locales),
                "outcome": "failure"}
    shots_by_locale = {}
    failed_bundles = []
    try:
        runtimes = smoke.run_command(directory, "simulator-runtimes-list", [
            "xcrun", "simctl", "list", "runtimes", "available", "--json"], 30)
        choice = choose_device(json.loads(runtimes.stdout), device, runtime)
        metadata.update(device=choice["device"], runtime=choice["runtime"])
        listing = smoke.run_command(directory, "simulator-list", [
            "xcrun", "simctl", "list", "devices", "available", "--json"], 30)
        simulator = smoke.create_ci_simulator(
            directory, json.loads(listing.stdout), choice["runtime"], metadata, choice["device"])
        simulator_id = simulator["udid"]
        metadata["simulator_id"] = simulator_id
        smoke.run_command(directory, "simulator-boot", ["xcrun", "simctl", "boot", simulator_id], 60)
        smoke.run_command(directory, "simulator-bootstatus", ["xcrun", "simctl", "bootstatus", simulator_id, "-b"],
                          smoke.COLD_BOOT_TIMEOUT_SECONDS)
        smoke.run_command(directory, "status-bar", [
            "xcrun", "simctl", "status_bar", simulator_id, "override", *STATUS_BAR_ARGUMENTS], 30)
        target = ["-project", "WhoGaveWhat.xcodeproj", "-scheme", "WhoGaveWhat",
                  "-destination", f"platform=iOS Simulator,id={simulator_id}",
                  "-derivedDataPath", str(directory / "DerivedData"), "-parallel-testing-enabled", "NO"]
        signing = ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
        smoke.run_command(directory, "xcodebuild-build", ["xcodebuild", "build-for-testing", *target, *signing],
                          BUILD_TIMEOUT_SECONDS, cwd=ROOT)
        for locale in locales:
            bundle = directory / f"{locale}.xcresult"
            failed_bundles.append(bundle)
            # The tests attach their own failure screenshots; default diagnostics collection can hang after a failure.
            with environment(TEST_RUNNER_KS_STORE_SCREENSHOTS="1", TEST_RUNNER_KS_STORE_LOCALE=locale):
                smoke.run_command(directory, f"xcodebuild-test-{locale}", [
                    "xcodebuild", "test-without-building", *target, "-resultBundlePath", str(bundle),
                    "-collect-test-diagnostics", "never", f"-only-testing:{TEST_CLASS}", *signing],
                    TEST_TIMEOUT_SECONDS, cwd=ROOT)
            shots_by_locale[locale] = export_locale(directory, locale, bundle)
        size = validate_set(shots_by_locale)
        metadata.update(sizes=[f"{size[0]}x{size[1]}"],
                        screenshots={locale: [output_name(number, slug) for number, slug, _ in shots]
                                     for locale, shots in shots_by_locale.items()})
        (directory / "index.html").write_text(render_index(shots_by_locale))
        metadata["outcome"] = "success"
        failed_bundles = []
    except (smoke.NativeCommandError, OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        metadata["error"] = str(error)
        raise
    finally:
        try:
            smoke.cleanup_ci_simulator(directory, metadata)
        finally:
            try:
                (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
            finally:
                shutil.rmtree(directory / "DerivedData", ignore_errors=True)
                # Keep result bundles only for a failed run; a good run already exported its attachments.
                for locale in locales:
                    bundle = directory / f"{locale}.xcresult"
                    if bundle not in failed_bundles:
                        shutil.rmtree(bundle, ignore_errors=True)
                        shutil.rmtree(directory / f"attachments-{locale}", ignore_errors=True)
    fixture = metadata.get("simulator_fixture", {})
    if fixture.get("cleanup_outcome") == "failure":
        raise ValueError(f"Screenshots were captured but the Simulator was not cleaned up: {fixture.get('cleanup_error')}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Output folder; screenshots go to <directory>/screenshots/<locale>/")
    parser.add_argument("--device", help=f"Simulator model (default: {PREFERRED_DEVICE}, else the newest Pro Max or Plus)")
    parser.add_argument("--runtime", help="Require a runtime such as 'iOS 27.0' (default: newest one supporting the model)")
    parser.add_argument("--locale", action="append", choices=LOCALES, help="Store language to capture (default: all)")
    args = parser.parse_args(argv)
    try:
        run(args.directory, args.device, args.runtime, tuple(args.locale or LOCALES))
    except (smoke.NativeCommandError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
