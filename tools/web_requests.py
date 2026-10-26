#!/usr/bin/env python3
"""Fails when the web app or its media path breaks in Chrome or Firefox under photolibd's Content-Security-Policy.

Usage: python3 tools/web_requests.py <app-dir>

Builds the app with its store and kernel (tools/data/web.sh, tools/kernel/wasm.sh), --wasm and the pseudo-locales on,
and serves it on 127.0.0.1 under CSP as photolibd will, with the response's nonce in place of index.html's CSP_NONCE.
Each browser, headless, opens the media probe (tools/web_probe/), then the app in en-XA, whose accented letters need a
fallback font; problems() says what fails. Both pages load tools/web_probe/errors.js first, which posts their errors.
Chrome resolves no other host and Firefox has a dead proxy, so nothing leaves the machine.
"""
import http.server
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import time

TIMEOUT = 60
PROBE_TIMEOUT = 300
UPLOAD, APPEND = 4 << 30, 8 << 20
# How much the browser may grow while it uploads, when the file's slices are the request bodies and when each append is
# read into memory first, as encryption needs: half the file, as each browser leaves up to 1 GiB of spent appends.
UPLOADS = {"slices": 256 << 20, "bytes": 2 << 30}
PROBE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web_probe")
CSP = ("default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'nonce-{nonce}'; "
       "worker-src 'self' blob:; connect-src 'self' blob:; img-src 'self' blob: data:; media-src 'self' blob:; "
       "object-src 'none'; base-uri 'self'; frame-ancestors 'none'; require-trusted-types-for 'script'; "
       "trusted-types flutter-js default")
BUILDS = {"chrome": ["/main.dart.wasm", "/canvaskit/skwasm.wasm"],
          "firefox": ["/main.dart.js", "/canvaskit/canvaskit.wasm"]}
NEEDS = {"chrome": ["WasmGC", "ImageDecoder", "OPFS", "SharedWorker", "Web Locks", "File System Access", "MSE",
                    "Trusted Types"],
         "firefox": ["WasmGC", "createImageBitmap in workers", "OPFS", "Web Locks", "MSE"]}


def problems(browser, paths, reports, probe, uploads, errors):
    """What breaks in one browser, from the paths it requested from the app's origin, its CSP reports, the probe's
    results, what the server received of each upload and the errors its pages logged."""
    found = [f"{browser}: the CSP blocked {r.get('effective-directive') or r.get('violated-directive')} "
             f"{r.get('blocked-uri')}" for r in reports]
    found += [f"{browser}: {error}" for error in errors]
    found += [f"{browser}: fetched the default font, so the app bundles none: {p}" for p in paths if "/roboto/" in p]
    if not any(p.startswith("/main.dart.") for p in paths):
        found.append(f"{browser}: the app never loaded")
    else:
        if missing := [p for p in BUILDS[browser] if p not in paths]:
            found.append(f"{browser}: loaded no {', '.join(missing)}")
        if not any(p.endswith(".woff2") for p in paths):
            found.append(f"{browser}: no fallback font was requested within {TIMEOUT} s, so the fonts were not checked")
    if probe is None or "error" in probe:
        return found + [f"{browser}: the media probe " + (f"failed: {probe['error']}" if probe else "never reported")]
    found += [f"{browser} lacks {name}, which its tier needs" for name in NEEDS[browser] if not probe["features"][name]]
    for name, budget in UPLOADS.items():
        upload, resumes = uploads[name], probe["upload"][name]["resumes"]
        if upload["received"] != UPLOAD or not upload["complete"]:
            found.append(f"{browser}: the server received {upload['received']} of {UPLOAD} bytes from {name}")
        if resumes != upload["failed"]:
            found.append(f"{browser}: {upload['failed']} append from {name} failed and the probe resumed {resumes} "
                         "times")
        if upload["growth"] > budget:
            found.append(f"{browser} grew by {upload['growth'] >> 20} MiB while uploading 4 GiB from {name}, over its "
                         f"{budget >> 20} MiB")
    return found


def tree_rss(pid):
    """The resident memory of a process and its descendants, in bytes."""
    ps = subprocess.run(["ps", "-e", "-o", "pid=,ppid=,rss="], check=False, capture_output=True, text=True)
    rows = [line.split() for line in ps.stdout.splitlines()]
    children, rss = {}, {}
    for p, parent, kib in rows:
        children.setdefault(int(parent), []).append(int(p))
        rss[int(p)] = int(kib) << 10
    total, stack = 0, [pid]
    while stack:
        p = stack.pop()
        total += rss.get(p, 0)
        stack += children.get(p, [])
    return total


class Run:
    """What one browser did; `start` and `peak` are its size when the upload in progress began and since."""

    def __init__(self):
        self.paths, self.reports, self.errors, self.probe, self.pid = [], [], [], None, None
        self.start, self.peak = None, 0
        self.uploads = {name: {"received": 0, "complete": False, "failed": 0, "growth": 0} for name in UPLOADS}


