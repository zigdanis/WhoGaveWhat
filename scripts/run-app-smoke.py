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


class MCPInvocationError(ValueError):
    def __init__(self, message, *, code=None, payload=None):
        super().__init__(message)
        self.code = code
        self.payload = payload


def checked_output(process):
    payload = json.loads(process.stdout)
    result = payload.get("result", payload)
    if (process.returncode or payload.get("isError") or result.get("didError") is not False):
        data = result.get("data", {}) if isinstance(result, dict) else {}
        code = data.get("code") or data.get("uiError", {}).get("code")
        raise MCPInvocationError(
            f"XcodeBuildMCP failed: {result.get('error') or process.stderr or process.stdout}",
            code=code, payload=payload)
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
            retryable_read_transport = False
            try:
                payload = json.loads(process.stdout)
                result = payload.get("result", payload)
                data = result.get("data", {})
                retryable_read_transport = (
                    workflow == "ui-automation"
                    and command == "wait-for-ui"
                    and data.get("code") == "DAEMON_TRANSPORT_FAILED"
                    and "Daemon request timed out after 30000ms" in str(result.get("error", "")))
            except (ValueError, AttributeError, TypeError):
                pass
            if attempt or retryable_read_transport:
                if retryable_read_transport and attempt == 0:
                    continue
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


def ensure_daemon(directory, timeout=90, command_runner=subprocess.run, sleeper=time.sleep):
    """Start xcodebuildmcp once and wait for the current workspace daemon."""
    directory = directory.resolve()
    workspace = Path.cwd().resolve()
    start = command_runner(
        ["xcodebuildmcp", "daemon", "start", "--style", "minimal"],
        cwd=str(workspace), text=True, capture_output=True, timeout=30)
    (directory / "daemon-start.log").write_text(start.stdout + start.stderr)
    deadline = time.monotonic() + timeout
    last_output = ""
    while time.monotonic() < deadline:
        status = command_runner(
            ["xcodebuildmcp", "daemon", "list", "--json", "--all"],
            cwd=str(workspace), text=True, capture_output=True, timeout=30)
        last_output = status.stdout + status.stderr
        try:
            daemons = json.loads(status.stdout)
        except (ValueError, TypeError):
            daemons = []
        if any(str(item.get("workspaceRoot", "")) == str(workspace)
               and item.get("status") == "running"
               for item in daemons if isinstance(item, dict)):
            return
        sleeper(1)
    (directory / "daemon-list-timeout.log").write_text(last_output)
    raise ValueError(f"xcodebuildmcp daemon did not become ready for {workspace}")


def _export_xcresult_attachments(result_bundle, attachments):
    attachments.mkdir(parents=True, exist_ok=True)
    process = subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments", "--path", str(result_bundle),
         "--output-path", str(attachments)],
        text=True, capture_output=True, timeout=300)
    if process.returncode:
        raise ValueError(f"xcresult attachment export failed: {process.stderr or process.stdout}")
    return process


