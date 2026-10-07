#!/usr/bin/env python3
"""Build, test and record an app smoke scenario through XcodeBuildMCP."""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


def checked_output(process):
    payload = json.loads(process.stdout)
    result = payload.get("result", payload)
    if (process.returncode or payload.get("isError") or result.get("didError") is not False):
        raise ValueError(f"XcodeBuildMCP failed: {result.get('error') or process.stderr or process.stdout}")
    return result.get("data", result)


def invoke_mcp(directory, sequence, workflow, command, parameters):
    invocation = ["xcodebuildmcp", workflow, command, "--json", json.dumps(parameters),
                  "--output", "json", "--verbose"]
    for attempt in range(2):
        suffix = "" if attempt == 0 else "-retry-1"
        diagnostic = directory / f"{sequence:02d}-{command}{suffix}"
        print(f"[{sequence:02d}{suffix}] xcodebuildmcp {workflow} {command}", flush=True)
        process = subprocess.run(invocation, text=True, capture_output=True, timeout=1800)
        diagnostic.with_suffix(".json").write_text(process.stdout)
        diagnostic.with_suffix(".log").write_text(process.stderr)
        try:
            return checked_output(process)
        except ValueError:
            if attempt or workflow != "ui-automation" or command not in {"wait-for-ui", "snapshot-ui"}:
                raise
            try:
                payload = json.loads(process.stdout)
                result = payload.get("result", payload)
                ui_error = result.get("data", {}).get("uiError", {})
                polling_failure = (result.get("didError") is True
                                   and result.get("error") == "Failed to poll runtime UI snapshot."
                                   and ui_error.get("code") == "ACTION_FAILED"
                                   and ui_error.get("message") == "Failed to poll runtime UI snapshot.")
            except (ValueError, AttributeError, TypeError):
                polling_failure = False
            if not polling_failure:
                raise


def select_simulator(simulators):
    phones = [s for s in simulators if s.get("isAvailable") and s["name"].startswith("iPhone")]
    booted = [s for s in phones if s["state"] == "Booted"]
    preferred = [s for s in phones if s["name"] == "iPhone 17 Pro"]
    candidates = booted or preferred
    if not candidates:
        raise ValueError("No available iPhone 17 Pro; install its runtime or boot an existing iPhone.")
    return max(candidates, key=lambda s: tuple(map(int, re.findall(r"\d+", s["runtime"]))))


def target(capture, label, role):
    matches = [e for e in capture["elements"] if e.get("label") == label
               and e.get("role") == role and "tap" in e.get("actions", [])]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one tappable {role} labelled {label!r}; got {len(matches)}")
    return matches[0]["ref"]


def assert_tab_screen(capture, label):
    """Require the native navigation heading and the selected tab, not its persistent label alone."""
    elements = capture["elements"]
    heading = any(e.get("identifier") == label and e.get("role") == "other"
                  and e.get("state", {}).get("visible") is True for e in elements)
    selected = any(e.get("label") == label and e.get("role") == "tab"
                   and (e.get("value") == "1" or e.get("state", {}).get("selected") is True)
                   for e in elements)
    if not heading or not selected:
        raise ValueError(f"The {label} navigation heading and selected tab must both be visible")


def setting_control(capture, label, contains=False):
    matches = [e for e in capture["elements"] if e.get("role") in ["button", "cell"]
               and "tap" in e.get("actions", [])
               and (label in e.get("label", "") if contains else
                    e.get("label", "").split(",")[0].rstrip(". …") == label)]
    if not matches:
        return None
    # Settings exposes the same SwiftUI row as outer/inner buttons and sometimes
    # repeats the hierarchy. Accept these only when they occupy the same control.
    outer = max(matches, key=lambda e: e["frame"]["width"] * e["frame"]["height"])
    bounds = outer["frame"]
    for element in matches:
        frame = element["frame"]
        if (frame["x"] < bounds["x"] or frame["y"] < bounds["y"]
                or frame["x"] + frame["width"] > bounds["x"] + bounds["width"] + 0.01
                or frame["y"] + frame["height"] > bounds["y"] + bounds["height"] + 0.01):
            raise ValueError(f"Ambiguous Settings controls for {label!r}")
    return outer["ref"]


