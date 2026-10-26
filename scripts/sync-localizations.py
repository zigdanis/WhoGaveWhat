#!/usr/bin/env python3
"""Synchronize the String Catalog with compiler output from a completed app build."""

import argparse
import difflib
from pathlib import Path
import shutil
import subprocess
import tempfile


CATALOG = Path("WhoGaveWhat/Resources/Localizable.xcstrings")


def sync(derived_data, check=False):
    # Only the app target's compiler output belongs to this catalog. Test-target
    # strings and other packages must not keep obsolete app strings alive.
    stringsdata = sorted((derived_data / "Build/Intermediates.noindex").glob(
        "WhoGaveWhat.build/*/WhoGaveWhat.build/Objects-normal/*/*.stringsdata"))
    if not stringsdata:
        raise ValueError("No app .stringsdata found; build WhoGaveWhat with this DerivedData path first")
    with tempfile.TemporaryDirectory(prefix="whogavewhat-localizations-") as directory:
        target = Path(directory) / CATALOG.name if check else CATALOG
        if check:
            shutil.copy2(CATALOG, target)
        subprocess.run(["xcrun", "xcstringstool", "sync", str(target), "--stringsdata",
                        *(str(path) for path in stringsdata)], check=True)
        if check:
            before = CATALOG.read_text()
            after = target.read_text()
            if before != after:
                print("".join(difflib.unified_diff(
                    before.splitlines(keepends=True), after.splitlines(keepends=True),
                    fromfile=str(CATALOG), tofile="synchronized/" + str(CATALOG))), end="")
                print("error: String Catalog is out of sync. Build with Xcode 27.1, then run "
                      "scripts/sync-localizations.py --derived-data PATH and commit the catalog.")
                return 1
    print("String Catalog is synchronized.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--check", action="store_true", help="Check a temporary copy without editing the catalog")
    args = parser.parse_args()
    try:
        return sync(args.derived_data.resolve(), args.check)
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
