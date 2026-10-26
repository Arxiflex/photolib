#!/usr/bin/env bash
# photolibd's image (deploy/Dockerfile) as far as it can be checked without a Docker daemon; tools/image.sh builds and
# runs it in the weekly workflow.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DOCKERFILE=$REPO_ROOT/deploy/Dockerfile

unpinned=$(grep -E '^FROM ' "$DOCKERFILE" | grep -Ev '^FROM (scratch|[^ ]+:[^ @]+@sha256:[0-9a-f]{64})( AS [a-z]+)?$')
[[ -z $unpinned ]] && ok "every base image is pinned by digest" || fail "unpinned: $unpinned"
packages=$(sed -n 's/^RUN apk add --no-cache //p' "$DOCKERFILE" | tail -1)
[[ " $packages " == *" vips vips-heif vips-jxl "* && $packages != *magick* && $packages != *poppler* ]] &&
  ok "the image renders with libvips, HEIF and JPEG XL, without its ImageMagick or PDF loaders (ADR-0084)" ||
  fail "the image's libvips packages: $packages"
[[ $(grep -E '^USER ' "$DOCKERFILE" | tail -1) =~ ^USER\ [1-9][0-9]*:[1-9][0-9]*$ ]] &&
  ok "the image runs as an unprivileged user by default" || fail "the image's last USER is not a numeric non-root one"
! grep -q '^VOLUME' "$DOCKERFILE" && ok "the image declares no volume, which would be a mount besides the bind mounts" ||
  fail "the Dockerfile declares a VOLUME"
major=$(sed -nE 's/^ +image: postgres:([0-9]+)\..*/\1/p' "$REPO_ROOT/deploy/compose/compose.yaml")
[[ -n $major ]] && grep -Eq "^RUN apk add .*\bpostgresql$major-client\b" "$DOCKERFILE" && grep -Eq "^RUN apk add .*\bffmpeg\b" \
  "$DOCKERFILE" && grep -Eq "^RUN apk add .*\bexiftool\b" "$DOCKERFILE" &&
  ok "the image has FFmpeg, ExifTool and the pg_dump of the compose file's PostgreSQL $major" ||
  fail "the image lacks FFmpeg, ExifTool or PostgreSQL ${major:-?}'s client programs"
grep -q 'PHOTOLIB_DATA_DIR=/data ' "$DOCKERFILE" && grep -q ':/data$' "$REPO_ROOT/deploy/compose/compose.yaml" &&
  ok "photolibd's data directory is where the compose file mounts it" || fail "data_dir and the compose mount differ"
[[ $(grep -v '^#' "$REPO_ROOT/deploy/Dockerfile.dockerignore") == $'*\n!kernel\n!server\n!tools/synthlib\n**/target' ]] &&
  ok "the build context is the sources photolibd builds from" || fail "Dockerfile.dockerignore sends more than sources"
bash -n "$REPO_ROOT/tools/image.sh" && ok "tools/image.sh parses" || fail "tools/image.sh does not parse"

finish
