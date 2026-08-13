#!/usr/bin/env python3
"""Mutation experiment for the weight and balance calculator.

Introduces one deliberate defect at a time into the calculator and reports which
part of the test suite catches it. The result is the 39 out of 39 quoted in
VERIFICATION.md, and this script is here so that number can be checked rather
than taken on faith.

    python3 verification/run_mutations.py            # the whole set
    python3 verification/run_mutations.py M04 P01    # only these
    python3 verification/run_mutations.py --check    # is the recorded result current?

The recorded result carries the SHA-256 of the two files it was measured over,
so --check can tell in milliseconds whether it still describes the code in front
of you, without spending the ten minutes to find out. A result that no longer
matches its source is not a weaker result, it is a statement about a file that
no longer exists.

Nothing on disk is modified by a run. The mutated page is held in memory and
served from there, so an interrupted run cannot leave a defect behind in
index.html.

Needs Python 3 and a Chromium or Chrome on PATH, the same browser run_tests.sh
uses. Set CHROME_BIN to point at a specific one. A full run takes around ten
minutes: 39 mutations, and for each one the suite runs once per layer.
"""

import hashlib
import http.server
import json
import os
import re
import shutil
import socketserver
import subprocess
import sys
import threading
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_FILE = ROOT / "index.html"
MUTATIONS_FILE = Path(__file__).resolve().parent / "mutations.json"
RESULTS_FILE = Path(__file__).resolve().parent / "results.json"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_recorded_result():
    """Reports whether results.json still describes the files in front of us.

    The whole of index.html is hashed, tests included: what a layer catches
    depends on the tests as much as on the code, so any edit to either can move
    the outcome. An edit that turns out not to change anything still has to be
    measured to know that, which is the point.
    """
    if not RESULTS_FILE.exists():
        print(f"No recorded result at {RESULTS_FILE.relative_to(ROOT)}. Run this script.")
        return 1
    recorded = json.loads(RESULTS_FILE.read_text(encoding="utf-8"))
    stale = []
    for label, path, key in (("index.html", SOURCE_FILE, "source_sha256"),
                             ("mutations.json", MUTATIONS_FILE, "mutations_sha256")):
        now, then = sha256(path), recorded.get(key)
        if then is None:
            stale.append(f"{label}: the recorded result predates this check and carries no hash")
        elif now != then:
            stale.append(f"{label}: measured over {then[:12]}, now {now[:12]}")
    if stale:
        print("The recorded result no longer describes these files:")
        for line in stale:
            print(f"  {line}")
        print("\nRe-run the experiment: python3 verification/run_mutations.py")
        return 1
    escaped = recorded.get("escaped", [])
    print(f"Recorded result is current: {recorded['mutations']} mutations, "
          f"{len(escaped)} escaped, over a suite of {recorded['suite_assertions']} assertions.")
    return 0

# The suite writes every constant out a second time to check it against the
# handbook. Mutating both halves would edit the check along with the value it
# checks, so everything from this marker on is off limits.
TEST_MARKER = "// --- TEST LOADER LOGIC ---"

# Each layer is run on its own, so a defect can be attributed to the module that
# catches it rather than to the suite as a whole. QUnit's filter takes a
# substring, or a regular expression between slashes, and inverts it with a
# leading "!".
LAYERS = {
    "examples": "!/POH source data|Invariants|Envelope verdict|Load limits/",
    "poh": "POH source data",
    "invariants": "Invariants",
    "envelope": "Envelope verdict",
    "loadlimits": "Load limits",
}

SUMMARY_RE = re.compile(r"(\d+) assertions of (\d+) passed, (\d+) failed")
PAGE_TIMEOUT = int(os.environ.get("SUITE_TIMEOUT", "90"))


def find_chrome():
    if os.environ.get("CHROME_BIN"):
        return os.environ["CHROME_BIN"]
    for name in ("chromium", "google-chrome-stable", "google-chrome", "chromium-browser"):
        found = shutil.which(name)
        if found:
            return found
    cached = sorted(Path.home().glob(".cache/ms-playwright/chromium-*/chrome-linux*/chrome"))
    if cached:
        return str(cached[-1])
    sys.exit("No chromium or chrome found. Install one, or set CHROME_BIN.")


class MutatingHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the repository, with index.html replaced by whatever is in memory."""

    mutated = None

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path in ("/", "/index.html") and type(self).mutated is not None:
            body = type(self).mutated
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def log_message(self, *args):
        pass


def start_server():
    httpd = socketserver.TCPServer(("127.0.0.1", 0), MutatingHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd.server_address[1]


def run_suite(chrome, port, layer=None):
    """Runs the suite (optionally one layer) and returns its QUnit summary."""
    params = {"test": "true"}
    if layer:
        params["filter"] = LAYERS[layer]
    url = f"http://127.0.0.1:{port}/index.html?" + urllib.parse.urlencode(params)
    try:
        out = subprocess.run(
            [chrome, "--headless", "--disable-gpu", "--no-first-run",
             "--virtual-time-budget=15000", "--dump-dom", url],
            capture_output=True, text=True, timeout=PAGE_TIMEOUT,
        ).stdout
    except subprocess.TimeoutExpired:
        return None
    match = SUMMARY_RE.search(re.sub(r"\s+", " ", re.sub(r"<[^>]*>", " ", out)))
    if not match:
        return None  # the page never reported: treat as a failure, not a pass
    total, passed, failed = (int(g) for g in match.groups())
    return {"total": total, "passed": passed, "failed": failed,
            "green": failed == 0 and passed > 0}


def mutate(source, find, replace):
    app, marker, tests = source.partition(TEST_MARKER)
    if not marker:
        sys.exit(f"Could not find the test loader marker in index.html: {TEST_MARKER}")
    hits = app.count(find)
    if hits != 1:
        sys.exit(f"'find' matched {hits} times in the application code, expected exactly 1:\n"
                 f"  {find[:100]!r}")
    return app.replace(find, replace) + marker + tests


def main():
    if "--check" in sys.argv:
        return check_recorded_result()
    wanted = set(sys.argv[1:])
    chrome = find_chrome()
    source = SOURCE_FILE.read_text(encoding="utf-8")
    mutations = json.loads(MUTATIONS_FILE.read_text(encoding="utf-8"))["mutations"]
    if wanted:
        mutations = [m for m in mutations if m["id"] in wanted]
        missing = wanted - {m["id"] for m in mutations}
        if missing:
            sys.exit(f"No such mutation: {', '.join(sorted(missing))}")

    port = start_server()
    print(f"Browser: {chrome}")

    baseline = run_suite(chrome, port)
    if baseline is None or not baseline["green"]:
        sys.exit(f"The suite is not green before mutating anything: {baseline}. "
                 f"Fix that first, or the run below means nothing.")
    sizes = {name: run_suite(chrome, port, name)["total"] for name in LAYERS}
    print(f"Baseline: {baseline['total']} assertions, all passing")
    print(f"Per layer: {sizes}, summing to {sum(sizes.values())}\n")

    rows = []
    for mut in mutations:
        MutatingHandler.mutated = mutate(source, mut["find"], mut["replace"]).encode("utf-8")
        full = run_suite(chrome, port)
        caught = []
        if full is None or not full["green"]:
            caught = [name for name in LAYERS
                      if (r := run_suite(chrome, port, name)) is None or not r["green"]]
        verdict = "+".join(caught) if caught else "ESCAPES"
        print(f"{mut['id']}  {mut['category']:11}  {verdict:44}  {mut['description']}")
        rows.append({"id": mut["id"], "category": mut["category"],
                     "description": mut["description"],
                     "caught_by": caught, "escapes": not caught})
    MutatingHandler.mutated = None

    escaped = [r["id"] for r in rows if r["escapes"]]
    print(f"\n{len(rows) - len(escaped)} of {len(rows)} caught."
          + (f" ESCAPED: {', '.join(escaped)}" if escaped else ""))
    for name in LAYERS:
        alone = [r["id"] for r in rows if r["caught_by"] == [name]]
        print(f"  caught only by {name:11}: {len(alone):2}  {', '.join(alone)}")

    if not wanted:
        RESULTS_FILE.write_text(json.dumps(
            {"schema": 1,
             "_comment": "Written by verification/run_mutations.py. The two hashes below "
                         "are of the files this result was measured over; "
                         "run_mutations.py --check compares them against the files on "
                         "disk, so a result that has gone stale says so instead of "
                         "standing there looking current.",
             "source_sha256": sha256(SOURCE_FILE),
             "mutations_sha256": sha256(MUTATIONS_FILE),
             "suite_assertions": baseline["total"],
             "assertions_per_layer": sizes,
             "mutations": len(rows),
             "escaped": escaped,
             "results": rows}, indent=2) + "\n", encoding="utf-8")
        print(f"\nWrote {RESULTS_FILE.relative_to(ROOT)}")
    return 1 if escaped else 0


if __name__ == "__main__":
    sys.exit(main())
