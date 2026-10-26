#!/usr/bin/env python3
"""Measures the timeline prototype (M0-30) on one target and prints its results as one JSON line.

Usage: python3 tools/timeline_bench.py <linux|chrome|firefox> [--wasm] [--check]

Generates the 1M-asset synthetic library once (tools/synthlib, seed 42; cached in $PHOTOLIB_CACHE, else
${TMPDIR:-/var/tmp}/photolib-<uid>), counts its assets per capture day, builds app/benchmark/timeline.dart in profile
mode with those counts as bench/library.json, and runs it: on Linux under xvfb-run from a copy in the cache (the
checkout may be noexec), in a browser headless from a server on 127.0.0.1 that receives the results. Chrome is
$CHROME_EXECUTABLE or google-chrome, Firefox $FIREFOX_EXECUTABLE or firefox; --wasm builds with dart2wasm, which
Flutter's loader runs on Chromium only. With --check, the web part's budget `timeline-scroll-web` of
tools/perf/budgets.json is checked too: the share of janky frames of the codec pipeline's drag and fling, the worse of
the two, less what an idle page of the same view missed meanwhile (ADR-0140, which tools/perf/perf.py applies), must
be within it (exit status 1 otherwise); a run over it is measured again, three runs at most on one build, the least
charged counting, and the machine's load average is recorded with it.
"""
import collections
import csv
import functools
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
TIMEOUT = 900
WINDOW = (1280, 1024)
MAX_IDLE = 10


def buckets(rows):
    """Assets per local capture day, newest first and undated (0) last, as yyyymmdd."""
    counts = collections.Counter(int(row["taken_local"][:10].replace("-", "") or 0) for row in rows)
    days = sorted(counts, key=lambda day: (day == 0, -day))
    return {"days": days, "counts": [counts[day] for day in days]}


def library(cache):
    out = cache / "library-1m-42.json"
    if not out.exists():
        assets = cache / "synthlib-1m-42"
        shutil.rmtree(assets, ignore_errors=True)
        subprocess.run(["cargo", "run", "-q", "--release", "--manifest-path", str(ROOT / "tools/synthlib/Cargo.toml"),
                        "--", "--assets", "1m", "--seed", "42", "--out", str(assets)], check=True)
        with open(assets / "assets.csv", newline="", encoding="utf-8") as table:
            out.write_text(json.dumps(buckets(csv.DictReader(table))))
        shutil.rmtree(assets)
    return out


def build(*args):
    subprocess.run(["flutter", "build", *args, "--profile", "-t", "benchmark/timeline.dart"], cwd=APP, check=True,
                   stdout=sys.stderr)


def run_linux(lib, cache):
    build("linux")
    with tempfile.TemporaryDirectory(dir=cache) as tmp:
        bundle = shutil.copytree(APP / "build/linux/x64/profile/bundle", Path(tmp) / "bundle")
        (bundle / "data/flutter_assets/bench").mkdir()
        shutil.copy(lib, bundle / "data/flutter_assets/bench/library.json")
        run = subprocess.run(["xvfb-run", "-a", "-s", f"-screen 0 {WINDOW[0]}x{WINDOW[1]}x24", str(bundle / "photolib")],
                             capture_output=True, text=True, timeout=TIMEOUT)
    for line in run.stdout.splitlines():
        if line.startswith("timeline-bench: "):
            return {"target": "linux", **json.loads(line.split(" ", 1)[1])}
    sys.exit(f"timeline_bench.py: no results from the Linux app\n{run.stdout}\n{run.stderr}")


class _Results(http.server.SimpleHTTPRequestHandler):
    posted = None

    def do_POST(self):
        type(self).posted = self.rfile.read(int(self.headers["Content-Length"]))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


