#!/usr/bin/env python3
"""Check a screenshot review page's full-screen viewer in headless Chrome.

Writes a copy of the page with a probe script next to it in a temporary folder, loads it with
`google-chrome --headless=new --dump-dom` (or `--chrome PATH`), and checks that a tap opens the first shot,
the right and left arrows step through every shot, and a tap closes the viewer. The page itself is not
changed. Exits 0 when every step behaves, 1 otherwise.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Runs after the page's own script: open the first shot, step right, step left twice (wrapping to the last
# shot), then tap the open shot. Each step records whether the viewer is open and its label.
PROBE = """<script>
window.addEventListener('load', () => {
  const zoom = document.getElementById('zoom');
  const shots = document.querySelectorAll('figure a');
  const steps = [];
  const record = () => steps.push({open: !!zoom && zoom.open, label: zoom ? zoom.querySelector('p').textContent : ''});
  const key = name => document.dispatchEvent(new KeyboardEvent('keydown', {key: name, bubbles: true}));
  if (zoom && shots.length) {
    shots[0].querySelector('img').click(); record();
    key('ArrowRight'); record();
    key('ArrowLeft'); key('ArrowLeft'); record();
    zoom.querySelector('img').click(); record();
  }
  document.title = 'REVIEW-PROBE ' + JSON.stringify({shots: shots.length, steps});
});
</script>"""
RESULT = re.compile(r"<title>REVIEW-PROBE (\{.*?\})</title>", re.S)


def probe_page(page):
    """The page with the probe script added at the end of its body."""
    return page.replace("</body>", PROBE + "</body>") if "</body>" in page else page + PROBE


def evaluate(result):
    """Problems found in the probe's result; an empty list means the viewer works."""
    shots, steps = result.get("shots", 0), result.get("steps", [])
    if not shots:
        return ["the page has no shots in figure links, or no #zoom viewer"]
    if len(steps) != 4:
        return [f"the probe ran {len(steps)} of 4 steps"]
    problems = []
    expected = [(True, f"1/{shots}"), (True, f"{min(2, shots)}/{shots}"), (True, f"{shots}/{shots}"), (False, None)]
    names = ("a tap on the first shot", "the right arrow", "two left arrows", "a tap on the open shot")
    for name, (should_open, position), step in zip(names, expected, steps):
        if step["open"] != should_open:
            problems.append(f"after {name} the viewer is {'open' if step['open'] else 'closed'}")
        elif position and not step["label"].endswith(position):
            problems.append(f"after {name} the viewer shows {step['label']!r}, expected shot {position}")
    return problems


def run(page_path, chrome):
    with tempfile.TemporaryDirectory() as temporary:
        probe = Path(temporary) / "probe.html"
        probe.write_text(probe_page(Path(page_path).read_text()))
        output = subprocess.run(
            [chrome, "--headless=new", "--disable-gpu", "--no-sandbox", "--virtual-time-budget=10000",
             "--dump-dom", probe.as_uri()], capture_output=True, text=True, timeout=120).stdout
    match = RESULT.search(output)
    if not match:
        return None, ["the probe did not finish; check that the page's own script loads"]
    result = json.loads(match[1])
    return result, evaluate(result)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("page", type=Path, help="Review page, such as one written by store-screenshots.py --review-page")
    parser.add_argument("--chrome", default=shutil.which("google-chrome") or shutil.which("chromium") or "google-chrome",
                        help="Chrome or Chromium binary (default: google-chrome or chromium on PATH)")
    args = parser.parse_args(argv)
    try:
        result, problems = run(args.page, args.chrome)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if problems:
        return 1
    print(f"{args.page}: {result['shots']} shots; tap opens, arrows step through, tap closes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
