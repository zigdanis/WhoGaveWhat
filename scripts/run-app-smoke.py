#!/usr/bin/env python3
"""Build, test and record an app smoke scenario through XcodeBuildMCP."""
import argparse
import calendar
import json
import os
import re
import shutil
import subprocess
import uuid
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


def target(capture, label, role):
    matches = [e for e in capture["elements"] if e.get("label") == label
               and e.get("role") == role and "tap" in e.get("actions", [])]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one tappable {role} labelled {label!r}; got {len(matches)}")
    return matches[0]["ref"]


def element(capture, *, identifier=None, label=None, role=None):
    """Return one current AX element, using stable identifiers where possible."""
    matches = []
    for candidate in capture.get("elements", []):
        if identifier is not None:
            value = candidate.get("identifier", "")
            if value != identifier:
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


def has_element(capture, *, identifier=None, label=None, role=None):
    try:
        element(capture, identifier=identifier, label=label, role=role)
        return True
    except ValueError:
        return False


def matches_selector(capture, selector):
    return any(all(element.get(key) == value for key, value in selector.items())
               for element in capture.get("elements", []))


def calendar_month(capture):
    """Extract the UIKit calendar's visible month heading from the live AX tree."""
    pattern = re.compile(r"^(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{4}$")
    matches = sorted({e.get("label", "") for e in capture.get("elements", []) if pattern.fullmatch(e.get("label", ""))})
    if len(matches) != 1:
        raise ValueError(f"Expected one visible calendar month heading; got {matches}")
    return matches[0]


def calendar_week_count(month_heading):
    month_name, year_text = month_heading.rsplit(" ", 1)
    month = list(calendar.month_name).index(month_name)
    return len(calendar.Calendar(firstweekday=6).monthdayscalendar(int(year_text), month))


def assert_endpoint(capture, identifier, expected):
    observed = element(capture, identifier=identifier)
    if observed.get("value") != expected:
        raise ValueError(f"{identifier} did not select {expected!r}: {observed}")


def assert_picker_closed(capture, endpoint, expected):
    if any(e.get("identifier", "").startswith("person-picker.") for e in capture.get("elements", [])):
        raise ValueError("Person picker remained visible after Add")
    assert_endpoint(capture, endpoint, expected)


def assert_form_absent(capture):
    if any(e.get("identifier") == "add-gift.name" for e in capture.get("elements", [])):
        raise ValueError("Gift form remained visible after Save")


def assert_currency(capture, expected_code="AUD"):
    observed = element(capture, identifier="settings.currency")
    if observed.get("value") != expected_code:
        raise ValueError(f"Currency selection {expected_code} was not persisted in Settings: {observed}")
    placeholders = {"License information is unavailable.", "Choose", "No value"}
    visible = {str(e.get("label", "")) for e in capture.get("elements", [])}
    unexpected = sorted(placeholders.intersection(visible))
    if unexpected:
        raise ValueError(f"Settings contains placeholder labels: {unexpected}")


def currency_target(initial_code):
    return "AFN" if initial_code == "AUD" else "AUD"


def assert_license_content(capture):
    labels = {str(e.get("label", "")) for e in capture.get("elements", [])}
    if not any("Archivo" in label or "SIL Open Font License" in label for label in labels):
        raise ValueError("Bundled third-party license content is not visible")


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


def entity_names():
    """Return names unique to this invocation, including local simulator runs."""
    run_id = re.sub(r"[^A-Za-z0-9-]", "-", os.environ.get("GITHUB_RUN_ID", "local"))
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
    token = f"{run_id}-{attempt}-{uuid.uuid4().hex[:8]}"
    return {
        "gift": f"CI acceptance book {token}",
        "giver": f"CI Giver {token}",
        "receiver": f"CI Receiver {token}",
        "duplicate": f"CI duplicate reuse {token}",
    }


