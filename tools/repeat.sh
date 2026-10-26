#!/usr/bin/env bash
# Repeats a selection of tests N times with every retry off and fails on any failure: the guard that keeps a flaky test
# from passing the gate on a retry. The gate retries a failing test (CHECK_RETRIES, `retry:` in dart_test.yaml, nextest
# --retries), so a test that fails one run in five passes it; here the first failure fails.
#
#   tools/repeat.sh [-n N] [-k] <test file>...     the tests of these files, each package's together
#   tools/repeat.sh [-n N] [-k] --since <rev>      the test files the diff <rev>...HEAD adds or changes
#   tools/repeat.sh [-n N] [-k] -- <command...>    any command, from the repository root
#   tools/repeat.sh --list ...                     print what would run (directory, command), run nothing
#
# N is 10, or $REPEAT_N, or -n. The first failing run stops the repetition unless -k (keep going) is given, which
# counts every failure; the exit status is 1 on any failure. A test file maps to the runner the gate uses for it:
#   *_test.dart  `flutter test` (or `dart test`) in the package that owns it, `retry: 0` for the run (dart_test.yaml
#                is put back after); a browser test (`@TestOn('browser')`) runs in Chrome
#   tests/*.rs   `cargo nextest run --retries 0 -p <crate> --test <file>`; a src/ file with tests, the tests of its module
#   tools/tests/test_*.sh   `bash <file>`; tools/tests/*.py, the test_*.sh that names it
#   *.test.ts, *.test.mjs, tools/*/test.mjs   `node --test <file>`
# $REPEAT_CARGO_ARGS is added to cargo's (a host that needs `--config 'patch...'`). Under load is the way to find a
# flake: run it beside a busy machine, or `taskset -c 0,1 tools/repeat.sh ...` for a small one.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1
N=${REPEAT_N:-10}
KEEP='' LIST='' SINCE='' FILES=() COMMAND=()

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

while (($#)); do
  case $1 in
    -n) [[ ${2:-} =~ ^[1-9][0-9]*$ ]] || { echo "repeat.sh: -n needs a positive whole number" >&2; exit 2; }
      N=$2 && shift 2 ;;
    -k) KEEP=1 && shift ;;
    --list) LIST=1 && shift ;;
    --since) [[ -n ${2:-} ]] || usage; SINCE=$2 && shift 2 ;;
    --) shift && COMMAND=("$@") && break ;;
    -h | --help) usage ;;
    -*) echo "repeat.sh: unknown option $1" >&2 && usage ;;
    *) FILES+=("$1") && shift ;;
  esac
done
[[ $N =~ ^[1-9][0-9]*$ ]] || { echo "repeat.sh: REPEAT_N must be a positive whole number, not '$N'" >&2; exit 2; }

# Each job is "<dir>\t<command>": the directory it runs in, relative to the repository root, and the command.
JOBS=()
add() { JOBS+=("$1"$'\t'"$2"); }

# up <file> <name>: the nearest directory above the file that holds <name>.
up() {
  local dir
  dir=$(dirname "$ROOT/$1")
  while [[ $dir != "$ROOT" && $dir != / ]]; do
    [[ -e $dir/$2 ]] && { echo "${dir#"$ROOT"/}"; return 0; }
    dir=$(dirname "$dir")
  done
  [[ -e $ROOT/$2 ]] && echo . && return 0
  return 1
}

# group the files of a runner by directory: DART[dir]="file file", so a package's files run in one process
declare -A DART RUST_TEST RUST_LIB NODE SHELLS
declare -a ORDER=()
remember() { # remember <array name> <key> <value>
  local -n map=$1
  [[ -n ${map[$2]:-} ]] || ORDER+=("$1:$2")
  map[$2]+="${map[$2]:+ }$3"
}

map_file() {
  local file=$1 dir rel base
  case $file in
    *_test.dart)
      dir=$(up "$file" pubspec.yaml) || { echo "repeat.sh: no pubspec.yaml above $file" >&2; return 1; }
      remember DART "$dir" "${file#"$dir"/}" ;;
    tools/tests/test_*.sh) remember SHELLS . "$file" ;;
    tools/tests/*.py)
      base=$(basename "$file")
      local found=''
      while IFS= read -r test; do remember SHELLS . "$test" && found=1; done \
        < <(grep -l -- "$base" tools/tests/test_*.sh 2>/dev/null)
      [[ -n $found ]] || add . "$(printf '%q ' python3 "$file")" ;;
    *.rs)
      dir=$(up "$file" Cargo.toml) || { echo "repeat.sh: no Cargo.toml above $file" >&2; return 1; }
      rel=${file#"$dir"/}
      case $rel in
        tests/*) base=${rel#tests/} && remember RUST_TEST "$dir" "${base%%/*}" ;;
        src/*)
          grep -q '#\[\(cfg(test)\|test\|tokio::test\)' "$file" || return 0
          base=${rel#src/} base=${base%.rs} base=${base%/mod} base=${base//\//::}
          [[ $base == lib || $base == main ]] && base=''
          remember RUST_LIB "$dir" "${base:-.}" ;;
        *) return 0 ;;
      esac ;;
    *.test.ts | *.test.mjs | *.test.js | tools/*/test.mjs)
      dir=$(up "$file" package.json) || dir=$(dirname "$file")
      remember NODE "$dir" "${file#"$dir"/}" ;;
    *) return 0 ;;
  esac
}