def handler(web, run):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def end_headers(self):
            self.send_header("Content-Security-Policy", CSP.format(nonce=self.nonce) + "; report-uri /csp")
            super().end_headers()

        def translate_path(self, path):
            self.directory = PROBE if path.startswith("/probe/") else web
            return super().translate_path(path.removeprefix("/probe"))

        def answer(self, status, headers=(), body=b""):
            self.send_response(status)
            for name, value in [*headers, ("Content-Length", str(len(body)))]:
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(body)

        def parse_request(self):
            self.nonce = secrets.token_urlsafe(16)
            ok = super().parse_request()
            if ok:
                run.paths.append(self.path.split("?")[0])
            return ok

        def do_GET(self):
            if self.path.split("?")[0] not in ("/", "/index.html"):
                return super().do_GET()
            with open(os.path.join(web, "index.html"), "rb") as page:
                html = page.read().replace(b"CSP_NONCE", self.nonce.encode())
                html = html.replace(b"<head>", b'<head><script src="/probe/errors.js"></script>', 1)
                self.answer(200, [("Content-Type", "text/html")], html)

        def do_HEAD(self):
            if not self.path.startswith("/upload/"):
                return super().do_HEAD()
            self.answer(204, [("Upload-Offset", str(run.uploads[self.path[8:]]["received"]))])

        def do_POST(self):
            body = self.rfile.read(int(self.headers["Content-Length"]))
            if self.path == "/errors":
                run.errors.append(body.decode())
                return self.answer(204)
            body = json.loads(body)
            if self.path == "/csp":
                run.reports.append(body.get("csp-report", body))
            else:
                run.probe = body
            self.answer(204)

        def do_PATCH(self):
            upload, offset = run.uploads[self.path[8:]], int(self.headers["Upload-Offset"])
            length = remaining = int(self.headers["Content-Length"])
            while remaining and (chunk := self.rfile.read(min(remaining, 1 << 20))):
                remaining -= len(chunk)
            if remaining:
                return
            if offset == 0:
                run.start = run.peak = tree_rss(run.pid)
            if offset != upload["received"]:
                return self.answer(409)
            if offset == UPLOAD // 2 and not upload["failed"]:
                upload["failed"] += 1
                return self.answer(502, [("Content-Type", "text/html")], b"<html><body>502 Bad Gateway</body></html>")
            upload["received"] += length
            upload["complete"] = self.headers["Upload-Complete"] == "?1"
            if upload["complete"]:
                upload["growth"], run.start = run.peak - run.start, None
            self.answer(204)

    return Handler


def launch(browser, url, profile):
    if browser == "chrome":
        exe = os.environ.get("CHROME_EXECUTABLE") or shutil.which("google-chrome") or shutil.which("chromium")
        args = ["--headless=new", "--no-sandbox", "--disable-gpu", "--enable-unsafe-swiftshader",
                "--disable-background-networking", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1",
                "--lang=en-XA", "--accept-lang=en-XA", f"--user-data-dir={profile}", "--remote-debugging-port=0"]
    else:
        exe = os.environ.get("FIREFOX_EXECUTABLE") or shutil.which("firefox")
        prefs = {"intl.accept_languages": "en-XA", "network.proxy.type": 1, "network.proxy.http": "127.0.0.1",
                 "network.proxy.http_port": 9, "network.proxy.ssl": "127.0.0.1", "network.proxy.ssl_port": 9,
                 "browser.shell.checkDefaultBrowser": False, "datareporting.policy.dataSubmissionEnabled": False,
                 "toolkit.telemetry.reportingpolicy.firstRun": False,
                 "browser.startup.homepage_override.mstone": "ignore"}
        with open(os.path.join(profile, "user.js"), "w", encoding="utf-8") as user:
            user.writelines(f"user_pref({json.dumps(k)}, {json.dumps(v)});\n" for k, v in prefs.items())
        args = ["--headless", "--no-remote", "--profile", profile]
    if not exe:
        sys.exit(f"web_requests.py: no {browser}; install it or set {browser.upper()}_EXECUTABLE")
    return subprocess.Popen([exe, *args, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def visit(browser, web):
    """Opens the probe, then the app, in one browser, and returns what it did."""
    run = Run()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler(web, run))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = f"http://127.0.0.1:{server.server_address[1]}"
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as profile:
        process = launch(browser, f"{origin}/probe/?upload={UPLOAD}&append={APPEND}", profile)
        run.pid = process.pid
        deadline = time.monotonic() + PROBE_TIMEOUT
        while time.monotonic() < deadline and run.probe is None:
            if run.start is not None:
                run.peak = max(run.peak, tree_rss(run.pid))
            time.sleep(0.2)
        deadline = time.monotonic() + TIMEOUT
        while time.monotonic() < deadline and not any(p.endswith(".woff2") for p in run.paths):
            time.sleep(0.5)
        time.sleep(2)
        process.terminate()
        try:
            process.wait(10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    server.shutdown()
    return run


def main(app):
    tools = os.path.dirname(os.path.abspath(__file__))
    subprocess.run(["bash", os.path.join(tools, "data", "web.sh"), os.path.join(app, "web")], check=True)
    subprocess.run(["bash", os.path.join(tools, "hls", "web.sh"), os.path.join(app, "web")], check=True)
    subprocess.run(["bash", os.path.join(tools, "kernel", "wasm.sh"), os.path.join(app, "web", "kernel")], check=True)
    with tempfile.TemporaryDirectory() as tmp:
        web = os.path.join(tmp, "web")
        subprocess.run(["flutter", "build", "web", "--wasm", "--dart-define=PHOTOLIB_FLAGS=pseudoLocales",
                        "--output", web], cwd=app, check=True)
        found = []
        for browser in BUILDS:
            run = visit(browser, web)
            for path in dict.fromkeys(run.paths):
                print(f"web_requests.py: {browser} {path}")
            print(f"web_requests.py: {browser} probe {json.dumps(run.probe)}")
            print(f"web_requests.py: {browser} uploads {json.dumps(run.uploads)}")
            found += problems(browser, run.paths, run.reports, run.probe, run.uploads, run.errors)
    for problem in found:
        print(f"FAIL: {problem}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
