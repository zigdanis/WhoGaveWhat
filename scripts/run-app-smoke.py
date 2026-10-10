#!/usr/bin/env python3
"""Run and record the native app smoke journey with Apple's Xcode tools."""
import argparse
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path


class NativeCommandError(ValueError):
    """An Apple tool failed or exceeded its bounded timeout."""


PLANNED_CHECKPOINT_NAMES = (
    "home-start", "people", "people-populated", "insights", "gift-compact-keyboard", "gift-compact-dismissed",
    "details-value", "gift-saved", "gift-after-relaunch", "settings-currency", "licenses",
    "calendar-reverse", "gift-content-sized-compact-keyboard", "gift-content-sized-details",
    "gift-content-sized-details-keyboard", "gift-content-sized-refocused-compact-keyboard",
    "person-add-cancel-draft", "person-add-created", "person-editor-delete-keyboard",
    "person-editor-delete-confirmation", "person-editor-delete-cancelled", "person-add-deleted",
    "person-editor", "person-editor-photo", "person-detail", "person-editor-keyboard",
    "person-editor-header-accessibility", "person-editor-header-accessibility-keyboard",
    "person-editor-russian", "person-editor-russian-keyboard", "person-photo-picker",
    "person-photo-crop", "person-editor-crop-cancelled", "person-photo-crop-adjusted",
    "person-editor-photo-keyboard", "person-editor-selected-photo", "person-detail-selected-photo",
    "person-editor-photo-persisted", "person-photo-replacement-crop",
    "person-editor-existing-photo-crop-cancelled", "person-editor-photo-removed",
    "person-editor-photo-removal-persisted",
)
APP_DISCOVERY_CHECKPOINT_NAMES = (
    "home-screen-english", "system-settings", "language-region-before",
    "english-system-russian-secondary", "settings-apps-list", "settings-search-app",
    "app-settings-before", "app-language-picker", "app-language-russian",
    "home-screen-russian-app", "russian-app-home", "spotlight-draft-before",
    "spotlight-russian", "spotlight-russian-opened", "spotlight-english", "spotlight-english-opened",
    "spotlight-navigation-result", "spotlight-navigation-preserved", "spotlight-draft-cancelled",
    "spotlight-cold-launch", "spotlight-cold-onboarding",
)
GENERATED_LOG_LABELS = (
    "simulator-list", "simulator-boot", "simulator-bootstatus", "record-video",
    "record-video-stop", "xcodebuild-test", "export-attachments", "bundle-info", "bundle-names-en", "bundle-names-ru",
    "language-shutdown", "language-preferences-before", "language-preferences-languages", "language-preferences-locale",
    "language-preferences-after", "language-boot", "language-bootstatus", "language-device-state",
    "app-discovery-index-log", "spotlight-pipeline-log",
    "simulator-signing-info", "simulator-signing-display", "simulator-signing-verify",
)
COLD_BOOT_TIMEOUT_SECONDS = 600
LANGUAGE_SHUTDOWN_TIMEOUT_SECONDS = 180


def clear_previous_outputs(directory):
    """Remove only this runner's fixed-name products before reusing its output folder."""
    for name in ("Acceptance.xcresult", "DerivedData", "attachments"):
        path = directory / name
        if path.is_symlink() or (path.exists() and not path.is_dir()):
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
    for name in ("journeys.mp4", "metadata.json", "index.html"):
        path = directory / name
        if path.is_symlink() or path.exists():
            path.unlink()
    for label in GENERATED_LOG_LABELS:
        for suffix in (".log", "-processes.log"):
            path = directory / f"{label}{suffix}"
            if path.is_symlink() or path.exists():
                path.unlink()


def _diagnose_processes(directory, label):
    try:
        process = subprocess.run(["ps", "-Ao", "pid,ppid,stat,etime,command"],
                                 text=True, capture_output=True, timeout=10)
        (directory / f"{label}-processes.log").write_text(process.stdout + process.stderr)
    except (OSError, subprocess.SubprocessError) as error:
        (directory / f"{label}-processes.log").write_text(f"Could not collect process list: {error}\n")


