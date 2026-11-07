#!/usr/bin/env python3
"""Write the SwiftData store fixtures that StoreFixtureMigrationTests opens with the current schema.

Each fixture in the manifest names the commit of a shipped build. Its `SwiftDataModels.swift` is
taken unchanged from Git and compiled with FixtureWriter.swift on macOS, which inserts the
manifest's dataset and saves. The result is checkpointed into a single SQLite file, so the test
bundle carries one `.store` file per build. Run it on a Mac with Xcode:

    python3 scripts/store-fixtures/generate.py            # every fixture
    python3 scripts/store-fixtures/generate.py --only StoreFixture-1.2.0.store

Commit the regenerated files; never write over a fixture of a build that already shipped
unless its writer was wrong, because the file stands for data users have on their devices.
"""

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "WhoGaveWhatTests/Fixtures/StoreFixtures"
MANIFEST = FIXTURES / "store-fixtures.json"
WRITER = Path(__file__).with_name("FixtureWriter.swift")
MODELS_PATH = "WhoGaveWhat/Infrastructure/Persistence/SwiftDataModels.swift"
# Manifest feature -> compilation condition in FixtureWriter.swift.
FEATURE_FLAGS = {
    "role": "HAS_ROLE",
    "imageData": "HAS_IMAGE_DATA",
    "emojiPickedByUser": "HAS_EMOJI_PICKED_BY_USER",
    "lastSavedAt": "HAS_LAST_SAVED_AT",
    "currencyCode": "HAS_CURRENCY_CODE",
}


def compile_flags(features):
    unknown = sorted(set(features) - FEATURE_FLAGS.keys())
    if unknown:
        raise ValueError(f"Unknown fixture features: {', '.join(unknown)}")
    return [arg for feature in features for arg in ("-D", FEATURE_FLAGS[feature])]


def checkpoint(store):
    """Fold the write-ahead log into the main file and leave it in rollback-journal mode."""
    connection = sqlite3.connect(store)
    try:
        connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        connection.execute("PRAGMA journal_mode=DELETE")
    finally:
        connection.close()
    for suffix in ("-wal", "-shm"):
        Path(f"{store}{suffix}").unlink(missing_ok=True)


def write_fixture(fixture, work):
    models = subprocess.run(
        ["git", "show", f"{fixture['commit']}:{MODELS_PATH}"],
        cwd=ROOT, check=True, capture_output=True, text=True).stdout
    source = work / "SwiftDataModels.swift"
    source.write_text(models)
    binary = work / "FixtureWriter"
    subprocess.run(
        ["xcrun", "swiftc", "-parse-as-library", "-module-name", "WhoGaveWhat",
         *compile_flags(fixture["features"]), str(source), str(WRITER), "-o", str(binary)],
        check=True)
    output = work / fixture["file"]
    subprocess.run([str(binary), str(MANIFEST), str(output)], check=True)
    checkpoint(output)
    # External storage keeps large blobs next to the store; the dataset's photo is small enough to stay inline,
    # so the support folder SwiftData creates must stay empty.
    leftovers = sorted(
        str(path.relative_to(work)) for support in work.glob(f".{output.stem}_SUPPORT")
        for path in support.rglob("*") if path.is_file())
    if leftovers:
        raise ValueError(f"{fixture['file']} wrote external files the test bundle would not carry: {leftovers}")
    shutil.copyfile(output, FIXTURES / fixture["file"])
    print(f"{fixture['file']}: schema of {fixture['commit']} ({fixture['builds']})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", action="append", help="Write only this fixture file (repeatable)")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.exit(1, "error: SwiftData fixtures are written on macOS with Xcode\n")
    fixtures = json.loads(MANIFEST.read_text())["fixtures"]
    if args.only:
        missing = set(args.only) - {fixture["file"] for fixture in fixtures}
        if missing:
            parser.exit(1, f"error: not in the manifest: {', '.join(sorted(missing))}\n")
        fixtures = [fixture for fixture in fixtures if fixture["file"] in args.only]
    for fixture in fixtures:
        with tempfile.TemporaryDirectory(prefix="whogavewhat-store-fixture-") as directory:
            write_fixture(fixture, Path(directory))
    return 0


if __name__ == "__main__":
    sys.exit(main())
