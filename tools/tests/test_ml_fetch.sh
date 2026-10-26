#!/usr/bin/env bash
# tools/ml/fetch.py: what the ML runtime spike runs is pinned by SHA-256 in tools/ml/artefacts.json, downloaded once
# into a private cache and refused on a mismatch; archives yield only their listed files. The downloads here are
# file:// URLs, so the test needs no network.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/tools/ml" "$SANDBOX/src/pkg/lib"
cp "$REPO_ROOT/tools/ml/fetch.py" "$SANDBOX/tools/ml/"
printf 'model bytes' >"$SANDBOX/src/model.onnx"
head -c 20000 /dev/zero >"$SANDBOX/src/pkg/lib/libort.so"
echo notice >"$SANDBOX/src/pkg/LICENSE"
tar -czf "$SANDBOX/src/ort.tgz" -C "$SANDBOX/src" pkg
(cd "$SANDBOX/src" && python3 -m zipfile -c ort.zip pkg >/dev/null)
sum() { sha256sum "$SANDBOX/src/$1" | cut -d' ' -f1; }
cat >"$SANDBOX/tools/ml/artefacts.json" <<EOF
{
  "model": {"url": "file://$SANDBOX/src/model.onnx", "sha256": "$(sum model.onnx)", "licence": "MIT"},
  "tampered": {"url": "file://$SANDBOX/src/model.onnx", "sha256": "$(sum model.onnx | tr '0-9a-f' 'f')"},
  "tgz": {"url": "file://$SANDBOX/src/ort.tgz", "sha256": "$(sum ort.tgz)", "files": ["pkg/lib/libort.so"]},
  "zip": {"url": "file://$SANDBOX/src/ort.zip", "sha256": "$(sum ort.zip)", "files": ["pkg/lib/libort.so"]}
}
EOF
fetch() { capture env PHOTOLIB_TOOLS_CACHE="$SANDBOX/cache" python3 "$SANDBOX/tools/ml/fetch.py" "$@"; }
field() { python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)[sys.argv[1]]))' "$1" <<<"$OUT"; }

fetch model tgz zip
expect_result "pinned files download and their local paths print as JSON" 0
[[ $(cat "$(field model)") == 'model bytes' ]] && ok "the model is the pinned file" || fail "model: $OUT"
for archive in tgz zip; do
  file=$(field "$archive")
  [[ $file == */pkg/lib/libort.so && $(wc -c <"$file") -eq 20000 && ! -e ${file%/lib/libort.so}/LICENSE ]] &&
    ok "a .$archive yields only its listed files" || fail "$archive: $OUT"
done
[[ $(stat -c %a "$SANDBOX/cache") == 700 ]] && ok "the cache is private" || fail "cache mode $(stat -c %a "$SANDBOX/cache")"

fetch tampered
expect_result "a download that does not match its pin is refused" failure "SHA-256"
[[ -z $(find "$SANDBOX/cache" -path '*tampered*' -type f) ]] && ok "nothing of it is cached" || fail "tampered was cached"

rm "$SANDBOX/src/model.onnx"
fetch model
expect_result "a second run reads the cache without downloading" 0
[[ $(cat "$(field model)") == 'model bytes' ]] && ok "the cached model is the same file" || fail "cached: $OUT"

fetch nothing
expect_result "an unknown name fails" failure "nothing"

# Windows has neither os.getuid nor fcntl: a stand-in, whose msvcrt.locking logs its calls, gives up the first time as
# Windows does after 10 s and then takes the lock with flock, fetches into the default cache under the temporary
# directory, waiting for the lock and letting go of it.
cat >"$SANDBOX/windows.py" <<'EOF'
import errno, fcntl, os, runpy, sys, types
del os.getuid
sys.modules["fcntl"] = None
msvcrt = types.ModuleType("msvcrt")
msvcrt.LK_UNLCK, msvcrt.LK_LOCK = 0, 1
def locking(fd, mode, nbytes):
    print("locking", mode, nbytes, file=open(os.environ["LOCKS"], "a"))
    if open(os.environ["LOCKS"]).read().count("\n") == 1:
        raise OSError(errno.EDEADLOCK, "Resource deadlock avoided")
    fcntl.flock(fd, fcntl.LOCK_EX if mode else fcntl.LOCK_UN)
msvcrt.locking = locking
sys.modules["msvcrt"] = msvcrt
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
EOF
mkdir "$SANDBOX/tmp"
capture env -u PHOTOLIB_TOOLS_CACHE TMPDIR="$SANDBOX/tmp" LOCKS="$SANDBOX/locks" \
  python3 "$SANDBOX/windows.py" "$SANDBOX/tools/ml/fetch.py" tgz zip