def run_web(browser, wasm, lib, cache, collect=lambda once: once()):
    """Builds once and serves the build; `collect` gets `once`, which opens the browser on it and returns one run's
    results, and returns what run_web does: --check measures up to three times without building again."""
    executable = (os.environ.get("CHROME_EXECUTABLE") or shutil.which("google-chrome") if browser == "chrome"
                  else os.environ.get("FIREFOX_EXECUTABLE") or shutil.which("firefox"))
    if not executable:
        sys.exit(f"timeline_bench.py: no {browser}")
    version = subprocess.run([executable, "--version"], capture_output=True, text=True).stdout.strip()
    with tempfile.TemporaryDirectory(dir=cache) as tmp:
        web, profile = Path(tmp) / "web", Path(tmp) / "profile"
        build("web", "--output", str(web), *(["--wasm"] if wasm else []))
        (web / "assets/bench").mkdir(parents=True, exist_ok=True)
        shutil.copy(lib, web / "assets/bench/library.json")
        handler = type("Handler", (_Results,), {})
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=web))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_address[1]}/"
        if browser == "chrome":
            command = [executable, "--headless=new", "--no-sandbox", "--enable-unsafe-swiftshader",
                       f"--window-size={WINDOW[0]},{WINDOW[1]}", f"--user-data-dir={profile}",
                       "--disable-background-networking", url]
        else:
            profile.mkdir()
            # Full-resolution performance.now(); Firefox otherwise rounds it to a millisecond.
            (profile / "user.js").write_text('user_pref("privacy.reduceTimerPrecision", false);\n')
            command = [executable, "--headless", "--no-remote", "--profile", str(profile),
                       f"--window-size={WINDOW[0]},{WINDOW[1]}", url]

        def once():
            handler.posted = None
            process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + TIMEOUT
            while handler.posted is None and time.monotonic() < deadline and process.poll() is None:
                time.sleep(1)
            process.terminate()
            process.wait()
            if handler.posted is None:
                sys.exit(f"timeline_bench.py: no results from {version}")
            return {"target": browser, "browser": version, **json.loads(handler.posted)}

        try:
            return collect(once)
        finally:
            server.shutdown()


def main(args):
    target, wasm = args[0], "--wasm" in args[1:]
    cache = Path(os.environ.get("PHOTOLIB_CACHE") or Path(os.environ.get("TMPDIR", "/var/tmp")) / f"photolib-{os.getuid()}")
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    lib = library(cache)
    if "--check" in args:
        if target == "linux":
            sys.exit("timeline_bench.py: --check is the web budget")
        return check(target, wasm, lib, cache)
    results = run_linux(lib, cache) if target == "linux" else run_web(target, wasm, lib, cache)
    print(json.dumps(results))
    return 0


def sample(results):
    """One run's janky share (the worse of the drag and the fling) and its idle page's, in %. An idle page that missed
    more than MAX_IDLE of its frames means the machine cannot measure anything: it earns no credit, or a run in which
    every frame was late would pass on its own idle page's."""
    janky = max(results[f"codec/{run}"]["janky_pct"] for run in ("drag", "fling"))
    idle = results["idle"]["janky_pct"]
    return (janky, idle if idle <= MAX_IDLE else 0)


def charged(janky, idle):
    """What perf.py charges against the budget: the share less what an idle page missed, never below 0 (ADR-0140)."""
    return round(max(0, janky - idle), 2)


def least_janky(measure, limit, attempts=3):
    """Measures again while the least charged so far is over `limit`, `attempts` at most (ADR-0140); returns the least
    charged sample (the first of equals) as (janky, idle, attempts made)."""
    least = measure()
    made = 1
    while made < attempts and charged(*least) > limit:
        made += 1
        again = measure()
        if charged(*again) < charged(*least):
            least = again
    return (*least, made)


def result_line(janky, idle, attempts, loadavg):
    """The result perf.py checks, with the load average the runs ended under, so a loaded machine shows in the log."""
    return {"budget": "timeline-scroll-web", "metric": "janky", "target": "web", "fixture": "1m", "value": janky,
            "idle": idle, "attempts": attempts, "loadavg": loadavg}


def check(target, wasm, lib, cache):
    budget = json.loads((ROOT / "tools/perf/budgets.json").read_text())["budgets"]["timeline-scroll-web"]
    limit = budget["metrics"]["janky"]["max"]["web"]
    def measure(once):
        def run():
            results = once()
            janky, idle = sample(results)
            seen = results["idle"]["janky_pct"]
            print(f"timeline_bench.py: janky {janky} %, its idle page {seen} % (credit {idle} %)", file=sys.stderr)
            return janky, idle
        return least_janky(run, limit)

    janky, idle, attempts = run_web(target, wasm, lib, cache, measure)
    line = result_line(janky, idle, attempts, round(os.getloadavg()[0], 2))
    out = cache / "timeline-scroll-web.jsonl"
    out.write_text(json.dumps(line) + "\n")
    print(json.dumps(line))
    return subprocess.run([sys.executable, str(ROOT / "tools/perf/perf.py"), "check", str(out)], check=False).returncode


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("linux", "chrome", "firefox"):
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1:]))
