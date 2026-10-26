#!/usr/bin/env bash
# The iOS backup spike (M0-32): the strategy ADR, the report and its probe, which runs PhotoKitProbe.swift on an iPhone
# or simulator against a local upload sink. Xcode, xcrun and Flutter are stubs here; the sink runs for real.
# shellcheck disable=SC2016 # patterns match literal backticks
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool curl
cd "$REPO_ROOT" || exit 1

REPORT=docs/dev/ios-backup-spike.md
ADR=docs/adr/0049-ios-backup-strategy.md
SWIFT=app/ios/RunnerTests/PhotoKitProbe.swift
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("", 0)); print(s.getsockname()[1])'; }
up() { curl -s -o /dev/null "http://localhost:$1/"; }

# --- the sink: accepts uploads, discards the bytes and logs what iOS sent
port=$(free_port)
python3 tools/ios/probe.py sink "$port" "$TMP/sink.jsonl" &
sink_pid=$!
for _ in {1..50}; do up "$port" && break; sleep 0.1; done
head -c 3000 /dev/zero >"$TMP/body"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST --data-binary @"$TMP/body" \
  -H 'Upload-Draft-Interop-Version: 6' -H 'Upload-Complete: ?1' "http://localhost:$port/upload/8")
continued=$(curl -sv -o /dev/null --expect100-timeout 5 -H 'Expect: 100-continue' --data-binary @"$TMP/body" \
  "http://localhost:$port/upload/8" 2>&1)
kill "$sink_pid"
[[ $continued == *"< HTTP/1.1 100 Continue"* ]] && ok "the sink lets a client that expects 100-continue send at once" ||
  fail "the sink never answers 100 Continue: $continued"
[[ $code == 201 ]] && ok "the sink answers an upload with 201" || fail "the sink answered $code"
python3 - "$TMP/sink.jsonl" <<'PY' && ok "the sink logs the bytes and the Upload-* headers" || fail "sink log: $(cat "$TMP/sink.jsonl")"
import json, sys
entry = json.loads(open(sys.argv[1]).readline())
assert (entry["method"], entry["path"], entry["bytes"]) == ("POST", "/upload/8", 3000), entry
assert entry["headers"] == {"upload-draft-interop-version": "6", "upload-complete": "?1"}, entry
PY

# --- the table: one row per result, a rate per second or MB/s, and the headers iOS sent
cat >"$TMP/probe.jsonl" <<'EOF'
{"metric":"enumerate","count":100000,"seconds":2.5,"bytes":0}
{"metric":"icloud_download","count":0,"seconds":0,"bytes":0}
{"metric":"upload_background_8m","count":4,"seconds":2.0,"bytes":33554432}
EOF
capture python3 tools/ios/probe.py table "$TMP/probe.jsonl" "$TMP/sink.jsonl"
expect_result "the table has a row per result with its rate" 0 \
  '| enumerate | 100,000 | 2.500 | 40,000/s |' '| icloud_download | 0 | 0.000 | — |' \
  '| upload_background_8m | 4 | 2.000 | 16.8 MB/s |' \
  'Upload headers sent: upload-complete: ?1; upload-draft-interop-version: 6'
capture python3 tools/ios/probe.py table "$TMP/probe.jsonl" "$TMP/missing.jsonl"
expect_result "the table says when nothing reached the sink" 0 'Upload headers sent: none'
: >"$TMP/empty.jsonl"
capture python3 tools/ios/probe.py table "$TMP/empty.jsonl" "$TMP/sink.jsonl"
expect_result "no results fail the table" failure "no results"

# --- the probe, in a copy of the checkout with stubbed Apple and Flutter tools
mkdir -p "$TMP/repo/tools/ios" "$TMP/repo/app/ios/Runner.xcodeproj" "$TMP/bin"
cp tools/ios/photokit_probe.sh tools/ios/probe.py "$TMP/repo/tools/ios/"
cp app/ios/Runner.xcodeproj/project.pbxproj "$TMP/repo/app/ios/Runner.xcodeproj/"
for tool in uname xcrun flutter xcodebuild scutil; do
  cat >"$TMP/bin/$tool" <<'STUB'
#!/usr/bin/env bash
echo "$(basename "$0") $* @${PWD##*/}" >>"$CALLS"
case "$(basename "$0")" in
  uname) echo "${STUB_OS:-Darwin}" ;;
  scutil) echo mac-mini ;;
  xcrun) [[ $2 != list ]] || printf -- '-- iOS 26.1 --\n    iPad (A16) (AAAAAAAA-1111-2222-3333-444444444444) (Shutdown)\n    iPhone 17 (1A2B3C4D-1111-2222-3333-444455556666) (Shutdown)\n' ;;
  xcodebuild)
    env | grep '^TEST_RUNNER_' | sort >>"$CALLS"
    [[ $TEST_RUNNER_PROBE_SINK != *localhost* ]] ||
      curl -s -o /dev/null -X POST --data-binary probe -H 'Upload-Draft-Interop-Version: 6' "$TEST_RUNNER_PROBE_SINK/upload/8"
    echo 'Test Suite PhotoKitProbe started'
    [[ -n ${STUB_SILENT:-} ]] || echo 'PROBE {"metric":"enumerate","count":100000,"seconds":2.5,"bytes":0}'
    exit "${XCODEBUILD_EXIT:-0}" ;;
