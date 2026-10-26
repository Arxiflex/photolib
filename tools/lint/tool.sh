#!/usr/bin/env bash
# Runs a linter of the lint ratchet (tools/lint/ratchet.py) at the release pinned here, so that every machine counts
# the findings the baseline counts: downloaded once into the per-user tools cache and checked against its SHA-256 by
# tools/fetch_release.sh; eslint and its TypeScript parser come from npm. ktlint needs java.
#
#   tools/lint/tool.sh <shellcheck|ruff|swiftlint|clang-tidy|ktlint|eslint> [arguments...]
set -euo pipefail

NAME=${1:?usage: tools/lint/tool.sh <tool> [arguments...]}
shift
# Outside the checkout, which may be on a noexec mount where the tools cannot start.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
PLATFORM=$(uname -s)-$(uname -m)
PLATFORM=${PLATFORM/aarch64/arm64}
GITHUB=https://github.com
EXTRA=()

# pin <version> <url> <sha256> <file in the download>, for this platform
pin() { VERSION=$1 URL=$2 SHA=$3 FILE=${4:-$FILE}; }
case $NAME:$PLATFORM in
  shellcheck:*)
    v=0.11.0 base=$GITHUB/koalaman/shellcheck/releases/download/v$v/shellcheck-v$v FILE=shellcheck-v$v/shellcheck
    case $PLATFORM in
      Linux-x86_64) pin $v "$base.linux.x86_64.tar.xz" 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 ;;
      Linux-arm64) pin $v "$base.linux.aarch64.tar.xz" 12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588 ;;
      Darwin-x86_64) pin $v "$base.darwin.x86_64.tar.xz" 3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6 ;;
      Darwin-arm64) pin $v "$base.darwin.aarch64.tar.xz" 56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79 ;;
    esac
    ;;
  ruff:*)
    v=0.17.1 target=''
    case $PLATFORM in
      Linux-x86_64) target=x86_64-unknown-linux-gnu sha=a293ac937715ae6fb6b64da86761598379e6149f40fbc00fde9ba8a2a562ac65 ;;
      Linux-arm64) target=aarch64-unknown-linux-gnu sha=d3ead1f0ed779e777a034ccd9286be6bd9bd3cdaba732ff9797f8288a283e9e2 ;;
      Darwin-x86_64) target=x86_64-apple-darwin sha=88ee16f88dba9d440e06375f46898ec85baf578042ad086764d5a33558bb6e17 ;;
      Darwin-arm64) target=aarch64-apple-darwin sha=1c8e6e36538eaa0b996378a20c226403c4ca6369ac24884751b024d3a9530b86 ;;
    esac
    [[ -z $target ]] || pin $v "$GITHUB/astral-sh/ruff/releases/download/$v/ruff-$target.tar.gz" "$sha" "ruff-$target/ruff"
    ;;
  swiftlint:*)
    v=0.65.1 base=$GITHUB/realm/SwiftLint/releases/download/0.65.1
    case $PLATFORM in
      Linux-x86_64) pin $v "$base/swiftlint_linux_amd64.zip" \
        caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d swiftlint-static ;;
      Linux-arm64) pin $v "$base/swiftlint_linux_arm64.zip" \
        9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8 swiftlint-static ;;
      Darwin-*) pin $v "$base/portable_swiftlint.zip" c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0 \
        swiftlint ;;
    esac
    ;;
  clang-tidy:*)
    # LLVM's clang-tidy as the PyPI wheel ships it: a static binary, and the compiler's own headers next to it.
    v=22.1.8 wheel='' EXTRA=('clang_tidy/data/lib/*')
    case $PLATFORM in
      Linux-x86_64) wheel=manylinux_2_27_x86_64.manylinux_2_28_x86_64
        sha=1a3de07ba82d4403d8b692ae63a5520d4db5c606014c92c24bbcef9259057bf1 ;;
      Linux-arm64) wheel=manylinux_2_26_aarch64.manylinux_2_28_aarch64
        sha=1eaddaa7415e8c5e39aeefbfd15174f1ab2a671c86f7ebb200eb523cf9465559 ;;
      Darwin-x86_64) wheel=macosx_10_9_x86_64 sha=04b6c97bcdc032763d0d924531def281acd0b5a939bcc79994cbf3c6fe83e1ae ;;
      Darwin-arm64) wheel=macosx_11_0_arm64 sha=916d7cbc9590e719459738fedc5ba76ac91f128d671390e574a0779014c84d73 ;;
    esac
    [[ -z $wheel ]] || pin $v \
      "https://files.pythonhosted.org/packages/py2.py3/c/clang-tidy/clang_tidy-$v-py2.py3-none-$wheel.whl" "$sha" \
      clang_tidy/data/bin/clang-tidy
    ;;
  ktlint:*)
    command -v java >/dev/null || { echo "'java' (a JDK 11 or later) is required for ktlint" >&2; exit 1; }
    pin 1.8.0 "$GITHUB/pinterest/ktlint/releases/download/1.8.0/ktlint" \
      a3fd620207d5c40da6ca789b95e7f823c54e854b7fade7f613e91096a3706d75 ktlint
    ;;
  eslint:*)
    # eslint.config.mjs finds the parser next to the eslint that runs it.
    PACKAGES=(eslint@10.13.0 typescript-eslint@8.71.2 typescript@6.0.3)
    INSTALL=${PACKAGES[*]}
    INSTALL=$CACHE/eslint-${INSTALL// /-}
    if ! "$INSTALL/node_modules/.bin/eslint" --version >/dev/null 2>&1; then
      command -v npm >/dev/null || { echo "'npm' is required to fetch eslint" >&2; exit 1; }
      (umask 077 && mkdir -p "$CACHE")
      rm -rf "$INSTALL"
      npm install --prefix "$INSTALL" --ignore-scripts --no-audit --no-fund --loglevel=error "${PACKAGES[@]}" >&2 ||
        npm install --prefix "$INSTALL" --ignore-scripts --no-audit --no-fund --loglevel=error "${PACKAGES[@]}" >&2
    fi
    exec "$INSTALL/node_modules/.bin/eslint" "$@"
    ;;
  *)
    echo "tools/lint/tool.sh: unknown tool '$NAME'" >&2
    exit 2
    ;;
esac
if [[ -z ${URL:-} ]]; then
  echo "$NAME has no pinned release for $PLATFORM" >&2
  exit 1
fi

DIR=$CACHE/$NAME-$VERSION-$PLATFORM
fetched=true
[[ -x $DIR/$FILE ]] || fetched=false
for extra in ${EXTRA[@]+"${EXTRA[@]}"}; do
  compgen -G "$DIR/$extra" >/dev/null || fetched=false # fetch_release.sh before photolib-design#575 left none
done
if ! $fetched; then
  (umask 077 && mkdir -p "$CACHE")
  if [[ ! -O $CACHE ]]; then
    echo "$CACHE is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
    exit 1
  fi
  bash "$(dirname "${BASH_SOURCE[0]}")/../fetch_release.sh" "$URL" "$SHA" "$DIR" "$FILE" ${EXTRA[@]+"${EXTRA[@]}"}
  chmod +x "$DIR/$FILE"
fi
exec "$DIR/$FILE" "$@"
