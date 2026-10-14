"""Shared validation for PR evidence metadata and the trusted-base status gate."""
import argparse
import json
import re
import subprocess

START = "<!-- visual-evidence:start -->"
END = "<!-- visual-evidence:end -->"
METADATA_PREFIX = "<!-- visual-evidence:metadata "
ATTACHMENT = re.compile(r"https://github\.com/user-attachments/assets/[A-Za-z0-9-]+\Z")
NATIVE_JOB_NAMES = {"Unit tests and app smoke", "Spotlight diagnostics (non-acceptance)"}


def gh(*arguments):
    return subprocess.check_output(["gh", *arguments], text=True)


def metadata_comment(metadata):
    return METADATA_PREFIX + json.dumps(metadata, sort_keys=True) + " -->"


def parse_evidence(body):
    if body.count(START) != 1 or body.count(END) != 1 or body.index(START) > body.index(END):
        raise ValueError("Publish one complete visual evidence section with screenshots AND video.")
    block = body.split(START, 1)[1].split(END, 1)[0]
    matches = re.findall(re.escape(METADATA_PREFIX) + r"(\{[^\n]+\}) -->", block)
    if len(matches) != 1:
        raise ValueError("Evidence provenance is missing or ambiguous; use the publishing helper.")
    metadata = json.loads(matches[0])
    if metadata.get("evidence_kind") not in {"app-smoke", "feature-acceptance"}:
        raise ValueError("Evidence must label app smoke or feature acceptance.")
    for key in ["images", "videos"]:
        links = metadata.get(key)
        if not isinstance(links, list) or not links or any(not isinstance(url, str) or not ATTACHMENT.fullmatch(url) for url in links):
            raise ValueError("Both screenshots AND video need native GitHub attachments.")
    images, videos = metadata["images"], metadata["videos"]
    if len(set(images + videos)) != len(images + videos):
        raise ValueError("Screenshots and video must be distinct attachments.")
    for url in images:
        if not re.search(r"!\[[^\]\n]*\]\(" + re.escape(url) + r"\)", block):
            raise ValueError("Embed each screenshot in the PR description.")
    for url in videos:
        if not re.search(r"^" + re.escape(url) + r"\s*$", block, re.MULTILINE):
            raise ValueError("Embed each video on its own line in the PR description.")
    if not re.fullmatch(r"[0-9a-f]{40}", str(metadata.get("head_sha", ""))):
        raise ValueError("Missing reviewed head commit.")
    if any(not re.fullmatch(r"[1-9][0-9]*", str(metadata.get(key, ""))) for key in ["run_id", "run_attempt"]):
        raise ValueError("Missing CI run or attempt.")
    return metadata


def latest_pr_acceptance_run(repo, sha):
    """Keep the newest acceptance authoritative; ignore only proven no-native runs."""
    runs = json.loads(gh("run", "list", "--repo", repo, "--workflow", "tests.yml", "--event", "pull_request",
                         "--commit", sha, "--limit", "100", "--json", "databaseId"))
    for candidate in runs:
        run = json.loads(gh("api", f"repos/{repo}/actions/runs/{candidate['databaseId']}"))
        if (run.get("id") != candidate["databaseId"] or run.get("event") != "pull_request"
                or run.get("head_sha") != sha):
            raise ValueError("PR Tests run identity does not match the requested head.")
        # A rerun may have executed native acceptance on an earlier attempt; retain it.
        if (run.get("status") == "completed" and run.get("conclusion") in {"success", "skipped"}
                and run.get("run_attempt") == 1):
            payload = json.loads(gh("api", f"repos/{repo}/actions/runs/{run['id']}/attempts/1/jobs?per_page=100"))
            jobs = payload.get("jobs") if isinstance(payload, dict) else None
            if (isinstance(jobs, list) and len(jobs) == payload.get("total_count") == len(NATIVE_JOB_NAMES)
                    and all(isinstance(job, dict) and job.get("status") == "completed"
                            and job.get("conclusion") == "skipped" for job in jobs)
                    and {job.get("name") for job in jobs} == NATIVE_JOB_NAMES):
                current = json.loads(gh("api", f"repos/{repo}/actions/runs/{run['id']}"))
                if current != run:
                    raise ValueError("PR Tests run changed while verifying skipped native jobs; retry selection.")
                continue
        return run
    if len(runs) == 100:
        raise ValueError("No scheduled native acceptance found within the latest 100 PR Tests runs.")
    return None


def checked_run(repo, sha, metadata):
    run = latest_pr_acceptance_run(repo, sha)
    if not run or str(run["id"]) != str(metadata["run_id"]):
        raise ValueError("Evidence is not from the latest PR Tests run.")
    if (run["status"] != "completed" or run["conclusion"] != "success"
            or run.get("event") != "pull_request" or run.get("head_sha") != sha
            or str(run["run_attempt"]) != str(metadata["run_attempt"])):
        raise ValueError("The current CI attempt must pass and match the reviewed evidence.")
    return run


def validate(repo, pr):
    metadata = parse_evidence(pr.get("body") or "")
    sha = pr["head"]["sha"]
    if metadata["head_sha"] != sha:
        raise ValueError("Visual evidence is stale for the current PR head.")
    checked_run(repo, sha, metadata)
    return metadata


def main(argv=None):
    parser = argparse.ArgumentParser(description="Select the latest scheduled native PR acceptance run.")
    parser.add_argument("repo")
    parser.add_argument("sha")
    args = parser.parse_args(argv)
    run = latest_pr_acceptance_run(args.repo, args.sha)
    if run is None:
        parser.exit(1, f"No scheduled PR native acceptance for {args.sha} yet.\n")
    print(json.dumps(run))


if __name__ == "__main__":
    main()
