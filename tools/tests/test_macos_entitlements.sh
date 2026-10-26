#!/usr/bin/env bash
# The sandboxed macOS app reaches the internet (map tiles, model downloads, the server) only with the outbound network
# entitlement; both entitlements files grant it as boolean true (parsed, not grepped), and nothing the app does not
# need is added: iOS has no sandbox entitlement to extend (ADR-0394).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

# entitlement <file> <key>: the value of the key, or "missing".
entitlement() {
  timeout 30 python3 -I -c 'import plistlib, sys
print(plistlib.load(open(sys.argv[1], "rb")).get(sys.argv[2], "missing"))' "$1" "$2"
}

for file in app/macos/Runner/Release.entitlements app/macos/Runner/DebugProfile.entitlements; do
  if [[ $(entitlement "$file" com.apple.security.network.client) == True ]]; then
    ok "$file grants network.client"
  else
    fail "$file: network.client is not true"
  fi
  if [[ $(entitlement "$file" com.apple.security.app-sandbox) == True ]]; then
    ok "$file keeps the App Sandbox"
  else
    fail "$file: the App Sandbox is gone"
  fi
done
if [[ $(entitlement app/macos/Runner/Release.entitlements com.apple.security.network.server) == missing ]]; then
  ok "the release app opens no listening socket (network.server is for the debug service only)"
else
  fail "Release.entitlements grants network.server"
fi
if [[ $(entitlement app/ios/Runner/Runner.entitlements com.apple.security.app-sandbox) == missing ]]; then
  ok "iOS needs no sandbox or network entitlement"
else
  fail "Runner.entitlements for iOS holds a macOS sandbox key"
fi

finish
