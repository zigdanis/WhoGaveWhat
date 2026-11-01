#!/usr/bin/env python3
"""Capture the plain App Store screenshots in every store language and lay them out for fastlane deliver.

The Debug app runs with its sample data on a fresh Simulator, once per language, through
WhoGaveWhatUITests/StoreScreenshotsUITests. `--display iphone-6.9` (the default) uses a 6.9-inch iPhone and
writes `<out>/screenshots/<locale>/NN_slug.png`; `--display iphone-6.3` uses iPhone 18 Pro and writes
`medium_NN_slug.png`; `--display iphone-duo` uses iPhone Duo, which boots folded, and writes the outer display as
`duo_NN_slug.png`; `--display ipad-13` uses the newest 13-inch iPad Pro and writes `ipad_NN_slug.png` in portrait.
Each run also writes metadata.json and an index.html contact sheet. `--combine PARTS` merges the sets' artifacts into
one folder per language, the layout the App Store metadata workflow uploads, with a review page of every set;
`--review-page FILE` turns such a folder into one self-contained page with the images embedded.
"""
import argparse
import base64
import collections
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
import tempfile
from pathlib import Path
from urllib.parse import quote

_spec = importlib.util.spec_from_file_location("simulator_tools", Path(__file__).with_name("simulator_tools.py"))
tools = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tools)

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ("en-US", "ru")
# One App Store Connect screenshot set: Apple's accepted portrait sizes, the file name prefix that keeps the sets
# apart in one language folder (deliver sorts files by name and sorts them into sets by size), and either the one
# Simulator model the set needs or the model name patterns it accepts, most preferred first. A pattern's number
# group, when it has one, prefers the newest model.
Display = collections.namedtuple("Display", "key title sizes prefix device models")
IPHONE_69 = Display("iphone-6.9", "6.9-inch", frozenset({(1320, 2868), (1290, 2796), (1260, 2736)}), "", None,
                    (r"iPhone 18 Pro Max", r"iPhone (\d+) Pro Max", r"iPhone (\d+) Plus"))
# Apple requires at least one screenshot for iPhone with Dynamic Island (medium display), the 6.3-inch set.
IPHONE_63 = Display("iphone-6.3", "6.3-inch", frozenset({(1206, 2622), (1179, 2556)}), "medium_", "iPhone 18 Pro", ())
# The iPhone Duo Simulator boots folded, so its screenshots show the outer display.
IPHONE_DUO = Display("iphone-duo", "iPhone Duo outer display", frozenset({(1398, 2034)}), "duo_", "iPhone Duo", ())
# Apple requires the 13-inch iPad set once the app runs on iPad; smaller iPads get it scaled down. fastlane deliver
# files both sizes under the 13-inch display type (APP_IPAD_PRO_3GEN_129).
IPAD_13 = Display("ipad-13", "13-inch iPad", frozenset({(2064, 2752), (2048, 2732)}), "ipad_", None,
                  (r"iPad Pro 13-inch \(M(\d+)\)", r"iPad Air 13-inch \(M(\d+)\)"))
DISPLAYS = {display.key: display for display in (IPHONE_69, IPHONE_63, IPHONE_DUO, IPAD_13)}
ALLOWED_SIZES = IPHONE_69.sizes
MIN_SHOTS = 5
MAX_SHOTS = 10  # App Store Connect accepts at most ten screenshots per set.
STATUS_BAR_ARGUMENTS = (
    "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
    "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100")
TEST_CLASS = "WhoGaveWhatUITests/StoreScreenshotsUITests"
# xcodebuild forwards TEST_RUNNER_<NAME> to the test runner as <NAME>; the test is skipped without them.
ATTACHMENT_NAME = re.compile(r"store-(?P<locale>en-US|ru)-(?P<number>\d{2})-(?P<slug>[a-z0-9]+(?:-[a-z0-9]+)*)")
BUILD_TIMEOUT_SECONDS = 1800
STATUS_BAR_ATTEMPTS = 3
STATUS_BAR_TIMEOUT_SECONDS = 90
TEST_TIMEOUT_SECONDS = 900


