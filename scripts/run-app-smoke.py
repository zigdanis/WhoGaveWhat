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
        invocation = ["xcodebuildmcp", workflow, command, "--json", json.dumps(parameters),
                      "--output", "json", "--verbose"]
        process = subprocess.run(invocation, text=True, capture_output=True, timeout=1800)
        (directory / f"{sequence:02d}-{command}.json").write_text(process.stdout)
        (directory / f"{sequence:02d}-{command}.log").write_text(process.stderr)
        return checked_output(process)

    def wait(**predicate):
        return mcp("ui-automation", "wait-for-ui", simulatorId=simulator["simulatorId"],
                   timeoutMs=20000, **predicate)["capture"]

    def checkpoint(name):
        wait(predicate="settled", settledDurationMs=800)
        capture = mcp("ui-automation", "snapshot-ui", simulatorId=simulator["simulatorId"])["capture"]
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
        checkpoint("home")
        for label in ["People", "Insights"]:
            capture = mcp("ui-automation", "snapshot-ui", simulatorId=simulator["simulatorId"])["capture"]
            mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"], elementRef=target(capture, label, "tab"))
            wait(predicate="exists", label=label, role="text")
            checkpoint(label.lower())
        capture = mcp("ui-automation", "snapshot-ui", simulatorId=simulator["simulatorId"])["capture"]
        mcp("ui-automation", "tap", simulatorId=simulator["simulatorId"], elementRef=target(capture, "Add a gift", "button"))
        wait(predicate="exists", identifier="add-gift.name")
        checkpoint("add-gift")
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
