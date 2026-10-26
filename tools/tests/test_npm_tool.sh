#!/usr/bin/env bash
# tools/npm_tool.sh installs a pinned npm release once into a cache keyed by its version. Two gates on a cold cache
# install at once: neither may delete or write into the other's install, half-done or running. npm is a stub here.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool node
sandbox_tools bash env mkdir rm mktemp id sleep cat chmod touch ln node

SANDBOX=$(mktemp -d)
SANDBOXES+=("$SANDBOX")
CACHE=$SANDBOX/cache INSTALL=$SANDBOX/cache/faketool-1.2.3
mkdir "$SANDBOX/bin"
# An npm that marks its prefix as its own, waits for go, then checks that the mark is still there before writing the
# tool: a gate that deleted the prefix meanwhile is caught.
cat >"$SANDBOX/bin/npm" <<EOF
#!/bin/bash
while [[ \$1 != --prefix ]]; do shift; done
prefix=\$2
mkdir -p "\$prefix/node_modules/.bin" && touch "\$prefix/mine.\$\$" "$SANDBOX/installing.\$\$"
until [[ -e $SANDBOX/go ]]; do sleep 0.05; done
[[ -e \$prefix/mine.\$\$ ]] || { echo "an install was deleted under npm \$\$" >>"$SANDBOX/deleted"; exit 1; }
printf '#!/bin/bash\necho "faketool \${FAKE_VERSION:-1.2.3} \$*"\n' >"\$prefix/node_modules/.bin/faketool"
chmod +x "\$prefix/node_modules/.bin/faketool"
EOF
chmod +x "$SANDBOX/bin/npm"

gate() { # gate <name>: npm_tool.sh as one gate runs it, its output and status in $SANDBOX/<name>.*
  PATH=$SANDBOX/bin:$BASE_BIN PHOTOLIB_TOOLS_CACHE=$CACHE bash "$REPO_ROOT/tools/npm_tool.sh" faketool \
    @example/faketool@1.2.3 lint >"$SANDBOX/$1.out" 2>&1
  echo $? >"$SANDBOX/$1.status"
}
installing() { local marks=("$SANDBOX"/installing.*); [[ -e ${marks[0]} ]] && echo ${#marks[@]} || echo 0; }

gate first &
until (($(installing) == 1)); do sleep 0.05; done
gate second &
until (($(installing) == 2)) || [[ -e $SANDBOX/second.status ]]; do sleep 0.05; done
touch "$SANDBOX/go"
wait
for name in first second; do
  [[ $(cat "$SANDBOX/$name.status") == 0 && $(cat "$SANDBOX/$name.out") == "faketool 1.2.3 lint" ]] &&
    ok "the $name gate on a cold cache runs the tool" ||
    fail "the $name gate: exit $(cat "$SANDBOX/$name.status"): $(cat "$SANDBOX/$name.out")"
done
[[ ! -e $SANDBOX/deleted ]] && ok "neither deleted the other's install" || fail "$(cat "$SANDBOX/deleted")"
[[ $("$INSTALL/node_modules/.bin/faketool" x) == "faketool 1.2.3 x" ]] && ok "the install is in place, whole" ||
  fail "no working install at $INSTALL"

# A cached install that does not start is replaced, and nothing is left beside the new one.
rm -rf "$CACHE" "$SANDBOX"/installing.*
mkdir -p "$INSTALL/node_modules/.bin"
printf '#!/bin/bash\nexit 1\n' >"$INSTALL/node_modules/.bin/faketool"
chmod +x "$INSTALL/node_modules/.bin/faketool"
gate broken
[[ $(cat "$SANDBOX/broken.status") == 0 && $(cat "$SANDBOX/broken.out") == "faketool 1.2.3 lint" ]] &&
  ok "an install that does not start is installed again" || fail "broken install: $(cat "$SANDBOX/broken.out")"
shopt -s nullglob dotglob
left=("$CACHE"/*)
[[ ${#left[@]} == 2 ]] && ok "the cache holds the install and the link to it, nothing else" ||
  fail "left in the cache: ${left[*]}"

# A cached install that starts but reports another version (a stub a test once left in the shared cache) is replaced.
rm -rf "$CACHE"
mkdir -p "$CACHE/stub/node_modules/.bin"
printf '#!/bin/bash\necho "faketool 1.2.34 $*"\n' >"$CACHE/stub/node_modules/.bin/faketool"
chmod +x "$CACHE/stub/node_modules/.bin/faketool"
ln -s stub "$INSTALL"
gate stub
[[ $(cat "$SANDBOX/stub.status") == 0 && $(cat "$SANDBOX/stub.out") == "faketool 1.2.3 lint" ]] &&
  ok "a cached install of another version is installed again" || fail "another version: $(cat "$SANDBOX/stub.out")"

# An install of another version is never published: three of them fail the gate.
rm -rf "$CACHE"
FAKE_VERSION=1.2.4 gate wrong
[[ $(cat "$SANDBOX/wrong.status") != 0 && $(cat "$SANDBOX/wrong.out") == "3 installs of faketool"* && ! -e $INSTALL ]] &&
  ok "installs of another version fail the gate and are not kept" || fail "another version installed: $(cat "$SANDBOX/wrong.out")"

finish
