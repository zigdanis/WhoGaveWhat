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
        wait(predicate="exists", label="Add a gift", role="button")
        mcp("simulator", "record-video", simulatorId=simulator["simulatorId"], start=True, fps=15)
        recording = True
        capture = checkpoint("home", label="Home", role="tab")
        # A singleton MCP batch uses the current ref activation point without an AX label re-query.
        for label in ["People", "Insights"]:
            mcp("ui-automation", "batch", simulatorId=simulator["simulatorId"],
                steps=[{"action": "tap", "elementRef": target(capture, label, "tab")}])
            wait(predicate="exists", identifier=label, role="other")
            capture = checkpoint(label.lower(), label=label, role="tab")
            assert_tab_screen(capture, label)
        mcp("ui-automation", "batch", simulatorId=simulator["simulatorId"],
            steps=[{"action": "tap", "elementRef": target(capture, "Add a gift", "button")}])
        wait(predicate="exists", identifier="add-gift.name")
        checkpoint("add-gift", identifier="add-gift.name")
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