def _captured_text(value):
    if value is None:
        return ""
    return value.decode(errors="replace") if isinstance(value, bytes) else value


def _signal_process_group(process, sig, cleanup_notes):
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        return
    except OSError as error:
        cleanup_notes.append(f"process-group signal {sig} failed: {error}")
        try:
            if sig == signal.SIGTERM:
                process.terminate()
            else:
                process.kill()
        except OSError as fallback_error:
            cleanup_notes.append(f"direct process signal {sig} failed: {fallback_error}")


def run_command(directory, label, command, timeout, *, cwd=None):
    """Run a bounded command and always preserve stdout, stderr, and failure context."""
    print(f"[{label}] {' '.join(map(str, command))}", flush=True)
    try:
        process = subprocess.Popen(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        (directory / f"{label}.log").write_text(f"Could not start command: {error}\n")
        _diagnose_processes(directory, label)
        raise NativeCommandError(f"{label} could not start: {error}") from error
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        # Bound each cleanup step: child processes can inherit pipes after xcodebuild
        # exits, and a denied group signal must not hide the original timeout.
        cleanup_notes = []
        stdout = _captured_text(error.stdout)
        stderr = _captured_text(error.stderr)
        _signal_process_group(process, signal.SIGTERM, cleanup_notes)
        try:
            collected_stdout, collected_stderr = process.communicate(timeout=5)
            stdout = _captured_text(collected_stdout) or stdout
            stderr = _captured_text(collected_stderr) or stderr
        except subprocess.TimeoutExpired as cleanup_error:
            stdout = _captured_text(cleanup_error.stdout) or stdout
            stderr = _captured_text(cleanup_error.stderr) or stderr
            _signal_process_group(process, signal.SIGKILL, cleanup_notes)
            try:
                process.wait(timeout=5)
            except (subprocess.TimeoutExpired, OSError) as wait_error:
                cleanup_notes.append(f"bounded process wait failed: {wait_error}")
            try:
                collected_stdout, collected_stderr = process.communicate(timeout=2)
                stdout = _captured_text(collected_stdout) or stdout
                stderr = _captured_text(collected_stderr) or stderr
            except subprocess.TimeoutExpired as pipe_error:
                stdout = _captured_text(pipe_error.stdout) or stdout
                stderr = _captured_text(pipe_error.stderr) or stderr
                cleanup_notes.append("inherited output pipes remained open after process cleanup")
                for stream_name in ("stdout", "stderr"):
                    stream = getattr(process, stream_name, None)
                    if stream:
                        try:
                            stream.close()
                        except OSError as close_error:
                            cleanup_notes.append(f"closing {stream_name} pipe failed: {close_error}")
        except OSError as cleanup_error:
            cleanup_notes.append(f"bounded process communication failed: {cleanup_error}")
            _signal_process_group(process, signal.SIGKILL, cleanup_notes)
            try:
                process.wait(timeout=5)
            except (subprocess.TimeoutExpired, OSError) as wait_error:
                cleanup_notes.append(f"bounded process wait failed: {wait_error}")
            for stream_name in ("stdout", "stderr"):
                stream = getattr(process, stream_name, None)
                if stream:
                    try:
                        stream.close()
                    except OSError as close_error:
                        cleanup_notes.append(f"closing {stream_name} pipe failed: {close_error}")
        log_text = f"STDOUT\n{stdout}\nSTDERR\n{stderr}\nTIMEOUT\n{timeout}s\n"
        if cleanup_notes:
            log_text += "CLEANUP\n" + "\n".join(cleanup_notes) + "\n"
        try:
            (directory / f"{label}.log").write_text(log_text)
        except OSError:
            pass
        try:
            _diagnose_processes(directory, label)
        except OSError as diagnostic_error:
            cleanup_notes.append(f"process diagnostics failed: {diagnostic_error}")
        raise NativeCommandError(f"{label} timed out after {timeout}s") from error
    (directory / f"{label}.log").write_text(f"STDOUT\n{stdout}\nSTDERR\n{stderr}\n")
    if process.returncode:
        _diagnose_processes(directory, label)
        raise NativeCommandError(f"{label} exited {process.returncode}: {stderr.strip() or stdout.strip()}")
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def _runtime_version(runtime):
    match = re.search(r"iOS[- ]?(\d+)[-_ .](\d+)", runtime, re.IGNORECASE)
    return tuple(map(int, match.groups())) if match else (0,)


def select_simulator(payload):
    """Prefer any already booted iPhone; otherwise choose newest iPhone 17 Pro."""
    devices = []
    for runtime, runtime_devices in payload.get("devices", {}).items():
        runtime_name = runtime.replace("com.apple.CoreSimulator.SimRuntime.", "")
        runtime_name = re.sub(r"^iOS-(\d+)-(\d+)$", r"iOS \1.\2", runtime_name)
        for device in runtime_devices:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                devices.append({**device, "runtime": runtime_name})
    booted = [device for device in devices if device.get("state") == "Booted"]
    candidates = booted or [device for device in devices if device.get("name") == "iPhone 17 Pro"]
    if not candidates:
        raise ValueError("No available booted iPhone or iPhone 17 Pro Simulator was found")
    return max(candidates, key=lambda device: _runtime_version(device["runtime"]))


def start_recording(directory, simulator_id, video_path):
    """Start simctl recording and return its process and open diagnostic log."""
    log = (directory / "record-video.log").open("w")
    command = ["xcrun", "simctl", "io", simulator_id, "recordVideo", "--codec=h264", str(video_path)]
    try:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, text=True)
    except BaseException:
        log.close()
        raise
    time.sleep(1)
    if process.poll() is not None:
        log.close()
        _diagnose_processes(directory, "record-video")
        raise NativeCommandError(f"simctl recordVideo exited early with status {process.returncode}")
    return process, log