esac
STUB
  chmod +x "$TMP/bin/$tool"
done

# probe <args...>: exit status in STATUS, output in OUT, every tool call in LOG.
probe() {
  export CALLS="$TMP/calls"
  : >"$CALLS"
  PROBE_PORT=$(free_port)
  OUT=$(PROBE_PORT=$PROBE_PORT PATH="$TMP/bin:$PATH" bash "$TMP/repo/tools/ios/photokit_probe.sh" --out "$TMP/out" "$@" 2>&1)
  STATUS=$?
  LOG=$(<"$CALLS")
}
has() {
  [[ $LOG == *"$2"* ]] && ok "$1" || fail "$1: no '$2' in $LOG $OUT"
}

sim=1A2B3C4D-1111-2222-3333-444455556666
probe
[[ $STATUS -eq 0 ]] && ok "a simulator run passes" || fail "a simulator run failed ($STATUS): $OUT"
has "boots the first iPhone simulator" "xcrun simctl bootstatus $sim -b"
has "grants the app full photo access" "xcrun simctl privacy $sim grant photos org.photolib.photolib"
has "prepares the Xcode project for the simulator" "flutter build ios --config-only --debug --simulator @app"
has "runs only the probe on the simulator" \
  "xcodebuild test -workspace app/ios/Runner.xcworkspace -scheme Runner -destination id=$sim -only-testing:RunnerTests/PhotoKitProbe"
has "seeds the simulator to 100k assets" "TEST_RUNNER_PROBE_SEED=100000"
has "uploads to the sink on the Mac" "TEST_RUNNER_PROBE_SINK=http://localhost:$PROBE_PORT"
[[ $OUT == *'| enumerate | 100,000 | 2.500 | 40,000/s |'* && $OUT == *'upload-draft-interop-version: 6'* ]] &&
  ok "prints the results and the headers the sink saw" || fail "no results table: $OUT"
grep -qx '{"metric":"enumerate","count":100000,"seconds":2.5,"bytes":0}' "$TMP/out/probe.jsonl" &&
  ok "keeps the raw results" || fail "probe.jsonl: $(cat "$TMP/out/probe.jsonl")"
up "$PROBE_PORT" && fail "the sink outlives the probe" || ok "the sink stops with the probe"

probe --seed 500
has "--seed sets the simulator's size" "TEST_RUNNER_PROBE_SEED=500"

probe --device 00008110-DEV -- DEVELOPMENT_TEAM=T1 -allowProvisioningUpdates
[[ $STATUS -eq 0 ]] && ok "a phone run passes" || fail "a phone run failed ($STATUS): $OUT"
has "runs on the phone with the signing arguments" \
  "-destination id=00008110-DEV -only-testing:RunnerTests/PhotoKitProbe DEVELOPMENT_TEAM=T1 -allowProvisioningUpdates"
has "prepares the Xcode project for a phone" "flutter build ios --config-only --debug @app"
has "never seeds a phone's library" "TEST_RUNNER_PROBE_SEED=0"
has "uploads to the Mac by its local name" "TEST_RUNNER_PROBE_SINK=http://mac-mini.local:$PROBE_PORT"
[[ $LOG != *"simctl"* && $LOG != *"--simulator"* ]] && ok "leaves the simulators alone" || fail "touched a simulator: $LOG"

probe --device 00008110-DEV --seed 5
[[ $STATUS -eq 2 && $OUT == *phone* ]] && ok "refuses to seed a phone" || fail "seeded a phone ($STATUS): $OUT"
probe --bogus
[[ $STATUS -eq 2 && $OUT == *usage* ]] && ok "an unknown option is a usage error" || fail "--bogus: $STATUS $OUT"
STUB_OS=Linux probe
[[ $STATUS -eq 2 && $OUT == *macOS* && $LOG != *xcodebuild* ]] && ok "needs macOS" || fail "ran off macOS: $STATUS $OUT"
XCODEBUILD_EXIT=65 probe
[[ $STATUS -ne 0 ]] && ok "a failing test run fails the probe" || fail "a failing xcodebuild passed: $OUT"
STUB_SILENT=1 probe
[[ $STATUS -ne 0 && $OUT == *"no results"* ]] && ok "a run without results fails" || fail "no results passed: $OUT"