def run(directory):
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "attachments").mkdir(exist_ok=True)
    metadata = {
        "head_sha": os.environ.get("HEAD_SHA", subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()),
        "checkout_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "evidence_kind": "feature-acceptance", "scenario": "Home → People → Insights → PR13 gift creation and Settings journey",
        "journey_outcome": "failure", "export_outcome": "failure",
        "xcode": os.environ.get("XCODE_VERSION", "selected local Xcode"),
        "mcp": "2.7.0", "checkpoints": [], "calendar_observations": [], "transport_recoveries": [],
        "acceptance_claims": [
            "compact gift title entry and keyboard",
            "expanded Details value entry and scrolling",
            "calendar month paging with observed adjacent month headings and dismissal",
            "new From and To people with automatic selection",
            "duplicate gift reuses existing people",
            "save and relaunch persistence",
            "Settings currency and bundled third-party licenses",
        ],
    }
    names = entity_names()
    gift_name = names["gift"]
    giver_name = names["giver"]
    receiver_name = names["receiver"]
    duplicate_name = names["duplicate"]
    metadata["run_entities"] = names
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
        settled = wait(predicate="settled", settledDurationMs=800)
        capture = settled if matches_selector(settled, readiness) else wait(predicate="exists", **readiness)
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

    def tap(capture, *, expected=None, verify=None, **selector):
        # Screenshots can outlive the AXe ref cache. Resolve every mutation from
        # a fresh settled capture immediately before sending it.
        capture = wait(predicate="settled", settledDurationMs=400)
        ref = element(capture, **selector)["ref"]
        try:
            mcp("ui-automation", "batch", simulatorId=simulator["simulatorId"],
                steps=[{"action": "tap", "elementRef": ref}])
        except ValueError as error:
            text = str(error)
            transport_timeout = (
                isinstance(error, MCPInvocationError)
                and error.code == "DAEMON_TRANSPORT_FAILED"
                and "Daemon request timed out after 30000ms" in text)
            if not transport_timeout or expected is None:
                raise
            recovered = wait(predicate="exists", **expected)
            if verify is not None:
                verify(recovered)
            metadata["transport_recoveries"].append({
                "action": "tap", "selector": selector,
                "postcondition": expected, "error": text,
            })

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
        for label in ["People", "Insights", "Home"]:
            tap(capture, label=label, role="tab",
                expected={"identifier": label, "role": "other"},
                verify=lambda recovered, label=label: assert_tab_screen(recovered, label))
            capture = checkpoint(label.lower(), label=label, role="tab")
            assert_tab_screen(capture, label)
        tap(capture, label="Add a gift", role="button", expected={"identifier": "add-gift.name"})
        capture = checkpoint("add-gift-compact", identifier="add-gift.name")
        type_text(capture, gift_name, identifier="add-gift.name")
        capture = wait(predicate="exists", identifier="add-gift.details")
        tap(capture, identifier="add-gift.details", expected={"identifier": "add-gift.value"})
        capture = checkpoint("add-gift-details", identifier="add-gift.value")
        type_text(capture, "42", identifier="add-gift.value")
        capture = wait(predicate="exists", identifier="add-gift.scroll")
        swipe(capture, "up", identifier="add-gift.scroll")
        capture = checkpoint("add-gift-value-scrolled", identifier="add-gift.save")

        # Exercise calendar paging in both directions, then dismiss through a real date choice.
        tap(capture, identifier="add-gift.date", expected={"identifier": "date-picker.calendar"})
        capture = wait(predicate="exists", identifier="date-picker.calendar")
        short_month = calendar_month(capture)
        short_weeks = calendar_week_count(short_month)
        metadata["calendar_observations"].append({"month": short_month, "week_count": short_weeks})
        capture = checkpoint(f"calendar-{short_month.lower().replace(' ', '-')}", identifier="date-picker.calendar")
        long_month = None
        long_weeks = None
        for _ in range(12):
            swipe(capture, "left", identifier="date-picker.calendar")
            capture = wait(predicate="exists", identifier="date-picker.calendar")
            candidate = calendar_month(capture)
            candidate_weeks = calendar_week_count(candidate)
            if candidate_weeks != short_weeks:
                long_month, long_weeks = candidate, candidate_weeks
                break
        if long_month is None:
            raise ValueError(f"Calendar paging did not reach a different week count from {short_month}")
        metadata["calendar_observations"].append({"month": long_month, "week_count": long_weeks})
        metadata["calendar_navigation_scope"] = "bounded paging to a different Sunday based week count"
        capture = checkpoint(f"calendar-{long_month.lower().replace(' ', '-')}", identifier="date-picker.calendar")
        swipe(capture, "right", identifier="date-picker.calendar")
        capture = wait(predicate="exists", identifier="date-picker.today")
        tap(capture, identifier="date-picker.today", expected={"identifier": "add-gift.save"})
        capture = checkpoint("details-after-calendar", identifier="add-gift.save")

        # Create both endpoints.  Creating a person immediately selects it and closes its picker.
        tap(capture, identifier="add-gift.from", expected={"identifier": "person-picker.query"})
        capture = wait(predicate="exists", identifier="person-picker.query")
        type_text(capture, giver_name, identifier="person-picker.query")
        capture = wait(predicate="exists", identifier="person-picker.add")
        tap(capture, identifier="person-picker.add", expected={"identifier": "add-gift.to"},
            verify=lambda recovered: assert_picker_closed(recovered, "add-gift.from", giver_name))
        capture = wait(predicate="exists", identifier="add-gift.to")
        tap(capture, identifier="add-gift.to", expected={"identifier": "person-picker.query"})
        capture = wait(predicate="exists", identifier="person-picker.query")
        type_text(capture, receiver_name, identifier="person-picker.query")
        capture = wait(predicate="exists", identifier="person-picker.add")
        tap(capture, identifier="person-picker.add", expected={"identifier": "add-gift.save"},
            verify=lambda recovered: assert_picker_closed(recovered, "add-gift.to", receiver_name))
        capture = checkpoint("add-gift-endpoints", identifier="add-gift.save")
        assert_endpoint(capture, "add-gift.from", giver_name)
        assert_endpoint(capture, "add-gift.to", receiver_name)
        tap(capture, identifier="add-gift.save", expected={"label": gift_name}, verify=assert_form_absent)
        capture = checkpoint("saved-gift", label=gift_name)

        # Relaunch proves SwiftData persistence and gives the recording a complete product journey.
        mcp("simulator", "stop", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat")
        mcp("simulator", "launch-app", simulatorId=simulator["simulatorId"], bundleId="pro.ziganshin.WhoGaveWhat",
            env={"KS_START": "app", "KS_TAB": "home"})
        capture = checkpoint("relaunch-persistence", label=gift_name)

        # Call the create callback with the same names. The use case must return
        # existing IDs rather than inserting duplicate people.
        tap(capture, label="Add a gift", role="button", expected={"identifier": "add-gift.name"})
        capture = wait(predicate="exists", identifier="add-gift.name")
        type_text(capture, duplicate_name, identifier="add-gift.name")
        capture = wait(predicate="exists", identifier="add-gift.from")
        tap(capture, identifier="add-gift.from", expected={"identifier": "person-picker.query"})
        capture = wait(predicate="exists", label=giver_name, role="button")
        original_giver_id = element(capture, label=giver_name, role="button").get("identifier")
        type_text(capture, giver_name, identifier="person-picker.query")
        capture = wait(predicate="exists", identifier="person-picker.add")
        tap(capture, identifier="person-picker.add", expected={"identifier": "add-gift.to"},
            verify=lambda recovered: assert_picker_closed(recovered, "add-gift.from", giver_name))
        capture = wait(predicate="exists", identifier="add-gift.to")
        tap(capture, identifier="add-gift.to", expected={"identifier": "person-picker.query"})
        capture = wait(predicate="exists", label=receiver_name, role="button")
        original_receiver_id = element(capture, label=receiver_name, role="button").get("identifier")
        type_text(capture, receiver_name, identifier="person-picker.query")
        capture = wait(predicate="exists", identifier="person-picker.add")
        tap(capture, identifier="person-picker.add", expected={"identifier": "add-gift.save"},
            verify=lambda recovered: assert_picker_closed(recovered, "add-gift.to", receiver_name))
        capture = wait(predicate="exists", identifier="add-gift.save")
        if not original_giver_id or not original_receiver_id:
            raise ValueError("Duplicate-person proof could not read original person identifiers")
        metadata["duplicate_person_ids"] = {"giver": original_giver_id, "receiver": original_receiver_id}
        assert_endpoint(capture, "add-gift.from", giver_name)
        assert_endpoint(capture, "add-gift.to", receiver_name)
        # The selected endpoint remains the original ID after the duplicate Add callback.
        tap(capture, identifier="add-gift.from", expected={"identifier": "person-picker.query"})
        capture = wait(predicate="exists", label=giver_name, role="button")
        if element(capture, label=giver_name, role="button").get("identifier") != original_giver_id:
            raise ValueError("Duplicate From person received a new identifier")
        tap(capture, label=giver_name, role="button", expected={"identifier": "add-gift.to"})
        capture = wait(predicate="exists", identifier="add-gift.to")
        tap(capture, identifier="add-gift.to", expected={"identifier": "person-picker.query"})
        capture = wait(predicate="exists", label=receiver_name, role="button")
        if element(capture, label=receiver_name, role="button").get("identifier") != original_receiver_id:
            raise ValueError("Duplicate To person received a new identifier")
        tap(capture, label=receiver_name, role="button", expected={"identifier": "add-gift.save"})
        capture = checkpoint("duplicate-person-reuse", identifier="add-gift.save")
        tap(capture, identifier="add-gift.save", expected={"label": duplicate_name}, verify=assert_form_absent)
        capture = wait(predicate="exists", label=duplicate_name)
        assert_form_absent(capture)

        # Settings: currency navigation works and the bundled license content is present.
        capture = wait(predicate="exists", label="Settings", role="button")
        tap(capture, label="Settings", role="button", expected={"identifier": "settings.screen"})
        capture = checkpoint("settings", identifier="settings.screen")
        initial_currency = element(capture, identifier="settings.currency").get("value")
        target_currency = currency_target(initial_currency)
        metadata["currency_observation"] = {"initial": initial_currency, "selected": target_currency}
        tap(capture, identifier="settings.currency", expected={"identifier": "settings.currency.list"})
        capture = wait(predicate="exists", identifier="settings.currency.list")
        target_identifier = f"settings.currency.{target_currency}"
        if not has_element(capture, identifier=target_identifier):
            raise ValueError(f"{target_currency} currency option is not visible in the currency list")
        if element(capture, identifier=target_identifier).get("value") != target_currency:
            raise ValueError(f"{target_currency} currency option did not expose its exact code")
        tap(capture, identifier=target_identifier, expected={"label": "Settings", "role": "button"})
        # Currency selection persists in place; use the native navigation back button.
        capture = wait(predicate="exists", label="Settings", role="button")
        tap(capture, label="Settings", role="button", expected={"identifier": "settings.third-party-licenses"})
        capture = wait(predicate="exists", identifier="settings.screen")
        assert_currency(capture, target_currency)
        tap(capture, identifier="settings.third-party-licenses", expected={"identifier": "settings.third-party-licenses.screen"})
        licenses_capture = checkpoint("licenses", identifier="settings.third-party-licenses.screen")
        assert_license_content(licenses_capture)
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
            "calendar-5-weeks", "calendar-6-weeks", "gift-saved", "gift-after-relaunch",
            "settings-aud", "licenses",
        ],
    }
    simulator = None
    recording = False
    test_succeeded = False
    result_bundle = None
    try:
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
            artifacts = (error.payload or {}).get("result", {}).get("data", {}).get("artifacts", {})
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
        if test_succeeded and result_bundle and result_bundle.is_dir():
            try:
                _export_xcresult_attachments(result_bundle, attachments)
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                metadata["export_error"] = str(error)
        images = sorted(attachments.glob("*.png"))
        for planned in metadata["planned_checkpoint_names"]:
            matches = [image for image in images if planned.lower() in image.stem.lower()]
            if matches:
                metadata["checkpoints"].append({"name": planned, "image": f"attachments/{matches[0].name}"})
        missing = [name for name in metadata["planned_checkpoint_names"]
                   if name not in {checkpoint["name"] for checkpoint in metadata["checkpoints"]}]
        if missing:
            metadata["missing_checkpoints"] = missing
        video = directory / "journeys.mp4"
        if test_succeeded:
            metadata["journey_outcome"] = "success"
        if test_succeeded and not missing and video.is_file() and video.stat().st_size:
            metadata["export_outcome"] = "success"
        (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        shutil.rmtree(directory / "DerivedData", ignore_errors=True)
    if metadata["export_outcome"] != "success":
        raise ValueError("Native acceptance evidence export is incomplete")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    run(parser.parse_args().directory)
