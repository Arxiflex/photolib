#!/usr/bin/env bash
# tools/offline.sh runs a test suite with egress blocked: a connection to anything but loopback fails at once, and so
# does DNS, while loopback servers, Unix sockets and the build tools that fetch pinned dependencies keep working.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/probe.py" <<'PY'
import errno, socket, sys, threading
family = {"4": socket.AF_INET, "6": socket.AF_INET6, "unix": socket.AF_UNIX}[sys.argv[1]]
kind = socket.SOCK_DGRAM if sys.argv[2] == "udp" else socket.SOCK_STREAM
s = socket.socket(family, kind)
s.settimeout(1)
try:
    if sys.argv[3] == "listen":
        server = socket.socket(family, kind)
        server.bind(("::1" if family == socket.AF_INET6 else "127.0.0.1", 0))
        server.listen()
        threading.Thread(target=server.accept, daemon=True).start()
        target = server.getsockname()[:2]
    elif sys.argv[3] == "path":
        server = socket.socket(family, kind)
        server.bind(sys.argv[4])
        server.listen()
        target = sys.argv[4]
    else:
        target = (sys.argv[3], int(sys.argv[4]))
    if kind == socket.SOCK_DGRAM:
        s.sendto(b"x", target)
        print("sent")
    else:
        s.connect(target)
        print("connected")
except OSError as e:
    print(errno.errorcode.get(e.errno, str(e)))
PY

probe() {
  capture bash tools/offline.sh python3 "$TMP/probe.py" "$@"
}

probe 4 tcp 192.0.2.1 443
expect_result "a TCP connection to another host is refused at once" 0 ENETUNREACH "offline: blocked 192.0.2.1 port 443"
probe 6 tcp 2001:db8::1 443
expect_result "so is one over IPv6" 0 ENETUNREACH "offline: blocked 2001:db8::1 port 443"
probe 4 udp 192.0.2.1 443
expect_result "a datagram to another host is refused" 0 ENETUNREACH
probe 4 udp 127.0.0.53 53
expect_result "DNS is refused even on loopback, where a resolver would forward it" 0 ENETUNREACH
capture bash tools/offline.sh python3 -c 'import socket; socket.getaddrinfo("example.com", 443)'
expect_result "so a name does not resolve" failure gaierror "offline: blocked lookup of example.com"
capture bash tools/offline.sh python3 -c 'import socket; socket.getaddrinfo("localhost", 443)'
expect_result "but localhost does" 0
probe 4 tcp listen
expect_result "a loopback server is reachable" 0 connected
probe 6 tcp listen
expect_result "and so is one on ::1" 0 connected
probe 6 tcp ::ffff:127.0.0.1 9
[[ $OUT != *offline:* ]] && ok "an IPv4-mapped loopback address is loopback" || fail "::ffff:127.0.0.1 was blocked: $OUT"
probe unix tcp path "$TMP/socket"
expect_result "a Unix socket is reachable" 0 connected

capture bash tools/offline.sh bash -c "python3 $TMP/probe.py 4 tcp 192.0.2.1 443"
expect_result "a child of the suite is blocked too" 0 ENETUNREACH
cp "$(python3 -c 'import sys; print(sys.executable)')" "$TMP/cargo"
capture bash tools/offline.sh "$TMP/cargo" "$TMP/probe.py" 4 tcp 192.0.2.1 443
[[ $OUT != *offline:* && $OUT != *ENETUNREACH* ]] && ok "cargo, which fetches pinned crates, is not blocked" ||
  fail "a build tool was blocked: $OUT"

capture bash tools/offline.sh bash -c 'exit 3'
expect_result "the suite's exit status is kept" 3
[[ $(bash tools/offline.sh env | grep ^PHOTOLIB_ | sort) == "$(env | grep ^PHOTOLIB_ | sort)" ]] &&
  ok "the suite gets no PHOTOLIB_ variable, which photolibd and its config tests would read as a setting" ||
  fail "offline.sh exports a PHOTOLIB_ variable: $(bash tools/offline.sh env | grep ^PHOTOLIB_)"

# A pinned tool or model that is not cached when egress is blocked is named, with the command that fetches it, and no
# download is tried (photolib-design#441).
fetchers=("python3 tools/ml/fetch.py yunet")
[[ $(uname -m) != x86_64 ]] || fetchers+=("bash tools/video/ffmpeg.sh" "bash tools/video/ffmpeg.sh --libs")
[[ $(uname -m) != @(x86_64|aarch64) ]] || fetchers+=("bash tools/garage.sh" "bash tools/proxies.sh")
for fetcher in "${fetchers[@]}"; do
  read -ra command <<<"$fetcher"
  capture bash tools/offline.sh env PHOTOLIB_TOOLS_CACHE="$TMP/cold" "${command[@]}"
  [[ $STATUS -ne 0 && $OUT == *"egress is blocked"*"fetch it first: $fetcher" && $OUT != *offline:* ]] &&
    ok "offline, $fetcher names what is missing and how to fetch it" || fail "offline, $fetcher: $OUT"
done

finish