# --- the XCTest it runs, wired into RunnerTests, and the app's photo-library purpose string
assert_matches "$SWIFT" '^final class PhotoKitProbe: XCTestCase' "is the PhotoKitProbe test case"
assert_matches "$SWIFT" 'func testProbe\(\) throws' "has the one test the probe runs"
assert_matches "$SWIFT" 'XCTSkipUnless\(.*PROBE_RUN' "is skipped unless the probe runs it"
# The build phase's files, not the build file entries above them; captured whole, as an early grep -q would end awk.
sources=$(awk '/files = \(/ { block = ""; on = 1 } on { block = block $0 } on && /\);/ { on = 0 }
  !on && block ~ /RunnerTests\.swift in Sources/ { print block; block = "" }' app/ios/Runner.xcodeproj/project.pbxproj)
[[ $sources == *'PhotoKitProbe.swift in Sources'* ]] && ok "RunnerTests compiles PhotoKitProbe.swift" ||
  fail "PhotoKitProbe.swift is not in RunnerTests' sources"
[[ $(grep -c 'PhotoKitProbe\.swift in Sources' app/ios/Runner.xcodeproj/project.pbxproj) -eq 2 ]] &&
  ok "only RunnerTests compiles the probe, never the app" || fail "PhotoKitProbe.swift is built by another target"
assert_prose app/ios/Runner/Info.plist '<key>NSPhotoLibraryUsageDescription</key>[[:space:]]*<string>[^<]+</string>' \
  "the app explains its photo-library access"

# --- the report: a row per metric the probe prints, the API facts and how to fill it
metrics=$(grep -oE '(report|thumbnails|upload)\("[a-z0-9_]+"' "$SWIFT" | cut -d'"' -f2)
[[ $(wc -w <<<"$metrics") -ge 14 ]] && ok "the probe reports at least 14 metrics" || fail "metrics: $metrics"
for metric in $metrics; do
  assert_matches "$REPORT" "^\| \`$metric\` \|" "has a row for $metric"
done
assert_patterns assert_prose "$REPORT" \
  'bash tools/ios/photokit_probe\.sh' "explains how a run fills the table" \
  '\(\.\./adr/0049-ios-backup-strategy\.md\)' "links the decision" \
  'BGContinuedProcessingTask[^.]*iOS 26' "records the continued-processing task" \
  'app switcher[^.]*cancels' "records that closing the app cancels continued processing" \
  'PHBackgroundResourceUploadExtension[^.]*26\.1[^.]*PHBackgroundResourceUploadJobExtension[^.]*27' \
  "records the upload extension and its iOS 27 successor" \
  'not available in the Simulator' "records that the extension needs a phone" \
  'jobLimit' "records the extension's in-flight limit" \
  'retr[a-z]* [^.]*once' "records that a job is retried once" \
  '`OPTIONS`[^.]*`Upload-Limit`[^.]*`104`' "records the extension's server requirements" \
  'draft-ietf-httpbis-resumable-upload-01' "records the resumable-upload draft of URLSession" \
  '`BackgroundUploadURLBase` is fixed at build time' "records that the extension's base URL is fixed per build"
assert_prose docs/dev/README.md '\(ios-backup-spike\.md\)' "the developer guide links the report"

# --- the decision
assert_matches "$ADR" '^\* \*\*Status\*\*: Accepted \(owner answered, 2026-10-17\)' "is Accepted"
assert_matches docs/adr/README.md '\(0049-ios-backup-strategy\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-17' \
  "the index lists ADR-0049 as Accepted"
assert_patterns assert_prose "$ADR" \
  '\(\.\./dev/ios-backup-spike\.md\)' "links the report" \
  'Standard libraries[^.]*upload extension' "sends standard libraries through the system upload extension" \
  'Private libraries never[^.]*extension' "keeps private libraries off the extension" \
  'background `URLSession`[^.]*files' "uploads prepared files through background URLSession" \
  '`BGProcessingTask`' "prepares uploads in processing tasks" \
  '`BGContinuedProcessingTask`[^.]*Back up now' "runs Back up now as a continued-processing task" \
  'upload intent' "gives the extension pre-registered upload intents" \
  '32 files' "bounds what the OS holds at once" \
  'client certificate' "keeps mutual TLS on the app's path" \
  'force-quit' "states what force-quitting stops" \
  'rejects other hosts, standard libraries fall back to the app.s path' \
  "falls back to the app's path if iOS enforces BackgroundUploadURLBase" \
  'photolibd sends no `104`[^.]*ADR-0061' "records that photolibd sends no 104 with the upload's Location" \
  'Before M2-20, a phone test[^.]*without it[^.]*`/upload` learns to send `104`' "tests the extension without 104 on a phone first" \
  'M2-19 builds the app.s path first[^.]*M2-20[^.]*once a phone' "builds the app's path first, the extension once proven" \
  'owner sets[^.]*name and domain[^.]*testing[^.]*ADR-0023' "keeps the placeholder until the owner names the domain"
assert_prose docs/adr/0061-resumable-uploads.md 'upload extension expects `104`[^.]*ADR-0049' \
  "ADR-0061 says what the missing 104 means for the upload extension"
assert_prose AGENTS.md 'ios-backup-spike\.md.*tools/ios/photokit_probe\.sh' "AGENTS.md names the report and the probe"
assert_prose tools/README.md 'ios/photokit_probe\.sh' "tools/README.md names the probe"

finish