# MARK: Device selection

def _ios_runtimes(payload):
    return [runtime for runtime in payload.get("runtimes", [])
            if runtime.get("isAvailable") and str(runtime.get("name", "")).startswith("iOS")]


def _device_preference(name, display):
    """Sort key for a candidate model: the earlier pattern of `display.models` first, then the newest model."""
    for group, pattern in enumerate(display.models):
        match = re.fullmatch(pattern, name)
        if match:
            return (group, -int(match.group(1)) if match.groups() else 0)
    return None


def choose_device(payload, device=None, runtime=None, display=IPHONE_69):
    """Pick the Simulator model for `display` and the newest available iOS runtime that supports it.

    `payload` is the JSON of `simctl list runtimes available` (or `simctl list -j`). Without `device`, only the models
    matching the set's patterns qualify: for the 6.9-inch set iPhone 18 Pro Max, other Pro Max and Plus models; for
    the 13-inch iPad set the 13-inch iPad Pro, then the 13-inch iPad Air. iPhone Duo is accepted only for its own
    set. A set tied to one model, such as iPhone Duo, accepts only that model.
    """
    runtimes = _ios_runtimes(payload)
    if runtime is not None:
        runtimes = [item for item in runtimes if item.get("name") == runtime]
    supported = {}
    for item in runtimes:
        for device_type in item.get("supportedDeviceTypes", []):
            supported.setdefault(device_type.get("name", ""), []).append(item)
    if display.device is not None:
        if device not in (None, display.device):
            raise ValueError(f"The {display.title} screenshots need {display.device}, not {device}")
        device = display.device
        names = [device] if device in supported else []
    elif device is not None:
        if "Duo" in device:
            raise ValueError(f"iPhone Duo does not produce {display.title} App Store screenshot sizes")
        names = [device] if device in supported else []
    else:
        names = sorted((name for name in supported if _device_preference(name, display) is not None),
                       key=lambda name: _device_preference(name, display))
    if not names:
        family = "iPad" if display is IPAD_13 else "iPhone"
        wanted = device or ("13-inch iPad" if display is IPAD_13 else "6.9-inch (Pro Max or Plus) iPhone")
        available = ", ".join(sorted(name for name in supported if name.startswith(family))) or "none"
        raise ValueError(
            f"No available {wanted} Simulator{f' on {runtime}' if runtime else ''}; available {family}s: {available}")
    name = names[0]
    chosen = max(supported[name], key=lambda item: tools._runtime_version(item["name"]))
    return {"device": name, "runtime": chosen["name"], "runtime_identifier": chosen.get("identifier")}


# MARK: Attachments and layout

def output_name(number, slug, prefix=""):
    return f"{prefix}{number:02d}_{slug}.png"


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


def validate_size(width, height, name, display=IPHONE_69):
    if width >= height:
        raise ValueError(f"{name} is {width}x{height}; store screenshots must be portrait")
    if (width, height) not in display.sizes:
        allowed = ", ".join(f"{w}x{h}" for w, h in sorted(display.sizes, reverse=True))
        raise ValueError(f"{name} is {width}x{height}; the {display.title} sizes are {allowed}")


def validate_set(shots_by_locale, display=IPHONE_69):
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
            validate_size(width, height, f"{locale}/{output_name(number, slug, display.prefix)}", display)
            sizes.add((width, height))
    if len(sizes) > 1:
        raise ValueError(f"Screenshots mix sizes: {sorted(sizes)}")
    return next(iter(sizes)) if sizes else None


def export_locale(directory, locale, result_bundle, display=IPHONE_69):
    """Export one run's attachments and copy its store screenshots to `screenshots/<locale>/`."""
    attachments = directory / f"attachments-{locale}"
    tools.export_xcresult_attachments(result_bundle, attachments, directory)
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
        shutil.copy2(source, target / output_name(number, slug, display.prefix))
        result.append((number, slug, png_size(source)))
    return result


# MARK: Reports