expect_result "on Windows pinned files download too" 0
[[ $(field tgz) == "$SANDBOX/tmp/photolib-tools/ml/tgz-"*/libort.so && $(wc -c <"$(field zip)") -eq 20000 ]] &&
  ok "into photolib-tools under the user's temporary directory" || fail "Windows: $OUT"
[[ $(cat "$SANDBOX/locks" 2>/dev/null) == $'locking 1 1\nlocking 1 1\nlocking 0 1\nlocking 1 1\nlocking 0 1' ]] &&
  ok "each under msvcrt's lock, waited for past Windows' 10 s" || fail "locks: $(cat "$SANDBOX/locks" 2>/dev/null)"

fetch --sizes tgz
expect_result "--sizes prints each runtime file's bytes and gzip bytes" 0 "tgz pkg/lib/libort.so 20000 "

# Two fetches of one artefact at once, as two gates on one machine make them: the second waits for the first's
# download, which a loopback server sends slowly, and both get the whole file.
head -c 800000 /dev/urandom >"$SANDBOX/src/slow.onnx"
python3 -c '
import http.server, sys, time
data, log = open(sys.argv[1], "rb").read(), sys.argv[2]
class Slow(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        open(log, "a").write(self.path + "\n")
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        for i in range(0, len(data), 100000):
            self.wfile.write(data[i:i + 100000])
            time.sleep(0.1)
    def log_message(self, *_):
        pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Slow)
print(server.server_port, flush=True)
server.serve_forever()' "$SANDBOX/src/slow.onnx" "$SANDBOX/gets" >"$SANDBOX/port" &
SERVER=$!
until [[ -s $SANDBOX/port ]]; do sleep 0.1; done
# pin <name> <url> <sha256>: one more artefact in the sandbox's artefacts.json.
pin() {
  python3 - "$SANDBOX/tools/ml/artefacts.json" "$@" <<'EOF'
import json, sys
path, name, url, sha256 = sys.argv[1:]
pins = json.load(open(path))
pins[name] = {"url": url, "sha256": sha256}
json.dump(pins, open(path, "w"))
EOF
}
pin slow "http://127.0.0.1:$(cat "$SANDBOX/port")/slow.onnx" "$(sum slow.onnx)"
# fetch_hash <n>: fetches slow and keeps the SHA-256 of the file it got as soon as it returns.
fetch_hash() {
  local OUT
  OUT=$(env PHOTOLIB_TOOLS_CACHE="$SANDBOX/cache" no_proxy='*' python3 "$SANDBOX/tools/ml/fetch.py" slow) &&
    sha256sum <"$(field slow)" | cut -d' ' -f1 >"$SANDBOX/hash$1"
}
fetch_hash 1 &
first=$!
until [[ -s $SANDBOX/gets ]]; do sleep 0.05; done
fetch_hash 2
wait "$first"
kill "$SERVER"
[[ $(cat "$SANDBOX/gets") == /slow.onnx ]] && ok "two fetches at once download the artefact once" ||
  fail "downloads: $(cat "$SANDBOX/gets")"
[[ $(cat "$SANDBOX/hash1") == "$(sum slow.onnx)" && $(cat "$SANDBOX/hash2") == "$(sum slow.onnx)" ]] &&
  ok "both get the whole file, never a partial one" || fail "hashes: $(cat "$SANDBOX/hash1" "$SANDBOX/hash2")"
leftovers=$(find "$SANDBOX/cache" -path '*slow*' -type f ! -name slow.onnx ! -name .lock)
[[ -z $leftovers ]] && ok "no temporary file is left in the cache" || fail "left: $leftovers"

pin gone "file://$SANDBOX/src/gone.onnx" "$(sum slow.onnx)"
fetch gone
leftovers=$(find "$SANDBOX/cache" -path '*gone*' -type f ! -name .lock)
[[ $STATUS -ne 0 && -z $leftovers ]] && ok "a failed download fails and leaves nothing behind" ||
  fail "gone: $STATUS $leftovers $OUT"

python3 - "$REPO_ROOT/tools/ml/artefacts.json" <<'EOF' && ok "every real pin is an https URL with a SHA-256, models at a commit with a permissive licence" || fail "the real pins"
import json, re, sys
for name, a in json.load(open(sys.argv[1])).items():
    assert a["url"].startswith("https://") and re.fullmatch(r"[0-9a-f]{64}", a["sha256"]), name
    if "fixture" in a:
        # A photograph a test runs the face models on, pinned by hash and never committed: public domain only.
        assert a["licence"] == "Public domain" and a["url"].startswith("https://upload.wikimedia.org/"), name
    elif "files" not in a:
        assert re.search(r"/[0-9a-f]{40}/", a["url"]) and a["licence"] in ("Apache-2.0", "MIT"), name
EOF

finish
