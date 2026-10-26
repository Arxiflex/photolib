#!/usr/bin/env bash
# photolibd takes every PHOTOLIB_ variable as a setting and refuses an unknown one, but for those other programs read
# (NOT_SETTINGS in its config.rs): every PHOTOLIB_ name the repository uses must be one or the other, or exporting it
# stops photolibd and fails its config tests.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

CONFIG=server/crates/photolib-server/src/config.rs
settings=$(sed -n '/^pub struct Config {/,/^}/s/^    pub \([a-z_]*\):.*/\1/p' "$CONFIG")
ignored=$(sed -n '/^const NOT_SETTINGS/,/;$/p' "$CONFIG" | sed 's/.*= "//; s/[\\";]//g' | tr -s ' ' '\n' | grep .)
[[ $settings == *data_dir* && $ignored == *tools_cache* ]] || fail "cannot read the settings and NOT_SETTINGS of $CONFIG"
both=$(comm -12 <(sort <<<"$settings") <(sort <<<"$ignored"))
[[ -z $both ]] && ok "photolibd ignores no variable of a setting" || fail "settings in NOT_SETTINGS: $both"
known=$settings$'\n'$ignored
# config.rs itself names unknown variables on purpose.
unknown=$(git grep -ohE 'PHOTOLIB_[A-Z0-9_]*[A-Z0-9]' -- ":!$CONFIG" | sort -u | while read -r name; do
  key=${name#PHOTOLIB_}
  key=${key,,}
  grep -qx "${key%%__*}" <<<"$known" || echo "$name"
done)
[[ -z $unknown ]] && ok "every PHOTOLIB_ name in the repository is a photolibd setting or one it ignores" ||
  fail "neither a setting nor in NOT_SETTINGS of $CONFIG: ${unknown//$'\n'/ }"

finish