PAGE_STYLE = ("<style>body{font:16px/1.5 system-ui;margin:24px auto;max-width:1400px;padding:0 16px}"
              ".row{display:flex;flex-wrap:wrap;gap:16px}figure{margin:0;width:220px}"
              "img{width:100%;border:1px solid #ccc;border-radius:12px;cursor:zoom-in}"
              "figcaption{overflow-wrap:anywhere;font-size:13px}"
              "dialog{border:0;padding:0;background:transparent;max-width:100vw;max-height:100vh}"
              "dialog img{width:auto;max-width:96vw;max-height:94vh;border:0;cursor:zoom-out}"
              "dialog::backdrop{background:rgba(0,0,0,.85)}dialog p{margin:6px 0 0;color:#fff;text-align:center;font-size:13px}"
              "</style>")
# A tap opens the shot full screen in the page and another closes it. Following the link instead fails where
# the page embeds its images, because browsers refuse to open a data: URL as a page. While open, the arrow keys
# or a horizontal swipe step through every shot on the page in order, and Escape closes it.
ZOOM = ('<dialog id="zoom"><img alt=""><p></p></dialog><script>'
        "const zoom=document.getElementById('zoom');let shown=-1,touchX=null;"
        "function show(index){const all=[...document.querySelectorAll('figure a')];if(!all.length)return;"
        "shown=(index+all.length)%all.length;const link=all[shown];zoom.querySelector('img').src=link.querySelector('img').src;"
        "zoom.querySelector('p').textContent=`${link.closest('figure').dataset.label}"
        " \u00b7 ${shown+1}/${all.length}`;if(!zoom.open)zoom.showModal()}"
        "document.addEventListener('click',event=>{const link=event.target.closest('figure a');"
        "if(link){event.preventDefault();show([...document.querySelectorAll('figure a')].indexOf(link))}"
        "else if(event.target.closest('dialog')){zoom.close()}});"
        "document.addEventListener('keydown',event=>{if(!zoom.open)return;"
        "if(event.key==='ArrowRight'||event.key==='ArrowDown'){event.preventDefault();show(shown+1)}"
        "else if(event.key==='ArrowLeft'||event.key==='ArrowUp'){event.preventDefault();show(shown-1)}});"
        "zoom.addEventListener('touchstart',event=>{touchX=event.touches[0].clientX},{passive:true});"
        "zoom.addEventListener('touchend',event=>{if(touchX===null)return;const dx=event.changedTouches[0].clientX-touchX;"
        "touchX=null;if(Math.abs(dx)>50){event.preventDefault();show(shown+(dx<0?1:-1))}});</script>")


def _page_start(title):
    return ['<!doctype html><html lang="en"><meta charset="utf-8">',
            '<meta name="viewport" content="width=device-width, initial-scale=1">',
            f"<title>{html.escape(title)}</title>", PAGE_STYLE, ZOOM, f"<h1>{html.escape(title)}</h1>"]


def _locale_rows(parts, shots_by_locale, prefix, source, heading, group):
    """One row of figures per locale; `source(locale, file name)` gives each image's address. The full-screen view
    labels each shot with `group`, its locale and its file name."""
    for locale, shots in shots_by_locale.items():
        parts.append(f"<{heading}>{html.escape(locale)}</{heading}><div class=\"row\">")
        for number, slug, (width, height) in shots:
            name = output_name(number, slug, prefix)
            address = html.escape(source(locale, name))
            # An embedded image is not repeated in the link: the page would double in size for a link that can't open.
            link = "#" if address.startswith("data:") else address
            caption = html.escape(f"{name} ({width}x{height})")
            label = html.escape(f"{group} · {locale} · {name}")
            parts.append(f'<figure data-label="{label}"><a href="{link}"><img loading="lazy" src="{address}" '
                         f'alt="{caption}"></a><figcaption>{caption}</figcaption></figure>')
        parts.append("</div>")


def _relative_source(locale, name):
    return quote(f"screenshots/{locale}/{name}")


def render_index(shots_by_locale, title="WhoGaveWhat App Store screenshots", prefix=""):
    parts = _page_start(title)
    _locale_rows(parts, shots_by_locale, prefix, _relative_source, "h2", title)
    return "\n".join(parts) + "\n"


