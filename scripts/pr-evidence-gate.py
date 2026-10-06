#!/usr/bin/env python3
"""Validate current PR media using metadata only; publish a status on its head."""
import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

from evidence_validation import gh, validate


def update_status(repo, sha, state, description, target_url):
    with tempfile.TemporaryDirectory(prefix="whogavewhat-evidence-status-") as directory:
        payload = Path(directory) / "status.json"
        payload.write_text(json.dumps({"state": state, "context": "Visual evidence",
                                      "description": description[:140], "target_url": target_url}))
        gh("api", f"repos/{repo}/statuses/{sha}", "--method", "POST", "--input", str(payload))


def check(repo, number, publish_status=False):
    endpoint = f"repos/{repo}/pulls/{number}"
    pr = json.loads(gh("api", endpoint))
    if pr["state"] != "open":
        return True
    sha = pr["head"]["sha"]
    try:
        validate(repo, pr)
        error = None
    except (ValueError, KeyError, TypeError, subprocess.CalledProcessError) as failure:
        error = str(failure)
    current = json.loads(gh("api", endpoint))
    if current["head"]["sha"] != sha or current.get("body") != pr.get("body"):
        # Another event re-evaluates the newer head/body. Avoid publishing success for stale input.
        error = "PR changed during validation; evaluate the current description again."
    if publish_status:
        update_status(repo, sha, "failure" if error else "success",
                      error or "Current-head screenshots and video reviewed from passing CI", pr["html_url"])
    print(f"PR #{number}: {error or 'visual evidence passes'}")
    return error is None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pr", nargs="?", type=int)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--event-file", type=Path)
    parser.add_argument("--publish-status", action="store_true")
    args = parser.parse_args()
    repo = args.repo or json.loads(gh("api", "repos/{owner}/{repo}"))["full_name"]
    numbers = [args.pr] if args.pr else []
    if args.event_file:
        event = json.loads(args.event_file.read_text())
        if "pull_request" in event:
            numbers = [event["pull_request"]["number"]]
        elif "workflow_run" in event:
            run = event["workflow_run"]
            numbers = [pr["number"] for pr in run.get("pull_requests", [])]
            if not numbers:
                numbers = [pr["number"] for pr in json.loads(gh(
                    "api", f"repos/{repo}/commits/{run['head_sha']}/pulls")) if pr["state"] == "open"]
    if not numbers:
        print("No open PR to validate.")
        return
    results = [check(repo, number, args.publish_status) for number in sorted(set(numbers))]
    if not all(results):
        parser.exit(1)


if __name__ == "__main__":
    main()
