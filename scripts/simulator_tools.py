#!/usr/bin/env python3
"""Bounded Apple tool invocations and Simulator fixtures shared by the native scripts."""
import json
import os
import re
import signal
import subprocess
import uuid


class NativeCommandError(ValueError):
    """An Apple tool failed or exceeded its bounded timeout."""


COLD_BOOT_TIMEOUT_SECONDS = 600
# iPhone 17 Pro is the default local Simulator; CI passes an explicit model and runtime.
DEFAULT_DEVICE = "iPhone 17 Pro"
SHUTDOWN_TIMEOUT_SECONDS = 180


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


def _available_iphones(payload):
    devices = []
    for runtime, runtime_devices in payload.get("devices", {}).items():
        runtime_name = runtime.replace("com.apple.CoreSimulator.SimRuntime.", "")
        runtime_name = re.sub(r"^iOS-(\d+)-(\d+)$", r"iOS \1.\2", runtime_name)
        for device in runtime_devices:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                devices.append({**device, "runtime": runtime_name, "runtime_identifier": runtime})
    return devices


def _booted_iphone(devices, requested_runtime, device_name=None):
    """Return the newest booted iPhone, rejecting one that conflicts with an explicit runtime or model."""
    booted = [device for device in devices if device.get("state") == "Booted"]
    if not booted:
        return None
    if device_name is not None:
        matching = [device for device in booted if device.get("name") == device_name]
        if not matching:
            names = ", ".join(sorted({device.get("name", "") for device in booted}))
            raise ValueError(f"Booted iPhone ({names}) is not the requested {device_name}; shut it down first")
        booted = matching
    selected = max(booted, key=lambda device: _runtime_version(device["runtime"]))
    if requested_runtime is not None and selected["runtime"] != requested_runtime:
        raise ValueError(
            f"Booted iPhone {selected['udid']} uses {selected['runtime']}, not requested {requested_runtime}")
    return selected


def select_simulator(payload, requested_runtime=None, device_name=None):
    """Reuse a booted iPhone of the requested model, or of any model when none was requested;
    otherwise select an available Simulator of that model (DEFAULT_DEVICE when none was requested)."""
    devices = _available_iphones(payload)
    booted = _booted_iphone(devices, requested_runtime, device_name)
    if booted:
        return booted
    device_name = device_name or DEFAULT_DEVICE
    candidates = [device for device in devices if device.get("name") == device_name
                  and (requested_runtime is None or device["runtime"] == requested_runtime)]
    if not candidates:
        if requested_runtime is not None:
            raise ValueError(f"No available {device_name} Simulator was found for requested runtime {requested_runtime}")
        raise ValueError(f"No available booted iPhone or {device_name} Simulator was found")
    return max(candidates, key=lambda device: _runtime_version(device["runtime"]))


def create_ci_simulator(directory, payload, requested_runtime, metadata, device_name=DEFAULT_DEVICE):
    """Create one owned fixture of the named model from the device types the exact runtime supports.

    A freshly downloaded runtime may have no default devices, so the model is resolved
    from the runtime itself instead of from an existing Simulator.
    """
    # Retain the existing guard against a conflicting booted iPhone runtime.
    _booted_iphone(_available_iphones(payload), requested_runtime)
    runtimes = run_command(directory, "simulator-runtimes", [
        "xcrun", "simctl", "list", "runtimes", "available", "--json"], 30)
    matching = [runtime for runtime in json.loads(runtimes.stdout).get("runtimes", [])
                if runtime.get("isAvailable") and runtime.get("name") == requested_runtime]
    if len(matching) != 1:
        raise ValueError(f"Expected exactly one available {requested_runtime} runtime, found {len(matching)}")
    runtime = matching[0]
    device_types = [device_type for device_type in runtime.get("supportedDeviceTypes", [])
                    if device_type.get("name") == device_name]
    if (len(device_types) != 1
            or not str(device_types[0].get("identifier", "")).startswith("com.apple.CoreSimulator.SimDeviceType.")):
        raise ValueError(f"{requested_runtime} does not support exactly one {device_name} device type")
    device_type = device_types[0]["identifier"]
    fixture = {"mode": "fresh-ci", "device_name": device_name,
               "device_type_identifier": device_type, "runtime_identifier": runtime["identifier"],
               "runtime_build": runtime.get("buildversion"),
               "name": f"WhoGaveWhat CI {uuid.uuid4()}", "creation_verified": False}
    metadata["simulator_fixture"] = fixture
    output = run_command(directory, "simulator-create", [
        "xcrun", "simctl", "create", fixture["name"], device_type, fixture["runtime_identifier"]], 60)
    try:
        created_id = str(uuid.UUID(output.stdout.strip())).upper()
    except ValueError as error:
        raise ValueError("simctl create did not return a Simulator UDID") from error
    existing_ids = {device.get("udid", "").upper() for devices in payload.get("devices", {}).values()
                    for device in devices}
    if created_id in existing_ids:
        raise ValueError("simctl create returned a pre-existing Simulator; refusing ownership")
    # Record ownership immediately so a later list or preparation failure still cleans up only this device.
    fixture["created_simulator_id"] = created_id
    listing = run_command(directory, "simulator-created-list", [
        "xcrun", "simctl", "list", "devices", "available", "--json"], 30)
    matches = [device for device in json.loads(listing.stdout).get("devices", {}).get(fixture["runtime_identifier"], [])
               if device.get("udid", "").upper() == created_id]
    if (len(matches) != 1 or not matches[0].get("isAvailable") or matches[0].get("state") != "Shutdown"
            or matches[0].get("deviceTypeIdentifier") != device_type or matches[0].get("name") != fixture["name"]):
        raise ValueError(f"Created Simulator does not match the requested fresh {device_name} fixture")
    fixture["creation_verified"] = True
    return {**matches[0], "udid": created_id, "runtime": requested_runtime,
            "runtime_identifier": fixture["runtime_identifier"]}


def cleanup_ci_simulator(directory, metadata):
    """Remove only the Simulator whose creation this invocation recorded."""
    fixture = metadata.get("simulator_fixture", {})
    created_id = fixture.get("created_simulator_id")
    if not created_id:
        return
    fixture["cleanup_outcome"] = "failure"
    try:
        listing = run_command(directory, "simulator-created-state", [
            "xcrun", "simctl", "list", "devices", "--json"], 30)
        matches = [device for devices in json.loads(listing.stdout).get("devices", {}).values()
                   for device in devices if device.get("udid", "").upper() == created_id]
        if len(matches) != 1:
            raise ValueError("Cannot locate the run-owned Simulator for cleanup")
        if matches[0].get("state") != "Shutdown":
            run_command(directory, "simulator-created-shutdown", ["xcrun", "simctl", "shutdown", created_id],
                        SHUTDOWN_TIMEOUT_SECONDS)
        run_command(directory, "simulator-created-delete", ["xcrun", "simctl", "delete", created_id], 60)
        fixture["cleanup_outcome"] = "success"
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        # Preserve the original native result and exported diagnostics on cleanup failure.
        fixture["cleanup_error"] = str(error)


def export_xcresult_attachments(result_bundle, attachments, directory):
    attachments.mkdir(parents=True, exist_ok=True)
    return run_command(directory, "export-attachments", [
        "xcrun", "xcresulttool", "export", "attachments", "--path", str(result_bundle),
        "--output-path", str(attachments)], 300)