def stop_recording(directory, recording, timeout=30):
    """Stop simctl with SIGINT so it finalizes the MP4, then bound cleanup."""
    process, log = recording
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            _diagnose_processes(directory, "record-video-stop")
            log.close()
            raise NativeCommandError("simctl recordVideo did not stop after SIGINT")
    log.close()
    if process.returncode not in (0, -signal.SIGINT, 130):
        raise NativeCommandError(f"simctl recordVideo exited with status {process.returncode}")


def _export_xcresult_attachments(result_bundle, attachments, directory):
    attachments.mkdir(parents=True, exist_ok=True)
    return run_command(directory, "export-attachments", [
        "xcrun", "xcresulttool", "export", "attachments", "--path", str(result_bundle),
        "--output-path", str(attachments)], 300)


def _export_named_checkpoints(directory, metadata):
    attachments = directory / "attachments"
    manifest_path = attachments / "manifest.json"
    attachment_names = {}
    if manifest_path.is_file():
        for test in json.loads(manifest_path.read_text()):
            for attachment in test.get("attachments", []):
                filename = attachment.get("exportedFileName", "")
                human_name = attachment.get("suggestedHumanReadableName", "")
                if filename.lower().endswith(".png") and human_name:
                    attachment_names[human_name] = filename
    else:
        metadata["export_error"] = "xcresult attachment manifest.json is missing"
    for planned in metadata["planned_checkpoint_names"]:
        matches = [filename for name, filename in attachment_names.items()
                   if re.search(re.escape(planned.lower()) + r"(?=$|[^a-z0-9-])", name.lower())]
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
    if metadata.get("evidence_kind") != "diagnostic" and len(calendar_counts) < 2:
        missing.append("two calendar checkpoints with distinct week counts")
    if missing:
        metadata["missing_checkpoints"] = missing
    return missing