def render_review(sets, title="WhoGaveWhat App Store screenshots: every set", source=_relative_source, note=None):
    """The page for reviewing an upload: every set, then every locale. `sets` is [(display, metadata, shots)]."""
    parts = _page_start(title)
    parts.append("<p>Tap a screenshot to open it full screen. The arrow keys or a swipe go to the next or previous one;"
                 " a tap or Escape closes it.</p>")
    if note:
        parts.append(f"<p>{html.escape(note)}</p>")
    head = sorted({metadata.get("head_sha", "")[:12] for _display, metadata, _shots in sets} - {""})
    if head:
        parts.append(f"<p>Commit {html.escape(', '.join(head))}</p>")
    for display, metadata, shots_by_locale in sets:
        details = ", ".join(str(value) for value in (metadata.get("device"), metadata.get("runtime")) if value)
        count = sum(len(shots) for shots in shots_by_locale.values())
        parts.append(f"<h2>{html.escape(display.title)}{f' ({html.escape(details)})' if details else ''}"
                     f" &middot; {count} screenshots</h2>")
        _locale_rows(parts, shots_by_locale, display.prefix, source, "h3", display.title)
    return "\n".join(parts) + "\n"


def combine_sets(parts, out, displays=tuple(DISPLAYS)):
    """Merge the per-set artifacts `<parts>/store-screenshots-<display>` into `<out>/screenshots/<locale>/`.

    This is the layout the App Store metadata workflow uploads: one folder per language holding every set. Each
    set's metadata and contact sheet stay in `<out>/<display>/`, and `<out>/index.html` shows every set. Returns
    `[(display, metadata, shots_by_locale)]` in the order of `DISPLAYS`.
    """
    found = {path.name.removeprefix("store-screenshots-") for path in parts.iterdir() if path.is_dir()}
    if found != set(displays):
        raise ValueError(f"Expected the screenshot sets {sorted(displays)}, got {sorted(found)}")
    sets = []
    for display in (display for key, display in DISPLAYS.items() if key in displays):
        part = parts / f"store-screenshots-{display.key}"
        (out / display.key).mkdir(parents=True)
        metadata = json.loads((part / "metadata.json").read_text())
        shutil.copy2(part / "metadata.json", out / display.key / "metadata.json")
        # The set's own contact sheet now sits one level below the screenshots it links to.
        sheet = (part / "index.html").read_text()
        sheet = sheet.replace('href="screenshots/', 'href="../screenshots/').replace('src="screenshots/', 'src="../screenshots/')
        (out / display.key / "index.html").write_text(sheet)
        languages = sorted(path.name for path in (part / "screenshots").iterdir())
        if set(languages) - set(LOCALES):
            raise ValueError(f"{display.key} has unexpected language folders: {languages}")
        pattern = re.compile(rf"{re.escape(display.prefix)}(\d{{2}})_([a-z0-9]+(?:-[a-z0-9]+)*)\.png")
        shots_by_locale = {}
        for locale in (locale for locale in LOCALES if locale in languages):
            shots = []
            for source in sorted((part / "screenshots" / locale).iterdir()):
                match = pattern.fullmatch(source.name)
                if not match:
                    raise ValueError(f"{display.key} has an unexpected file {locale}/{source.name}")
                target = out / "screenshots" / locale / source.name
                if target.exists():
                    raise ValueError(f"Two sets both produced {locale}/{source.name}")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                shots.append((int(match[1]), match[2], png_size(source)))
            shots_by_locale[locale] = shots
        validate_set(shots_by_locale, display)
        sets.append((display, metadata, shots_by_locale))
    (out / "index.html").write_text(render_review(sets))
    return sets