def run(directory, verify_app_names=False):
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "attachments").mkdir(exist_ok=True)
    metadata = {
        "head_sha": os.environ.get("HEAD_SHA", subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()),
        "checkout_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "evidence_kind": "app-smoke", "scenario": "Home → People → Insights → Add a gift",
        "journey_outcome": "failure", "export_outcome": "failure",
        "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"),
        "mcp": "2.7.0", "checkpoints": [],
    }
    sequence = 0
    simulator = None
    recording = False

    def mcp(workflow, command, **parameters):
        nonlocal sequence
        sequence += 1
        return invoke_mcp(directory, sequence, workflow, command, parameters)

    def wait(**predicate):
        return mcp("ui-automation", "wait-for-ui", simulatorId=simulator["simulatorId"],
                   timeoutMs=20000, **predicate)["capture"]

    def checkpoint(name, *, settle=True, **readiness):
        if settle:
            wait(predicate="settled", settledDurationMs=800)
        capture = (wait(predicate="exists", **readiness) if readiness else
                   mcp("ui-automation", "snapshot-ui", simulatorId=simulator["simulatorId"])["capture"])
        image = mcp("simulator", "screenshot", simulatorId=simulator["simulatorId"], returnFormat="path")
        source = Path(image["artifacts"]["screenshotPath"])
        destination = directory / "attachments" / f"{name}.png"
        # MCP 2.7 optimizes captures to JPEG. Normalize that real capture to PNG for publication.
        subprocess.run(["sips", "-s", "format", "png", str(source), "--out", str(destination)],
                       check=True, capture_output=True)
        if destination.stat().st_size == 0:
            raise ValueError("Empty simulator screenshot")
        metadata["checkpoints"].append({"name": name, "image": f"attachments/{name}.png"})
        return capture

    def tap_setting(label, *, contains=False, allow_text_touch=False):
        for attempt in range(7):
            capture = mcp("ui-automation", "snapshot-ui", simulatorId=simulator["simulatorId"])["capture"]
            ref = setting_control(capture, label, contains)
            if ref:
                mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"], elementRef=ref)
                return wait(predicate="settled", settledDurationMs=800)
            # The native language picker exposes its actionable row only as
            # static text. Touch that observed element instead of coordinates.
            if allow_text_touch:
                texts = [e for e in capture["elements"] if e.get("role") == "text"
                         and "touch" in e.get("actions", [])
                         and (label in e.get("label", "") if contains else e.get("label") == label)]
                frames = {tuple(e["frame"].values()) for e in texts}
                if texts and len(frames) == 1:
                    mcp("ui-automation", "touch", simulatorId=simulator["simulatorId"],
                        elementRef=texts[0]["ref"], down=True, up=True)
                    return wait(predicate="settled", settledDurationMs=800)
                if texts:
                    raise ValueError(f"Ambiguous language text for {label!r}")
            if attempt == 6:
                raise ValueError(f"No Settings control for {label!r}")
            scroll = next(e for e in capture["elements"] if "swipeWithin" in e.get("actions", []))
            mcp("ui-automation", "swipe", simulatorId=simulator["simulatorId"],
                withinElementRef=scroll["ref"], direction="up", distance=0.7)
            wait(predicate="settled", settledDurationMs=800)

    def prepare_russian_clipboard():
        session = mcp("debugging", "attach", simulatorId=simulator["simulatorId"],
                      bundleId="pro.ziganshin.WhoGaveWhat", continueOnAttach=False)["session"]["debugSessionId"]
        try:
            for command in ['expression -l objc++ -- @import UIKit',
                            'expression -l objc++ -- (void)[[UIPasteboard generalPasteboard] setString:@"кто че"]']:
                result = mcp("debugging", "lldb-command", debugSessionId=session,
                             command=command, timeoutMs=10000)
                if any("error:" in line.lower() for line in result["outputLines"]):
                    raise ValueError(f"Unable to prepare Russian clipboard: {result['outputLines']}")
        finally:
            mcp("debugging", "detach", debugSessionId=session)

    def search_settings(text, *, settle=True):
        deadline = time.monotonic() + 20
        while True:
            capture = mcp("ui-automation", "snapshot-ui", simulatorId=simulator["simulatorId"])["capture"]
            fields = [e for e in capture["elements"] if "typeText" in e.get("actions", [])]
            if len(fields) == 1:
                break
            if fields or time.monotonic() >= deadline:
                raise ValueError("Expected one native search field")
        if text == "кто че":
            # AXe typing accepts ASCII only. Use actual system Paste for the
            # public query prepared through UIKit while the app was foreground.
            mcp("ui-automation", "type-text", simulatorId=simulator["simulatorId"],
                elementRef=fields[0]["ref"], text=" ", replaceExisting=True)
            mcp("ui-automation", "key-press", simulatorId=simulator["simulatorId"], keyCode=42)
            capture = wait(predicate="exists", identifier="SpotlightSearchField", role="text-field")
            field = next(e for e in capture["elements"] if e.get("identifier") == "SpotlightSearchField"
                         and "longPress" in e.get("actions", []))
            mcp("ui-automation", "long-press", simulatorId=simulator["simulatorId"],
                elementRef=field["ref"], duration=900)
            capture = wait(predicate="exists", label="Paste")
            mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"],
                elementRef=target(capture, "Paste", "button"))
            capture = wait(predicate="textContains", text=text)
            if not any(e.get("identifier") == "SpotlightSearchField" and e.get("value") == text
                       for e in capture["elements"]):
                raise ValueError("System Paste did not enter the exact Russian Spotlight query")
        else:
            mcp("ui-automation", "type-text", simulatorId=simulator["simulatorId"],
                elementRef=fields[0]["ref"], text=text, replaceExisting=True)
        if settle:
            wait(predicate="settled", settledDurationMs=800)
        else:
            wait(predicate="textContains", text=text)

    def home_app_checkpoint(name):
        capture = wait(predicate="exists", identifier="Home screen icons", role="other")
        for attempt in range(3):
            if any(e.get("label") in ["Who Gave", "кто че"] and "tap" in e.get("actions", [])
                   for e in capture["elements"]):
                return checkpoint(name, settle=False)
            if attempt == 2:
                raise ValueError("App icon is not visible on the Home-screen pages")
            region = next(e for e in capture["elements"] if e.get("identifier") == "Home screen icons")
            mcp("ui-automation", "swipe", simulatorId=simulator["simulatorId"],
                withinElementRef=region["ref"], direction="left", distance=1.0, duration=0.3)
            capture = wait(predicate="exists", identifier="Home screen icons", role="other")

    def spotlight_open(query, name):
        mcp("ui-automation", "button", simulatorId=simulator["simulatorId"], buttonType="home")
        capture = wait(predicate="exists", identifier="Home screen icons", role="other")
        regions = [e for e in capture["elements"] if "swipeWithin" in e.get("actions", [])]
        if len(regions) != 1:
            raise ValueError("Expected one Home-screen swipe region")
        mcp("ui-automation", "swipe", simulatorId=simulator["simulatorId"],
            withinElementRef=regions[0]["ref"], direction="down", distance=0.5)
        search_settings(query, settle=False)
        # The query field itself cannot establish discovery. Require a real,
        # actionable Russian launcher result for both the Russian and English query.
        deadline = time.monotonic() + 60
        while True:
            capture = mcp("ui-automation", "snapshot-ui", simulatorId=simulator["simulatorId"])["capture"]
            results = [e for e in capture["elements"] if "кто че" in e.get("label", "")
                       and "ResultCell" in e.get("identifier", "")
                       and any(action in e.get("actions", []) for action in ["tap", "touch"])]
            if results:
                if len(results) != 1:
                    raise ValueError(f"Ambiguous Spotlight launcher results for {query!r}")
                label = results[0]["label"]
                capture = checkpoint(name, settle=False)
                result = next(e for e in capture["elements"] if e.get("label") == label
                              and "ResultCell" in e.get("identifier", "")
                              and any(action in e.get("actions", []) for action in ["tap", "touch"]))
                metadata.setdefault("spotlight_queries", []).append({"query": query, "result": label})
                if "tap" in result["actions"]:
                    mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"], elementRef=result["ref"])
                else:
                    # Native Spotlight result cells expose touch rather than tap.
                    mcp("ui-automation", "touch", simulatorId=simulator["simulatorId"],
                        elementRef=result["ref"], down=True, up=True)
                return
            if time.monotonic() >= deadline:
                checkpoint(name + "-missing", settle=False)
                raise ValueError(f"Spotlight did not expose the indexed launcher for {query!r}")
            wait(predicate="textContains", text=query)

    try:
        simulator = select_simulator(mcp("simulator", "list", enabled=True)["simulators"])
        metadata.update(device=simulator["name"], runtime=simulator["runtime"])
        settings = dict(projectPath="WhoGaveWhat.xcodeproj", scheme="WhoGaveWhat",
                        simulatorId=simulator["simulatorId"], derivedDataPath=str(directory / "DerivedData"),
                        extraArgs=["CODE_SIGNING_ALLOWED=NO"])
        mcp("simulator", "test", **{**settings, "extraArgs": settings["extraArgs"] + [
            "-resultBundlePath", str(directory / "UnitTests.xcresult"), "-parallel-testing-enabled", "NO"]})
        mcp("simulator", "build-and-run", **settings)
        bundle = directory / "DerivedData/Build/Products/Debug-iphonesimulator/WhoGaveWhat.app"
        for language, name in [("en", "Who Gave"), ("ru", "кто че")]:
            resource = bundle / f"{language}.lproj/InfoPlist.strings"
            info = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(resource)]))
            if any(info.get(key) != name for key in ["CFBundleDisplayName", "CFBundleName"]):
                raise ValueError(f"Built {language} system app names do not match {name!r}")
        metadata["bundle_names"] = {"en": "Who Gave", "ru": "кто че"}
        info = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(bundle / "Info.plist")]))
        if info.get("NSUserActivityTypes") != ["com.apple.corespotlightitem"]:
            raise ValueError("Built app does not declare its Spotlight activity type")
        mcp("simulator", "stop", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat")
        mcp("simulator", "launch-app", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat",
            env={"KS_START": "app", "KS_TAB": "home"}, launchArgs=["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        wait(predicate="exists", label="Add a gift", role="button")
        mcp("simulator", "record-video", simulatorId=simulator["simulatorId"], start=True, fps=15)
        recording = True
        capture = checkpoint("home", label="Home", role="tab")
        for label in ["People", "Insights"]:
            mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"], elementRef=target(capture, label, "tab"))
            wait(predicate="exists", identifier=label, role="other")
            capture = checkpoint(label.lower(), label=label, role="tab")
            assert_tab_screen(capture, label)
        mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"], elementRef=target(capture, "Add a gift", "button"))
        wait(predicate="exists", identifier="add-gift.name")
        checkpoint("add-gift", identifier="add-gift.name")
        if verify_app_names:
            mcp("ui-automation", "button", simulatorId=simulator["simulatorId"], buttonType="home")
            checkpoint("home-screen-english")
            mcp("simulator", "launch-app", simulatorId=simulator["simulatorId"], bundleId="com.apple.Preferences")
            checkpoint("system-settings")
            tap_setting("General")
            tap_setting("Language & Region")
            checkpoint("language-region-before")
            tap_setting("Add Language")
            search_settings("Russian")
            checkpoint("russian-language-picker")
            tap_setting("Russian", contains=True, allow_text_touch=True)
            checkpoint("language-confirmation")
            try:
                tap_setting("Use English", contains=True)
            except ValueError as error:
                # Adding a preferred language can complete while Settings
                # invalidates the automation connection. Never repeat the tap;
                # reconcile its effect from a new native snapshot instead.
                if "Daemon request timed out after 30000ms" not in str(error):
                    raise
                metadata["language_confirmation_timeout"] = True
            capture = checkpoint("english-system-russian-secondary")
            english = [e for e in capture["elements"] if e.get("label") == "Reorder English"]
            russian = [e for e in capture["elements"] if e.get("label") in ["Reorder Russian", "Reorder Русский"]]
            if not english or not russian or english[0]["frame"]["y"] >= russian[0]["frame"]["y"]:
                raise ValueError("Expected English first and Russian second in iPhone preferred languages")
            tap_setting("General")
            tap_setting("Settings")
            # Global Settings search does not reliably index newly installed
            # third-party apps. The Apps list owns the installed-app registry.
            tap_setting("Apps")
            checkpoint("settings-apps-list")
            search_settings("Who Gave")
            checkpoint("settings-search-app")
            tap_setting("Who Gave", contains=True, allow_text_touch=True)
            checkpoint("app-settings-before")
            tap_setting("Language")
            checkpoint("app-language-picker")
            tap_setting("Russian", contains=True, allow_text_touch=True)
            checkpoint("app-language-russian")
            mcp("ui-automation", "button", simulatorId=simulator["simulatorId"], buttonType="home")
            capture = home_app_checkpoint("home-screen-russian-app")
            metadata["per_app_home_names"] = [e["label"] for e in capture["elements"]
                                              if e.get("label") in ["Who Gave", "кто че"] and "tap" in e.get("actions", [])]
            mcp("simulator", "launch-app", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat",
                env={"KS_START": "app", "KS_TAB": "home"})
            wait(predicate="exists", label="Добавить подарок", role="button")
            capture = checkpoint("russian-app-home")
            mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"],
                elementRef=target(capture, "Добавить подарок", "button"))
            capture = wait(predicate="exists", identifier="add-gift.name")
            field = next(e for e in capture["elements"] if e.get("identifier") == "add-gift.name"
                         and "typeText" in e.get("actions", []))
            mcp("ui-automation", "type-text", simulatorId=simulator["simulatorId"],
                elementRef=field["ref"], text="Spotlight draft", replaceExisting=True)
            checkpoint("spotlight-draft-before")
            prepare_russian_clipboard()
            for query, name in [("кто че", "spotlight-russian"), ("who gave", "spotlight-english")]:
                spotlight_open(query, name)
                capture = wait(predicate="exists", identifier="add-gift.name")
                if not any(e.get("identifier") == "add-gift.name" and e.get("value") == "Spotlight draft"
                           for e in capture["elements"]):
                    raise ValueError("Opening from Spotlight lost the existing gift draft")
                checkpoint(name + "-opened")
            mcp("simulator", "stop", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat")
            spotlight_open("кто че", "spotlight-cold-launch")
            wait(predicate="exists", label="Далее", role="button")
            checkpoint("spotlight-cold-onboarding")
            metadata["evidence_kind"] = "feature-acceptance"
            metadata["scenario"] += (" → English iOS + Russian app language → Home-screen name and Russian app"
                                     " → Russian and English Spotlight queries → Open with gift draft preserved"
                                     " → Cold Spotlight launch preserves onboarding")
        metadata["journey_outcome"] = "success"
    finally:
        if recording:
            try:
                mcp("simulator", "record-video", simulatorId=simulator["simulatorId"], stop=True,
                    outputFile=str(directory / "journeys.mp4"))
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                metadata["journey_outcome"] = "failure"
                metadata["recording_error"] = str(error)
        video = directory / "journeys.mp4"
        if metadata["journey_outcome"] == "success" and video.is_file() and video.stat().st_size:
            metadata["export_outcome"] = "success"
        (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        # Build products are not evidence and would consume artifact storage.
        shutil.rmtree(directory / "DerivedData", ignore_errors=True)
    if metadata["export_outcome"] != "success":
        raise ValueError("App smoke media export is incomplete")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--verify-app-names", action="store_true",
                        help="Exercise system/app language settings on a disposable Simulator")
    args = parser.parse_args()
    run(args.directory, args.verify_app_names)
