#!/usr/bin/env bash
# Runs Helm, downloaded once into the per-user tools cache by tools/fetch_release.sh at the pinned SHA-256:
#
#   tools/helm.sh template photolib deploy/helm/photolib
set -euo pipefail

VERSION=4.3.0
declare -A SHA256=(
  [linux-amd64]=86584a54def73570558f66f5111cc53dfed56689637ae32c1201205d494f54fb
  [linux-arm64]=31c5794dd55c66a51e6b7d2e2ac7a114ae8b1de41ff1d9ba51748ac973b06a08
  [darwin-amd64]=347a784877e0e20eac865e8d1c36a80f6bb0861d6f29abd34defb6570ef95d92
  [darwin-arm64]=d3870437e1e95b67f8edbde964156c84a26503f560821d40c542441658934fba
)

ARCH=$(uname -m)
ARCH=${ARCH/x86_64/amd64}
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')-${ARCH/aarch64/arm64}
PINNED=${SHA256[$PLATFORM]:-}
[[ -n $PINNED ]] || { echo "Helm $VERSION has no pinned release for $PLATFORM" >&2; exit 1; }
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
HELM=$CACHE/helm-$VERSION/$PLATFORM/helm
[[ -x $HELM ]] || bash "$(dirname "${BASH_SOURCE[0]}")/fetch_release.sh" \
  "https://get.helm.sh/helm-v$VERSION-$PLATFORM.tar.gz" "$PINNED" "$CACHE/helm-$VERSION" "$PLATFORM/helm"
exec "$HELM" "$@"
