#!/usr/bin/env bash
# Prints the reverse proxies that the proxy template suite (server/crates/photolib-server/tests/proxies.rs) runs, one
# `<name> <path>` line each: Caddy, Traefik and cloudflared as pinned below, fetched once into the per-user tools cache
# and checked against their SHA-256; nginx and Apache httpd (`apache2` or `httpd`, then its module directory) from PATH.
set -euo pipefail

CADDY=2.11.7
TRAEFIK=v3.7.14
CLOUDFLARED=2026.10.0
declare -A SHA256=(
  [caddy-amd64]=727b91701a392de6ebc5027509f548bf39979e5216340d0faed8fa5e69c84f8b
  [caddy-arm64]=d8fc6d179a5d283028a472a5618564f6ad8a86fed513e64f032b3b0b7cc45e42
  [traefik-amd64]=d08641f5de2dd3788097bddab1ce4b29c10a0b788566970db707fa5c94c71f15
  [traefik-arm64]=e5a2d0620cecc01dbc3d8da739db0671fdc030ef1c3b2d90d54f3baaa25d85d3
  [cloudflared-amd64]=d33ff2d14475178d2012c2c56beba87389ac5ded27649519f198a7d3134a99db
  [cloudflared-arm64]=e6422b9d4f72d3194bc5a38676f13667c06666523217b842a877d72a80b5ac08
)

case $(uname -sm) in
  "Linux x86_64") arch=amd64 ;;
  "Linux aarch64") arch=arm64 ;;
  *) echo "proxies.sh: no Caddy, Traefik or cloudflared is pinned for $(uname -sm)" >&2 && exit 1 ;;
esac
cache=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
(umask 077 && mkdir -p "$cache")
if [[ ! -O $cache ]]; then
  echo "proxies.sh: $cache is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
  exit 1
fi
# fetch <name> <version> <url>: the binary of a release, once.
fetch() {
  if [[ ! -x $cache/$1-$2/$1 && -n ${EGRESS_BLOCKED:-} ]]; then
    echo "proxies.sh: $1 $2 is not in $cache, and egress is blocked (tools/offline.sh);" \
      "fetch it first: bash tools/proxies.sh" >&2
    exit 1
  fi
  [[ -x $cache/$1-$2/$1 ]] ||
    bash "$(dirname "${BASH_SOURCE[0]}")/fetch_release.sh" "$3" "${SHA256[$1-$arch]}" "$cache/$1-$2" "$1"
  echo "$1 $cache/$1-$2/$1"
}
fetch caddy "$CADDY" "https://github.com/caddyserver/caddy/releases/download/v$CADDY/caddy_${CADDY}_linux_$arch.tar.gz"
fetch traefik "$TRAEFIK" \
  "https://github.com/traefik/traefik/releases/download/$TRAEFIK/traefik_${TRAEFIK}_linux_$arch.tar.gz"
fetch cloudflared "$CLOUDFLARED" \
  "https://github.com/cloudflare/cloudflared/releases/download/$CLOUDFLARED/cloudflared-linux-$arch"

if ! nginx=$(command -v nginx); then
  echo "proxies.sh: nginx is not on PATH (apt-get install nginx)" >&2
  exit 1
fi
echo "nginx $nginx"
if ! httpd=$(command -v apache2 || command -v httpd); then
  echo "proxies.sh: Apache httpd is not on PATH as apache2 or httpd (apt-get install apache2-bin)" >&2
  exit 1
fi
for modules in "${httpd%/*}/../lib/apache2/modules" /usr/lib/apache2/modules /usr/lib64/httpd/modules \
  /usr/lib/httpd/modules; do
  if [[ -f $modules/mod_proxy_http.so ]]; then
    echo "apache $httpd $(cd "$modules" && pwd)"
    exit 0
  fi
done
echo "proxies.sh: no mod_proxy_http.so beside $httpd" >&2
exit 1
