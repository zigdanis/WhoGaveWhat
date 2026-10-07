#!/usr/bin/env python3
"""Import only WhoGaveWhat release credentials; never echo their values."""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import sys


def restricted_file(path):
    path = Path(path).expanduser().resolve(strict=True)
    if not stat.S_ISREG(path.stat().st_mode) or path.stat().st_mode & 0o077 or path.stat().st_uid != os.getuid():
        raise ValueError(f"Use a regular file readable only by you (chmod 600): {path}")
    repo = Path(__file__).resolve().parent.parent
    if path == repo or repo in path.parents:
        raise ValueError("Credential files must be outside the repository")
    if any((parent / '.git').exists() for parent in path.parents):
        raise ValueError("Credential files must be outside every git checkout")
    return path


def release_api(repository, path=''):
    route = 'repos/' + repository + ('/' + path if path else '')
    response = subprocess.run(['gh', 'api', route], text=True, capture_output=True)
    if response.returncode:
        raise RuntimeError('Cannot verify release configuration; check gh authentication')
    return json.loads(response.stdout)


def require_release_environment(repository):
    if release_api(repository).get('full_name') != 'zigdanis/WhoGaveWhat':
        raise RuntimeError('Credentials can only be imported into the canonical zigdanis/WhoGaveWhat repository')
    environment = release_api(repository, 'environments/testflight')
    policy = environment.get('deployment_branch_policy') or {}
    branches = release_api(repository, 'environments/testflight/deployment-branch-policies')['branch_policies']
    if not policy.get('custom_branch_policies') or {(p['name'], p['type']) for p in branches} != {('master', 'branch')}:
        raise RuntimeError('The testflight environment must allow only the master branch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, help='Explicit canonical release repository (zigdanis/WhoGaveWhat)')
    parser.add_argument("file", nargs="?", default="~/.config/whogavewhat-testflight/credentials.json")
    args = parser.parse_args()
    require_release_environment(args.repo)
    source = restricted_file(args.file)
    data = json.loads(source.read_text())
    required = {"ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH", "MATCH_PASSWORD"}
    if set(data) != required or any(not isinstance(v, str) or not v.strip() for v in data.values()):
        raise ValueError("Fill exactly ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH, MATCH_PASSWORD")
    key = restricted_file(data.pop("ASC_PRIVATE_KEY_PATH"))
    if key.parent != source.parent or key.suffix != '.p8':
        raise ValueError('Use a temporary .p8 copy beside the credentials JSON; both input files are removed after import')
    data["ASC_PRIVATE_KEY"] = key.read_text()
    # Validate without including the private key in arguments, output, or errors.
    check = subprocess.run(["openssl", "pkey", "-check", "-noout"], input=data["ASC_PRIVATE_KEY"],
                           text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode:
        raise ValueError("ASC_PRIVATE_KEY_PATH must contain the downloaded Apple .p8 private key")
    for name, value in data.items():
        result = subprocess.run(["gh", "secret", "set", name, "--repo", args.repo, "--env", "testflight"],
                                input=value, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(f"Could not save {name}; inputs retained. Check gh authentication and retry.")
        print(f"Saved {name}")
    key.unlink()
    source.unlink()
    print("Imported four encrypted Actions secrets; removed local credential input files.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as error:
        message = 'Invalid credentials JSON' if isinstance(error, json.JSONDecodeError) else str(error)
        if isinstance(error, OSError):
            message = 'Cannot read private credential input files; check their paths and permissions'
        print(message, file=sys.stderr)
        sys.exit(1)
