#!/usr/bin/env bash
# tools/retry.sh, which the tools that download or install something share: `download` fetches a URL with curl's retries
# (a 503 from the mirror is waited out) and refuses what does not match the pinned SHA-256, leaving no partial file;
# `retry` runs a command again with a growing pause. A local HTTP server plays the mirror (run 40232538815 failed
# on a 503 from Garage's).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool curl
require_tool python3

SANDBOX=$(mktemp -d)
trap 'kill "${SERVER:-}" 2>/dev/null; rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/tools"
cp "$REPO_ROOT/tools/retry.sh" "$SANDBOX/tools/" 2>/dev/null
export RETRY_DELAY=1 RETRY_COUNT=1

# A server whose first FAILS requests for /flaky answer 503 (as the Garage mirror did); /file is always served.
cat >"$SANDBOX/server.py" <<'PY'
import http.server, sys
fails, seen = int(sys.argv[2]), 0
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global seen
        if self.path == "/flaky" and seen < fails:
            seen += 1
            self.send_response(503)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", "5")
        self.end_headers()
        self.wfile.write(b"bytes")
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
open(sys.argv[1], "w").write(str(server.server_port))
server.serve_forever()
PY
start_server() {
  rm -f "$SANDBOX/port"
  python3 "$SANDBOX/server.py" "$SANDBOX/port" "$1" &
  SERVER=$!
  for _ in {1..50}; do [[ -s $SANDBOX/port ]] && break; sleep 0.1; done
  BASE="http://127.0.0.1:$(cat "$SANDBOX/port")"
}
SUM=$(printf bytes | sha256sum | cut -d' ' -f1)
# shellcheck disable=SC2016 # the inner script expands its own arguments
run() { capture bash -c 'source "$1/tools/retry.sh"; shift; "$@"' _ "$SANDBOX" "$@"; }

start_server 3
run download "$BASE/flaky" "$SANDBOX/out" "$SUM"
expect_result "download waits out three 503s from the mirror" 0
[[ $(cat "$SANDBOX/out" 2>/dev/null) == bytes ]] && ok "and has the file" || fail "no file after the 503s: $OUT"
kill "$SERVER"

start_server 0
run download "$BASE/file" "$SANDBOX/bad" "$(printf %064d 0)"
expect_result "download refuses a file that is not the pinned one" failure "does not match the pinned SHA-256"
[[ ! -e $SANDBOX/bad ]] && ok "and leaves no file" || fail "a refused download was left in place"
kill "$SERVER"

RETRY_TIMEOUT=2 run download "http://127.0.0.1:1/none" "$SANDBOX/none" "$SUM"
expect_result "download of a dead host fails with the URL named" failure "http://127.0.0.1:1/none"
[[ ! -e $SANDBOX/none ]] && ok "and leaves no file" || fail "a failed download left a file"

# retry <times> <command...>: the third run passes
echo 0 >"$SANDBOX/count"
cat >"$SANDBOX/flaky.sh" <<EOF
n=\$(( \$(cat "$SANDBOX/count") + 1 )); echo \$n >"$SANDBOX/count"; [[ \$n -ge \${PASS_AT:-3} ]]
EOF
run retry 3 bash "$SANDBOX/flaky.sh"
expect_result "retry runs a command that fails twice a third time" 0 "once more"
echo 0 >"$SANDBOX/count"
PASS_AT=9 run retry 3 bash "$SANDBOX/flaky.sh"
expect_result "retry gives up after the given number of runs and fails" failure "failed 3 times"
[[ $(cat "$SANDBOX/count") == 3 ]] && ok "it ran 3 times" || fail "it ran $(cat "$SANDBOX/count") times"

[[ $FAILURES -eq 0 ]] || exit 1