# crate <dir>: the package name of a crate directory.
crate() { sed -n 's/^name *= *"\(.*\)"/\1/p' "$ROOT/$1/Cargo.toml" | head -n 1; }

# in_browser <dir> <file>...: whether a test file declares @TestOn('browser') (or 'chrome').
in_browser() {
  local dir=$1 file
  shift
  for file in "$@"; do
    grep -q "@TestOn(['\"]\\(browser\\|chrome\\)" "$ROOT/$dir/$file" 2>/dev/null && return 0
  done
  return 1
}

build_jobs() {
  local key kind dir files file flags filters name
  for key in "${ORDER[@]}"; do
    kind=${key%%:*} dir=${key#*:}
    case $kind in
      DART)
        files=${DART[$dir]}
        # shellcheck disable=SC2086 # one path a word; test files have no spaces
        if grep -q "sdk: flutter" "$dir/pubspec.yaml"; then
          if in_browser "$dir" $files; then
            add "$dir" "flutter test --no-pub --platform chrome $files"
          else
            add "$dir" "flutter test --no-pub $files"
          fi
        elif in_browser "$dir" $files; then
          add "$dir" "dart test -p chrome -c dart2js -c dart2wasm $files"
        else
          add "$dir" "dart test $files"
        fi ;;
      RUST_TEST)
        name=$(crate "$dir")
        flags=''
        for file in ${RUST_TEST[$dir]}; do flags+=" --test ${file%.rs}"; done
        add "$dir" "cargo nextest run --retries 0 --no-fail-fast ${REPEAT_CARGO_ARGS:-} -p $name$flags" ;;
      RUST_LIB)
        name=$(crate "$dir")
        filters=''
        for file in ${RUST_LIB[$dir]}; do [[ $file == . ]] && filters='' && break || filters+=" $file"; done
        add "$dir" "cargo nextest run --retries 0 --no-fail-fast ${REPEAT_CARGO_ARGS:-} -p $name --lib$filters" ;;
      NODE) add "$dir" "node --test ${NODE[$dir]}" ;;
      SHELLS) for file in ${SHELLS[$dir]}; do add . "bash $file"; done ;;
    esac
  done
}

if [[ -n $SINCE ]]; then
  paths=$(git diff --name-only --no-renames --diff-filter=AM "$SINCE...HEAD") ||
    { echo "repeat.sh: cannot diff $SINCE...HEAD" >&2; exit 2; }
  while IFS= read -r file; do [[ -z $file ]] || FILES+=("$file"); done <<<"$paths"
fi
if ((${#COMMAND[@]})); then
  add . "$(printf '%q ' "${COMMAND[@]}")"
else
  for file in "${FILES[@]}"; do
    file=${file#./}
    [[ -f $file ]] || { [[ -n $SINCE ]] || echo "repeat.sh: no such file: $file" >&2; continue; }
    map_file "$file" || exit 2
  done
  build_jobs
fi
if ((${#JOBS[@]} == 0)); then
  echo "repeat.sh: no test to repeat${SINCE:+ in the diff $SINCE...HEAD}"
  exit 0
fi
if [[ -n $LIST ]]; then
  for job in "${JOBS[@]}"; do printf '%s\t%s\n' "${job%%$'\t'*}" "${job#*$'\t'}"; done
  exit 0
fi

# no_retry <dir>: the package's dart_test.yaml with `retry: 0`, until restore. A killed run leaves it so (git shows it).
SAVED=()
no_retry() {
  local config=$ROOT/$1/dart_test.yaml
  [[ -f $config ]] && grep -q '^retry:' "$config" && ! grep -q '^retry: *0 *$' "$config" || return 0
  SAVED+=("$config"$'\t'"$(cat "$config"; printf x)")
  sed -i 's/^retry:.*/retry: 0/' "$config"
}
restore() {
  local saved config content
  for saved in ${SAVED[@]+"${SAVED[@]}"}; do
    config=${saved%%$'\t'*} content=${saved#*$'\t'}
    printf '%s' "${content%x}" >"$config"
  done
  SAVED=()
}
trap restore EXIT
trap 'restore; exit 130' INT
trap 'restore; exit 143' TERM HUP

failed=0
for job in "${JOBS[@]}"; do
  dir=${job%%$'\t'*} command=${job#*$'\t'}
  [[ $command != flutter\ test* && $command != dart\ test* ]] || no_retry "$dir"
  passes=0 fails=0
  echo "==> [$dir] $command (x$N, no retries)"
  for ((run = 1; run <= N; run++)); do
    if (cd "$ROOT/$dir" && eval "$command") </dev/null; then
      passes=$((passes + 1))
    else
      fails=$((fails + 1))
      echo "repeat.sh: run $run of $N failed: [$dir] $command" >&2
      [[ -n $KEEP ]] || break
    fi
  done
  restore
  echo "<== $passes passed, $fails failed of $N runs: [$dir] $command"
  ((fails == 0)) || failed=1
  ((failed == 0)) || [[ -n $KEEP ]] || break
done
if ((failed)); then
  echo "repeat.sh: FAIL: a run failed; the test is flaky or broken" >&2
  exit 1
fi
echo "repeat.sh: all $N runs of every selection passed"
