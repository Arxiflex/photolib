#!/usr/bin/env bash
# tools/web_requests.py opens the web app and the media probe in Chrome and Firefox under photolibd's CSP. The gate
# runs it for real on the app; this checks its verdicts on made-up runs.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool node
cd "$REPO_ROOT" || exit 1

# problems <browser> <python-edit>: what web_requests.py reports for a run in <browser> that passes, after <python-edit>
# changes its paths (requested from the app's origin), reports (CSP reports), probe (the probe page's results), uploads
# (what the server received of each upload, and how much the browser grew meanwhile) or errors (what its pages logged).
problems() {
  python3 - "$@" <<'EOF_PY'
import sys
sys.path.insert(0, "tools")
import web_requests
browser, edit = sys.argv[1], sys.argv[2]
build = {"chrome": ["/main.dart.mjs", "/main.dart.wasm", "/canvaskit/skwasm.wasm"],
         "firefox": ["/main.dart.js", "/canvaskit/canvaskit.wasm"]}[browser]
paths = ["/", "/flutter_bootstrap.js", *build, "/fonts/notosans/v1/a.woff2"]
reports, errors = [], []
probe = {"features": {name: True for name in web_requests.NEEDS[browser]},
         "upload": {"slices": {"resumes": 1}, "bytes": {"resumes": 1}}}
uploads = {"slices": {"received": 4 << 30, "complete": True, "failed": 1, "growth": 10 << 20},
           "bytes": {"received": 4 << 30, "complete": True, "failed": 1, "growth": 1 << 30}}
exec(edit)
print("\n".join(web_requests.problems(browser, paths, reports, probe, uploads, errors)))
EOF_PY
}

expect_problems() {
  local description=$1 expected=$2 got
  got=$(problems "${@:3}") || { fail "$description: web_requests.py failed"; return; }
  if [[ $got == "$expected" ]]; then ok "$description"; else fail "$description: expected '$expected', got '$got'"; fi
}

expect_problems "Chrome on the WASM build with the probe's tier-1 features passes" "" chrome ""
expect_problems "Firefox on the JS build with the probe's tier-2 features passes" "" firefox ""
expect_problems "a CSP report fails" "chrome: the CSP blocked style-src-elem inline" \
  chrome 'reports.append({"effective-directive": "style-src-elem", "blocked-uri": "inline"})'
expect_problems "a font from a CDN, which the CSP blocks, fails" \
  "firefox: the CSP blocked font-src https://fonts.gstatic.com/s/notosans/v1/a.woff2" \
  firefox 'reports.append({"violated-directive": "font-src", "blocked-uri": "https://fonts.gstatic.com/s/notosans/v1/a.woff2"})'
expect_problems "fetching the default font means the app bundles none" \
  "chrome: fetched the default font, so the app bundles none: /fonts/roboto/v1/a.woff2" \
  chrome 'paths.append("/fonts/roboto/v1/a.woff2")'
expect_problems "Chrome on the JS build fails" "chrome: loaded no /main.dart.wasm, /canvaskit/skwasm.wasm" \
  chrome 'paths[2:5] = ["/main.dart.js", "/canvaskit/canvaskit.wasm"]'
expect_problems "Firefox on the WASM build fails" "firefox: loaded no /main.dart.js, /canvaskit/canvaskit.wasm" \
  firefox 'paths[2:4] = ["/main.dart.wasm", "/canvaskit/skwasm.wasm"]'
expect_problems "a run that needs no fallback font proves nothing about fonts" \
  "firefox: no fallback font was requested within 60 s, so the fonts were not checked" firefox 'paths.pop()'
expect_problems "a page that never loads the app fails" "chrome: the app never loaded" chrome 'paths[1:] = []'
expect_problems "a browser without a feature its tier needs fails" \
  "chrome lacks File System Access, which its tier needs" chrome 'probe["features"]["File System Access"] = []'
expect_problems "a probe that never reports fails" "firefox: the media probe never reported" firefox 'probe = None'
expect_problems "a probe that throws fails" "chrome: the media probe failed: TypeError: no worker" \
  chrome 'probe = {"error": "TypeError: no worker"}'
expect_problems "an uncaught exception or a console error in the probe's page fails" \
  "firefox: page /probe/: console.error: decoder lost" firefox 'errors.append("page /probe/: console.error: decoder lost")'
expect_problems "and so does one in the app's page" "chrome: page /: uncaught: TypeError: x is null" \
  chrome 'errors.append("page /: uncaught: TypeError: x is null")'
expect_problems "an upload cut short fails" "chrome: the server received 2147483648 of 4294967296 bytes from slices" \
  chrome 'uploads["slices"].update(received=2 << 30, complete=False)'
expect_problems "an upload that does not resume after a failed append fails" \
  "firefox: 1 append from bytes failed and the probe resumed 0 times" firefox 'probe["upload"]["bytes"]["resumes"] = 0'
expect_problems "a browser that holds a file's slices in memory fails" \
  "chrome grew by 300 MiB while uploading 4 GiB from slices, over its 256 MiB" \
  chrome 'uploads["slices"]["growth"] = 300 << 20'
expect_problems "a browser that holds the bytes it read in memory fails" \
  "firefox grew by 4200 MiB while uploading 4 GiB from bytes, over its 2048 MiB" \
  firefox 'uploads["bytes"]["growth"] = 4200 << 20'

# The app's page loads the error hook first, and what it posts is kept.
got=$(python3 - <<'EOF_PY' 2>&1
import http.server, os, sys, tempfile, threading, urllib.request
sys.path.insert(0, "tools")
import web_requests
web, run = tempfile.mkdtemp(), web_requests.Run()
with open(os.path.join(web, "index.html"), "w") as page:
    page.write("<html><head><title>app</title></head></html>")
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), web_requests.handler(web, run))
threading.Thread(target=server.serve_forever, daemon=True).start()
origin = f"http://127.0.0.1:{server.server_address[1]}"
print(urllib.request.urlopen(f"{origin}/").read().decode())
print(urllib.request.urlopen(f"{origin}/probe/errors.js").status)
urllib.request.urlopen(urllib.request.Request(f"{origin}/errors", b"page /: console.error: lost", method="POST"))
print(run.errors)
EOF_PY
)
[[ $got == "<html><head><script src=\"/probe/errors.js\"></script><title>app</title></head></html>
200
['page /: console.error: lost']" ]] && ok "the app's page loads the error hook, whose posts are kept" ||
  fail "the hook in the app's page: $got"

# The hook itself, and the node drivers' side of it, in Chrome and Firefox on a page that fails on purpose.
capture node --test tools/web_probe/errors_test.mjs
expect_result "errors.js reports a page's uncaught errors, unhandled rejections and console.error calls" 0 "# fail 0"

finish