def read_combined(directory):
    """The sets of a combined folder written by `combine_sets`, as `[(display, metadata, shots_by_locale)]`."""
    sets = []
    for display in DISPLAYS.values():
        if not (directory / display.key / "metadata.json").is_file():
            continue
        metadata = json.loads((directory / display.key / "metadata.json").read_text())
        pattern = re.compile(rf"{re.escape(display.prefix)}(\d{{2}})_([a-z0-9]+(?:-[a-z0-9]+)*)\.png")
        shots_by_locale = {}
        for locale in LOCALES:
            shots = []
            for path in sorted((directory / "screenshots" / locale).iterdir()):
                match = pattern.fullmatch(path.name)
                if match:
                    shots.append((int(match[1]), match[2], png_size(path)))
            shots_by_locale[locale] = shots
        validate_set(shots_by_locale, display)
        sets.append((display, metadata, shots_by_locale))
    if not sets:
        raise ValueError(f"{directory} holds no combined screenshot sets")
    return sets


def embedded_image(path, width):
    """A data: URL for one screenshot, scaled to `width` as JPEG with ffmpeg or macOS sips, else the PNG itself."""
    with tempfile.TemporaryDirectory() as temporary:
        target = Path(temporary) / "shot.jpg"
        for command in (["ffmpeg", "-loglevel", "error", "-y", "-i", str(path), "-vf", f"scale={width}:-1",
                         "-q:v", "4", str(target)],
                        ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "70", "--resampleWidth", str(width),
                         str(path), "--out", str(target)]):
            if shutil.which(command[0]):
                subprocess.run(command, check=True, capture_output=True)
                return "data:image/jpeg;base64," + base64.b64encode(target.read_bytes()).decode()
    return "data:image/png;base64," + base64.b64encode(Path(path).read_bytes()).decode()


def write_review_page(directory, page, note=None):
    """Write one self-contained review page for a combined folder: every set and locale, images embedded, so the
    file opens anywhere, such as from a T3 attachment on a phone."""
    sets = read_combined(directory)
    widths = {display.key: 1032 if display is IPAD_13 else 660 for display, _metadata, _shots in sets}
    prefixes = sorted(((display.prefix, display.key) for display, _metadata, _shots in sets), reverse=True)

    def source(locale, name):
        key = next(key for prefix, key in prefixes if name.startswith(prefix))
        return embedded_image(directory / "screenshots" / locale / name, widths[key])

    page.write_text(render_review(sets, title="WhoGaveWhat App Store screenshots (all sets, EN + RU)", source=source,
                                  note=note))
    return sets


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

def override_status_bar(directory, simulator_id, attempts=STATUS_BAR_ATTEMPTS):
    """Set the clean 9:41 status bar, or keep the real one when the Simulator never accepts the override."""
    for attempt in range(1, attempts + 1):
        try:
            tools.run_command(directory, f"status-bar-{attempt}", [
                "xcrun", "simctl", "status_bar", simulator_id, "override", *STATUS_BAR_ARGUMENTS],
                STATUS_BAR_TIMEOUT_SECONDS)
            return "overridden"
        except tools.NativeCommandError as error:
            print(f"Status bar override attempt {attempt} failed: {error}", flush=True)
    print("::warning::The status bar override failed; screenshots show the Simulator's real status bar", flush=True)
    return "real"


