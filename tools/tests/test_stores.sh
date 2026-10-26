#!/usr/bin/env bash
# The app stores' listings, metadata and recipes (ADR-0249): check_stores.py; appstreamcli validates the AppStream
# metadata of the Linux packages as software centres read it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool appstreamcli
python3 "$REPO_ROOT/tools/tests/check_stores.py" || fail "check_stores.py reported failures"
appstreamcli validate --no-net --pedantic --explain "$REPO_ROOT/app/linux/packaging/org.photolib.photolib.metainfo.xml" &&
  ok "the AppStream metadata is valid" || fail "appstreamcli rejects the AppStream metadata"
finish