def verify_built_simulator_identity(directory, metadata):
    """Require the actual app's valid ad hoc signature to identify its own bundle."""
    bundle = directory / "DerivedData/Build/Products/Debug-iphonesimulator/WhoGaveWhat.app"
    identity = {"verified": False}
    metadata["simulator_signing"] = identity
    output = run_command(directory, "simulator-signing-info", [
        "plutil", "-convert", "xml1", "-o", "-", str(bundle / "Info.plist")], 30)
    bundle_id = plistlib.loads(output.stdout.encode()).get("CFBundleIdentifier")
    identity["bundle_identifier"] = bundle_id
    output = run_command(directory, "simulator-signing-display", [
        "codesign", "--display", "--verbose=4", str(bundle)], 30)
    description = output.stdout + "\n" + output.stderr
    identifiers = re.findall(r"^Identifier=(.*)$", description, re.MULTILINE)
    signatures = re.findall(r"^Signature=(.*)$", description, re.MULTILINE)
    identity["signing_identifier"] = identifiers[0].strip() if len(identifiers) == 1 else None
    identity["signature"] = signatures[0].strip() if len(signatures) == 1 else None
    run_command(directory, "simulator-signing-verify", [
        "codesign", "--verify", "--strict", "--verbose=4", str(bundle)], 30)
    if not isinstance(bundle_id, str) or not bundle_id or identity["signing_identifier"] != bundle_id:
        raise ValueError("Built Simulator app signing identifier does not match its CFBundleIdentifier")
    if identity["signature"] != "adhoc":
        raise ValueError("Built Simulator app does not have the requested ad hoc signature")
    identity["verified"] = True


def verify_built_app_names(directory, metadata):
    """Check the compiled resources, not only the source strings and build settings."""
    bundle = directory / "DerivedData/Build/Products/Debug-iphonesimulator/WhoGaveWhat.app"
    names = {}
    for language, expected in (("en", "Who Gave"), ("ru", "кто че")):
        output = run_command(directory, f"bundle-names-{language}", [
            "plutil", "-convert", "xml1", "-o", "-", str(bundle / f"{language}.lproj/InfoPlist.strings")], 30)
        info = plistlib.loads(output.stdout.encode())
        if any(info.get(key) != expected for key in ("CFBundleDisplayName", "CFBundleName")):
            raise ValueError(f"Built {language} app names do not match {expected!r}")
        names[language] = expected
    output = run_command(directory, "bundle-info", [
        "plutil", "-convert", "xml1", "-o", "-", str(bundle / "Info.plist")], 30)
    if plistlib.loads(output.stdout.encode()).get("NSUserActivityTypes") != ["com.apple.corespotlightitem"]:
        raise ValueError("Built app does not declare its Spotlight activity type")
    metadata["bundle_names"] = names


def prepare_disposable_languages(directory, simulator, metadata):
    """Prepare preferred languages while the disposable device is off, before XCTest exists.

    Changing the system language list through Settings terminates the running test
    runner on iOS 26. The journey still selects the app's language through real Settings.
    """
    simulator_id = simulator["udid"]
    data_path = Path(simulator.get("dataPath") or (
        Path.home() / "Library/Developer/CoreSimulator/Devices" / simulator_id / "data"))
    preferences = data_path / "Library/Preferences/.GlobalPreferences.plist"
    desired = {"AppleLanguages": ["en-US", "ru-RU"], "AppleLocale": "en_US"}
    metadata["language_preparation"] = {"preferred_languages": desired["AppleLanguages"],
                                        "locale": desired["AppleLocale"], "verified": False}
    if simulator.get("state") != "Shutdown":
        run_command(directory, "language-shutdown", ["xcrun", "simctl", "shutdown", simulator_id],
                    LANGUAGE_SHUTDOWN_TIMEOUT_SECONDS)
    listing = run_command(directory, "language-device-state", ["xcrun", "simctl", "list", "devices", "--json"], 30)
    current = [device for devices in json.loads(listing.stdout).get("devices", {}).values()
               for device in devices if device.get("udid") == simulator_id]
    if len(current) != 1 or current[0].get("state") != "Shutdown":
        raise ValueError("Selected Simulator must be shut down before writing its language preferences")
    if not data_path.is_dir():
        raise ValueError("Selected Simulator data directory is unavailable")
    if not preferences.exists():
        # An unbooted device can lack this user preference file. Create only an
        # empty dictionary, exclusively, so an existing file can never be replaced.
        preferences.parent.mkdir(parents=True, exist_ok=True)
        with preferences.open("xb") as fresh:
            fresh.write(plistlib.dumps({}))
        metadata["language_preparation"]["initialized_preferences"] = True
    before = run_command(directory, "language-preferences-before", [
        "plutil", "-convert", "xml1", "-o", "-", str(preferences)], 30)
    original = plistlib.loads(before.stdout.encode())
    for key, value, label in (("AppleLanguages", desired["AppleLanguages"], "languages"),
                              ("AppleLocale", desired["AppleLocale"], "locale")):
        operation = "-replace" if key in original else "-insert"
        run_command(directory, f"language-preferences-{label}", [
            "plutil", operation, key, "-json", json.dumps(value), str(preferences)], 30)
    after = run_command(directory, "language-preferences-after", [
        "plutil", "-convert", "xml1", "-o", "-", str(preferences)], 30)
    prepared = plistlib.loads(after.stdout.encode())
    expected = {**original, **desired}
    if prepared != expected:
        raise ValueError("Simulator language preparation did not preserve its other preferences")
    run_command(directory, "language-boot", ["xcrun", "simctl", "boot", simulator_id], 60)
    run_command(directory, "language-bootstatus", ["xcrun", "simctl", "bootstatus", simulator_id, "-b"],
                COLD_BOOT_TIMEOUT_SECONDS)
    metadata["language_preparation"]["verified"] = True