def run(directory, device=None, runtime=None, locales=LOCALES, display=IPHONE_69):
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    clear_previous_outputs(directory)
    head = os.environ.get("HEAD_SHA") or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, cwd=ROOT).strip()
    metadata = {"head_sha": head, "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
                "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"), "locales": list(locales),
                "display": display.key,
                "outcome": "failure"}
    shots_by_locale = {}
    failed_bundles = []
    try:
        runtimes = tools.run_command(directory, "simulator-runtimes-list", [
            "xcrun", "simctl", "list", "runtimes", "available", "--json"], 30)
        choice = choose_device(json.loads(runtimes.stdout), device, runtime, display)
        metadata.update(device=choice["device"], runtime=choice["runtime"])
        listing = tools.run_command(directory, "simulator-list", [
            "xcrun", "simctl", "list", "devices", "available", "--json"], 30)
        simulator = tools.create_ci_simulator(
            directory, json.loads(listing.stdout), choice["runtime"], metadata, choice["device"])
        simulator_id = simulator["udid"]
        metadata["simulator_id"] = simulator_id
        tools.run_command(directory, "simulator-boot", ["xcrun", "simctl", "boot", simulator_id], 60)
        tools.run_command(directory, "simulator-bootstatus", ["xcrun", "simctl", "bootstatus", simulator_id, "-b"],
                          tools.COLD_BOOT_TIMEOUT_SECONDS)
        target = ["-project", "WhoGaveWhat.xcodeproj", "-scheme", "WhoGaveWhat",
                  "-destination", f"platform=iOS Simulator,id={simulator_id}",
                  "-derivedDataPath", str(directory / "DerivedData"), "-parallel-testing-enabled", "NO"]
        signing = ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
        tools.run_command(directory, "xcodebuild-build", ["xcodebuild", "build-for-testing", *target, *signing],
                          BUILD_TIMEOUT_SECONDS, cwd=ROOT)
        # Overridden after the build: right after a cold boot the override can hang while the Simulator settles.
        metadata["status_bar"] = override_status_bar(directory, simulator_id)
        for locale in locales:
            bundle = directory / f"{locale}.xcresult"
            failed_bundles.append(bundle)
            # The tests attach their own failure screenshots; default diagnostics collection can hang after a failure.
            with environment(TEST_RUNNER_KS_STORE_SCREENSHOTS="1", TEST_RUNNER_KS_STORE_LOCALE=locale):
                tools.run_command(directory, f"xcodebuild-test-{locale}", [
                    "xcodebuild", "test-without-building", *target, "-resultBundlePath", str(bundle),
                    "-collect-test-diagnostics", "never", f"-only-testing:{TEST_CLASS}", *signing],
                    TEST_TIMEOUT_SECONDS, cwd=ROOT)
            shots_by_locale[locale] = export_locale(directory, locale, bundle, display)
        size = validate_set(shots_by_locale, display)
        metadata.update(sizes=[f"{size[0]}x{size[1]}"],
                        screenshots={locale: [output_name(number, slug, display.prefix) for number, slug, _ in shots]
                                     for locale, shots in shots_by_locale.items()})
        (directory / "index.html").write_text(render_index(
            shots_by_locale, f"WhoGaveWhat App Store screenshots ({display.title})", display.prefix))
        metadata["outcome"] = "success"
        failed_bundles = []
    except (tools.NativeCommandError, OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError) as error:
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
    parser.add_argument("--combine", type=Path, metavar="PARTS",
                        help="Instead of capturing, merge the downloaded store-screenshots-<display> artifacts in PARTS "
                             "into the output folder and write one review page of every set")
    parser.add_argument("--review-page", type=Path, metavar="FILE",
                        help="Instead of capturing, write a self-contained review page of the combined folder "
                             "(a store-screenshots artifact) to FILE, with the images embedded")
    parser.add_argument("--note", help="A line of context for --review-page, such as the run it shows")
    parser.add_argument("--display", choices=sorted(DISPLAYS), default=IPHONE_69.key,
                        help="App Store screenshot set to capture (default: %(default)s)")
    parser.add_argument("--device", help="Simulator model for the 6.9-inch or iPad set (default: iPhone 18 Pro Max, else the "
                        "newest Pro Max or Plus; for iPad the newest 13-inch iPad Pro, else iPad Air)")
    parser.add_argument("--runtime", help="Require a runtime such as 'iOS 27.0' (default: newest one supporting the model)")
    parser.add_argument("--locale", action="append", choices=LOCALES, help="Store language to capture (default: all)")
    args = parser.parse_args(argv)
    if args.review_page:
        try:
            write_review_page(args.directory, args.review_page, args.note)
        except (OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        print(args.review_page)
        return 0
    if args.combine:
        try:
            for display, _metadata, shots_by_locale in combine_sets(args.combine, args.directory):
                for locale, shots in shots_by_locale.items():
                    print(display.key, locale, [output_name(number, slug, display.prefix) for number, slug, _ in shots])
        except (OSError, ValueError, json.JSONDecodeError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        return 0
    try:
        run(args.directory, args.device, args.runtime, tuple(args.locale or LOCALES), DISPLAYS[args.display])
    except (tools.NativeCommandError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
