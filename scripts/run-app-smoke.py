#!/usr/bin/env python3
"""Build, test and record an app smoke scenario through XcodeBuildMCP."""
import argparse
import json
import os
import re
import shutil
import subprocess
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


def element(capture, *, identifier=None, label=None, role=None, prefix=False):
    """Return one current AX element, using stable identifiers where possible."""
    matches = []
    for candidate in capture.get("elements", []):
        if identifier is not None:
            value = candidate.get("identifier", "")
            if (value.startswith(identifier) if prefix else value != identifier):
                continue
        if label is not None and candidate.get("label") != label:
            continue
        if role is not None and candidate.get("role") != role:
            continue
        matches.append(candidate)
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one element identifier={identifier!r} label={label!r} role={role!r}; got {len(matches)}")
    return matches[0]


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


def run(directory):
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "attachments").mkdir(exist_ok=True)
    metadata = {
        "head_sha": os.environ.get("HEAD_SHA", subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()),
        "checkout_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "evidence_kind": "app-smoke", "scenario": "PR13 gift creation, persistence, and Settings journey",
        "journey_outcome": "failure", "export_outcome": "failure",
        "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"),
        "mcp": "2.7.0", "checkpoints": [],
        "acceptance_claims": [
            "compact gift title entry and keyboard",
            "expanded Details value entry and scrolling",
            "calendar short and long month paging with dismissal",
            "new From and To people with automatic selection",
            "duplicate gift reuses existing people",
            "save and relaunch persistence",
            "Settings currency and bundled third-party licenses",
        ],
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

    def checkpoint(name, **readiness):
        wait(predicate="settled", settledDurationMs=800)
        capture = wait(predicate="exists", **readiness)
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

    def tap(capture, **selector):
        ref = element(capture, **selector)["ref"]
        mcp("ui-automation", "batch", simulatorId=simulator["simulatorId"],
            steps=[{"action": "tap", "elementRef": ref}])

    def type_text(capture, text, **selector):
        ref = element(capture, **selector)["ref"]
        mcp("ui-automation", "type-text", simulatorId=simulator["simulatorId"],
            elementRef=ref, text=text, replaceExisting=True)

    def swipe(capture, direction, **selector):
        ref = element(capture, **selector)["ref"]
        mcp("ui-automation", "swipe", simulatorId=simulator["simulatorId"],
            withinElementRef=ref, direction=direction, distance=0.7)

    try:
        simulator = select_simulator(mcp("simulator", "list", enabled=True)["simulators"])
        metadata.update(device=simulator["name"], runtime=simulator["runtime"])
        settings = dict(projectPath="WhoGaveWhat.xcodeproj", scheme="WhoGaveWhat",
                        simulatorId=simulator["simulatorId"], derivedDataPath=str(directory / "DerivedData"),
                        extraArgs=["CODE_SIGNING_ALLOWED=NO"])
        mcp("simulator", "test", **{**settings, "extraArgs": settings["extraArgs"] + [
            "-resultBundlePath", str(directory / "UnitTests.xcresult"), "-parallel-testing-enabled", "NO"]})
        mcp("simulator", "build-and-run", **settings)
        mcp("simulator", "stop", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat")
        mcp("simulator", "launch-app", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat",
            env={"KS_START": "app", "KS_TAB": "home"}, launchArgs=["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        capture = wait(predicate="exists", label="Add a gift", role="button")
        mcp("simulator", "record-video", simulatorId=simulator["simulatorId"], start=True, fps=15)
        recording = True
        capture = checkpoint("home", label="Home", role="tab")
        tap(capture, label="Add a gift", role="button")
        capture = checkpoint("add-gift-compact", identifier="add-gift.name")
        type_text(capture, "CI acceptance book", identifier="add-gift.name")
        capture = wait(predicate="exists", identifier="add-gift.details")
        tap(capture, identifier="add-gift.details")
        capture = checkpoint("add-gift-details", identifier="add-gift.value")
        type_text(capture, "42", identifier="add-gift.value")
        capture = wait(predicate="exists", identifier="add-gift.scroll")
        swipe(capture, "up", identifier="add-gift.scroll")
        capture = checkpoint("add-gift-value-scrolled", identifier="add-gift.save")

        # Exercise calendar paging in both directions, then dismiss through a real date choice.
        tap(capture, identifier="add-gift.date")
        capture = checkpoint("calendar-short-month", identifier="date-picker.calendar")
        swipe(capture, "left", identifier="date-picker.calendar")
        capture = checkpoint("calendar-long-month", identifier="date-picker.calendar")
        swipe(capture, "right", identifier="date-picker.calendar")
        capture = wait(predicate="exists", identifier="date-picker.today")
        tap(capture, identifier="date-picker.today")
        capture = checkpoint("details-after-calendar", identifier="add-gift.save")

        # Create both endpoints.  Creating a person immediately selects it and closes its picker.
        tap(capture, identifier="add-gift.from")
        capture = wait(predicate="exists", identifier="person-picker.query")
        type_text(capture, "CI Giver", identifier="person-picker.query")
        capture = wait(predicate="exists", identifier="person-picker.add")
        tap(capture, identifier="person-picker.add")
        capture = wait(predicate="exists", identifier="add-gift.to")
        tap(capture, identifier="add-gift.to")
        capture = wait(predicate="exists", identifier="person-picker.query")
        type_text(capture, "CI Receiver", identifier="person-picker.query")
        capture = wait(predicate="exists", identifier="person-picker.add")
        tap(capture, identifier="person-picker.add")
        capture = checkpoint("add-gift-endpoints", identifier="add-gift.save")
        tap(capture, identifier="add-gift.save")
        capture = checkpoint("saved-gift", label="CI acceptance book")

        # Relaunch proves SwiftData persistence and gives the recording a complete product journey.
        mcp("simulator", "stop", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat")
        mcp("simulator", "launch-app", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat",
            env={"KS_START": "app", "KS_TAB": "home"})
        capture = checkpoint("relaunch-persistence", label="CI acceptance book")

        # Reuse the created people in a second draft rather than creating duplicates.
        tap(capture, label="Add a gift", role="button")
        capture = wait(predicate="exists", identifier="add-gift.name")
        type_text(capture, "CI duplicate reuse", identifier="add-gift.name")
        tap(capture, identifier="add-gift.from")
        capture = wait(predicate="exists", label="CI Giver", role="button")
        first_person = element(capture, label="CI Giver", role="button")
        mcp("ui-automation", "batch", simulatorId=simulator["simulatorId"],
            steps=[{"action": "tap", "elementRef": first_person["ref"]}])
        capture = wait(predicate="exists", identifier="add-gift.to")
        tap(capture, identifier="add-gift.to")
        capture = wait(predicate="exists", label="CI Receiver", role="button")
        second_person = element(capture, label="CI Receiver", role="button")
        mcp("ui-automation", "batch", simulatorId=simulator["simulatorId"],
            steps=[{"action": "tap", "elementRef": second_person["ref"]}])
        capture = checkpoint("duplicate-person-reuse", identifier="add-gift.save")
        tap(capture, identifier="add-gift.save")
        capture = wait(predicate="exists", label="Home", role="tab")

        # Settings: currency navigation works and the bundled license content is present.
        capture = wait(predicate="exists", label="Settings", role="button")
        tap(capture, label="Settings", role="button")
        capture = checkpoint("settings", identifier="settings.screen")
        tap(capture, identifier="settings.currency")
        capture = wait(predicate="exists", identifier="settings.currency.USD")
        tap(capture, identifier="settings.currency.USD")
        # Currency selection persists in place; use the native navigation back button.
        capture = wait(predicate="exists", label="Settings", role="button")
        tap(capture, label="Settings", role="button")
        capture = wait(predicate="exists", identifier="settings.screen")
        tap(capture, identifier="settings.third-party-licenses")
        checkpoint("licenses", identifier="settings.third-party-licenses.screen")
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
    run(parser.parse_args().directory)
