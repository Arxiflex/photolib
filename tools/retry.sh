# shellcheck shell=bash
# Sourced by the tools that download or install something, so that a mirror's 503 or a dropped connection is waited out
# instead of failing a build (run 40232538815). RETRY_DELAY (seconds) fixes the pause between runs, as tests do with 0;
# RETRY_COUNT the curl retries (6); RETRY_TIMEOUT is the seconds one download attempt may take (default 600).
#
#   download <url> <file> <sha256>   curl with retries and timeouts, then the SHA-256 check; no file on failure
#   retry <times> <command...>       runs the command again, pausing 2, 4, 8 ... seconds, up to <times> runs

download() {
  local url=$1 file=$2 pinned=$3 actual
  local flags=(-fsSL --retry "${RETRY_COUNT:-6}" --retry-all-errors --retry-max-time 300 --connect-timeout 20
    --max-time "${RETRY_TIMEOUT:-600}")
  [[ -z ${RETRY_DELAY:-} ]] || flags+=(--retry-delay "$RETRY_DELAY")
  # A body that arrives whole but wrong (a proxy's page) is fetched once more, too.
  for _ in 1 2; do
    if curl "${flags[@]}" -o "$file" "$url"; then
      if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum <"$file"); else actual=$(shasum -a 256 <"$file"); fi
      [[ ${actual%% *} != "$pinned" ]] || return 0
    fi
    rm -f "$file"
  done
  echo "::error::download of $url failed, or does not match the pinned SHA-256 $pinned" >&2
  return 1
}

retry() {
  local times=$1 n=1 pause=2
  shift
  until "$@"; do
    if ((n >= times)); then
      echo "retry: '$*' failed $times times" >&2
      return 1
    fi
    echo "retry: '$*' failed, once more in ${RETRY_DELAY:-$pause} s" >&2
    sleep "${RETRY_DELAY:-$pause}"
    pause=$((pause * 2)) n=$((n + 1))
  done
}