def run(directory):
    """Run the native XCTest acceptance journey and export its real evidence."""
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    attachments = directory / "attachments"
    metadata = {
        "head_sha": os.environ.get("HEAD_SHA", subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()),
        "checkout_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "evidence_kind": "feature-acceptance",
        "scenario": "Native XCTest PR13 feature acceptance journey",
        "journey_outcome": "failure", "export_outcome": "failure",
        "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"), "mcp": "2.7.0",
        "checkpoints": [], "native_test": "WhoGaveWhatUITests/AdaptiveGiftJourneyUITests/testAdaptiveGiftJourney",
        "planned_checkpoint_names": [
            "home-start", "people", "insights", "gift-compact-keyboard", "details-value",
            "gift-saved", "gift-after-relaunch",
            "settings-currency", "licenses", "calendar-reverse",
        ],
    }
    simulator = None
    recording = False
    test_succeeded = False
    result_bundle = None
    try:
        ensure_daemon(directory)
        simulator = select_simulator(invoke_mcp(directory, 1, "simulator", "list", {"enabled": True})["simulators"])
        metadata.update(device=simulator["name"], runtime=simulator["runtime"])
        invoke_mcp(directory, 2, "simulator", "boot", {"simulatorId": simulator["simulatorId"]})
        invoke_mcp(directory, 3, "simulator", "record-video", {
            "simulatorId": simulator["simulatorId"], "start": True, "fps": 15})
        recording = True
        try:
            test_result = invoke_mcp(directory, 4, "simulator", "test", {
                "projectPath": "WhoGaveWhat.xcodeproj", "scheme": "WhoGaveWhat",
                "simulatorId": simulator["simulatorId"],
                "derivedDataPath": str(directory / "DerivedData"),
                "extraArgs": ["CODE_SIGNING_ALLOWED=NO", "-parallel-testing-enabled", "NO"]})
            artifact = test_result.get("artifacts", {}).get("xcresultPath") or test_result.get("artifacts", {}).get("resultBundlePath")
            if not artifact:
                raise ValueError(f"XcodeBuildMCP did not return a result bundle path: {test_result}")
            result_bundle = Path(os.path.expanduser(artifact))
            test_succeeded = True
        except MCPInvocationError as error:
            metadata["native_test_error"] = str(error)
            payload = error.payload or {}
            result = payload.get("result", payload)
            artifacts = result.get("data", {}).get("artifacts", {})
            artifact = artifacts.get("xcresultPath") or artifacts.get("resultBundlePath")
            if artifact:
                result_bundle = Path(os.path.expanduser(artifact))
            raise
    finally:
        if recording and simulator:
            try:
                invoke_mcp(directory, 5, "simulator", "record-video", {
                    "simulatorId": simulator["simulatorId"], "stop": True,
                    "outputFile": str(directory / "journeys.mp4")})
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                metadata["recording_error"] = str(error)
        if result_bundle and result_bundle.is_dir():
            try:
                local_bundle = directory / "Acceptance.xcresult"
                if result_bundle.resolve() != local_bundle.resolve():
                    shutil.copytree(result_bundle, local_bundle, dirs_exist_ok=True)
                    result_bundle = local_bundle
                _export_xcresult_attachments(result_bundle, attachments)
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                metadata["export_error"] = str(error)
        images = sorted(attachments.glob("*.png"))
        manifest_path = attachments / "manifest.json"
        attachment_names = {}
        if manifest_path.is_file():
            manifest = json.loads(manifest_path.read_text())
            for test in manifest:
                for attachment in test.get("attachments", []):
                    filename = attachment.get("exportedFileName", "")
                    human_name = attachment.get("suggestedHumanReadableName", "")
                    if filename.lower().endswith(".png") and human_name:
                        attachment_names[human_name] = filename
        else:
            metadata["export_error"] = "xcresult attachment manifest.json is missing"
        for planned in metadata["planned_checkpoint_names"]:
            matches = [filename for human_name, filename in attachment_names.items()
                       if re.search(re.escape(planned.lower()) + r"(?=$|[^a-z0-9-])", human_name.lower())]
            if matches and (attachments / matches[0]).is_file() and (attachments / matches[0]).stat().st_size:
                stable = f"{planned}.png"
                if matches[0] != stable:
                    shutil.copy2(attachments / matches[0], attachments / stable)
                metadata["checkpoints"].append({"name": planned, "image": f"attachments/{stable}"})
        calendar_counts = set()
        for human, filename in attachment_names.items():
            match = re.search(r"calendar-([456])-weeks(?=$|[^a-z0-9-])", human.lower())
            source = attachments / filename
            if match and source.is_file() and source.stat().st_size:
                count = match.group(1)
                stable = f"calendar-{count}-weeks.png"
                if filename != stable:
                    shutil.copy2(source, attachments / stable)
                calendar_counts.add(count)
                metadata["checkpoints"].append({"name": f"calendar-{count}-weeks", "image": f"attachments/{stable}"})
        missing = [name for name in metadata["planned_checkpoint_names"]
                   if name not in {checkpoint["name"] for checkpoint in metadata["checkpoints"]}]
        if len(calendar_counts) < 2:
            missing.append("two calendar checkpoints with distinct week counts")
        if missing:
            metadata["missing_checkpoints"] = missing
        video = directory / "journeys.mp4"
        if test_succeeded:
            metadata["journey_outcome"] = "success"
        if test_succeeded and not missing and not metadata.get("export_error") and not metadata.get("recording_error") and video.is_file() and video.stat().st_size:
            metadata["export_outcome"] = "success"
        (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        shutil.rmtree(directory / "DerivedData", ignore_errors=True)
    if metadata["export_outcome"] != "success":
        raise ValueError("Native acceptance evidence export is incomplete")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    run(parser.parse_args().directory)