def run(directory, verify_app_names=False, discovery_only=False):
    """Run the native XCTest journey, preserving diagnostics and real evidence."""
    if discovery_only and not verify_app_names:
        raise ValueError("Discovery-only diagnostics require --verify-app-names")
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    clear_previous_outputs(directory)
    head_sha = os.environ.get("HEAD_SHA") or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    metadata = {
        "head_sha": head_sha, "checkout_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "evidence_kind": "feature-acceptance",
        "scenario": "Native People disclosure and detail navigation plus grouped person editing, photo crop cancel and confirm, and photo persistence and removal",
        "journey_outcome": "failure", "export_outcome": "failure", "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"),
        "checkpoints": [], "native_test": "WhoGaveWhat scheme complete test suite (unit and UI tests)",
        "planned_checkpoint_names": list(PLANNED_CHECKPOINT_NAMES),
    }
    if verify_app_names:
        metadata["planned_checkpoint_names"].extend(APP_DISCOVERY_CHECKPOINT_NAMES)
        metadata["scenario"] += (
            "; English system with Russian app language selected in Settings; real Russian and English Spotlight"
            " launcher results preserve the gift draft and navigation, then cold launch preserves onboarding")
        metadata["app_discovery_queries"] = ["кто че", "Who Gave"]
    if discovery_only:
        metadata.update(
            evidence_kind="diagnostic",
            native_test="AppDiscoveryUITests only (partial suite; not acceptance)",
            scenario="Spotlight diagnostic: real Settings language selection and bilingual launcher searches",
            planned_checkpoint_names=list(APP_DISCOVERY_CHECKPOINT_NAMES))
    simulator = None
    recording = None
    result_bundle = directory / "Acceptance.xcresult"
    test_succeeded = False
    native_test_attempted = False
    try:
        listing = run_command(directory, "simulator-list", ["xcrun", "simctl", "list", "devices", "available", "--json"], 30)
        simulator = select_simulator(json.loads(listing.stdout))
        simulator_id = simulator["udid"]
        metadata.update(device=simulator["name"], simulator_id=simulator_id, runtime=simulator["runtime"])
        if verify_app_names:
            prepare_disposable_languages(directory, simulator, metadata)
        else:
            if simulator.get("state") != "Booted":
                run_command(directory, "simulator-boot", ["xcrun", "simctl", "boot", simulator_id], 60)
            run_command(directory, "simulator-bootstatus", ["xcrun", "simctl", "bootstatus", simulator_id, "-b"],
                        COLD_BOOT_TIMEOUT_SECONDS)
        recording = start_recording(directory, simulator_id, directory / "journeys.mp4")
        command = ["xcodebuild", "test", "-project", "WhoGaveWhat.xcodeproj", "-scheme", "WhoGaveWhat",
                   "-destination", f"platform=iOS Simulator,id={simulator_id}", "-derivedDataPath", str(directory / "DerivedData"),
                   "-resultBundlePath", str(result_bundle), "-parallel-testing-enabled", "NO",
                   "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
        if not verify_app_names:
            command.append("-skip-testing:WhoGaveWhatUITests/AppDiscoveryUITests")
        if discovery_only:
            command.append("-only-testing:WhoGaveWhatUITests/AppDiscoveryUITests")
        try:
            native_test_attempted = True
            run_command(directory, "xcodebuild-test", command, 900 if discovery_only else 1800)
            if verify_app_names:
                verify_built_app_names(directory, metadata)
            test_succeeded = True
        except (NativeCommandError, OSError) as error:
            metadata["native_test_error"] = str(error)
            raise
    except (NativeCommandError, OSError, ValueError, json.JSONDecodeError) as error:
        metadata.setdefault("native_test_error", str(error))
        raise
    finally:
        if recording:
            try:
                stop_recording(directory, recording)
            except (NativeCommandError, OSError, subprocess.SubprocessError) as error:
                metadata["recording_error"] = str(error)
        if native_test_attempted:
            try:
                verify_built_simulator_identity(directory, metadata)
            except (ValueError, OSError, subprocess.SubprocessError, plistlib.InvalidFileException) as error:
                metadata["simulator_identity_error"] = str(error)
                test_succeeded = False
        if verify_app_names and simulator:
            try:
                run_command(directory, "app-discovery-index-log", [
                    "xcrun", "simctl", "spawn", simulator["udid"], "log", "show", "--last", "20m",
                    "--info", "--style", "compact", "--predicate",
                    'subsystem == "pro.ziganshin.WhoGaveWhat" AND category == "AppDiscovery"'], 30)
            except (NativeCommandError, OSError, subprocess.SubprocessError) as error:
                # This diagnostic must never replace the native test failure or its evidence.
                metadata["app_discovery_diagnostic_error"] = str(error)
            try:
                run_command(directory, "spotlight-pipeline-log", [
                    "xcrun", "simctl", "spawn", simulator["udid"], "log", "show", "--last", "20m",
                    "--info", "--style", "compact", "--predicate",
                    '(process == "corespotlightd" OR process == "Spotlight" OR subsystem CONTAINS[c] "spotlight") '
                    'AND (eventMessage CONTAINS[c] "pro.ziganshin.WhoGaveWhat" OR messageType == 16 OR messageType == 17)'], 30)
            except (NativeCommandError, OSError, subprocess.SubprocessError) as error:
                metadata["spotlight_pipeline_diagnostic_error"] = str(error)
        if result_bundle.is_dir():
            try:
                _export_xcresult_attachments(result_bundle, directory / "attachments", directory)
            except (NativeCommandError, OSError, subprocess.SubprocessError) as error:
                metadata["export_error"] = str(error)
        missing = _export_named_checkpoints(directory, metadata) if (directory / "attachments").exists() else metadata["planned_checkpoint_names"]
        if missing:
            metadata["missing_checkpoints"] = missing
        if test_succeeded:
            metadata["journey_outcome"] = "success"
        video = directory / "journeys.mp4"
        if (test_succeeded and not missing and not metadata.get("export_error") and not metadata.get("recording_error")
                and video.is_file() and video.stat().st_size):
            metadata["export_outcome"] = "success"
        (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        shutil.rmtree(directory / "DerivedData", ignore_errors=True)
    if metadata["export_outcome"] != "success":
        raise ValueError(metadata.get("simulator_identity_error") or "Native acceptance evidence export is incomplete")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--verify-app-names", action="store_true",
                        help="Exercise real Settings language selection and Spotlight on a disposable Simulator")
    parser.add_argument("--discovery-only", action="store_true",
                        help="Run only AppDiscoveryUITests and mark partial evidence as diagnostic, never acceptance")
    args = parser.parse_args()
    run(args.directory, args.verify_app_names, args.discovery_only)
