#!/usr/bin/env bash
# The administrator guides (M2-34): the runbooks of design 15 §12, object storage (ADR-0022), the admin-succession kit
# with two administrators, and no guide naming a photolibd command or a store setting that does not exist.
# shellcheck disable=SC2016 # patterns and samples hold literal backticks
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

RUNBOOKS=docs/admin/runbooks.md
for runbook in 'Upgrade' 'A failed upgrade' 'Restore a database dump' 'Recover from storage' 'Move the data directory' \
  'Change the storage backend' 'Re-run thumbnails and ML' 'Rotate server secrets' 'A user lost their recovery kit' \
  'The disk is full' 'Replace a failed node'; do
  assert_matches "$RUNBOOKS" "^## $runbook\$" "has the runbook \"$runbook\""
done
assert_prose "$RUNBOOKS" 'impossible' "says that nobody can open a private library without its keys"

STORAGE=docs/admin/storage.md
assert_patterns assert_matches "$STORAGE" \
  '^## Placement$' "says what placement puts on a bucket" \
  '^## Costs$' "says what a bucket costs" \
  '^## A bucket is not a backup$' "says why a bucket is not a backup" \
  '^## What the provider can read$' "says what a provider can read" \
  '^ +endpoint: http://[^ ]+:3900( |$)' "configures Garage" \
  '^ +endpoint: https://[^ ]+\.r2\.cloudflarestorage\.com( |$)' "configures Cloudflare R2" \
  '^ +endpoint: https://s3\.[^ ]+\.backblazeb2\.com( |$)' "configures Backblaze B2" \
  '^ +endpoint: https://s3\.[^ ]+\.amazonaws\.com( |$)' "configures AWS S3"
CONFIG=server/crates/photolib-server/src/config.rs
fields() { sed -n "/^pub struct $1 {/,/^}/s/^    pub \([a-z_]*\):.*/\1/p" "$CONFIG"; }
# Keys of the guide's YAML: two levels below `stores:` a store's, one below `placement:` placement's.
keys() {
  awk -v block="$1" -v pad="$(printf '%*s' "$2" '')" '/^```yaml/ {y = 1; next} /^```/ {y = 0; next} !y {next}
    /^[a-z_]+:/ {s = ($0 ~ "^" block ":"); next}
    s && $0 ~ "^" pad "[a-z_]+:" {sub(/^ +/, ""); sub(/:.*/, ""); print}' "$STORAGE" | sort -u
}
for check in 'stores 4 Store' 'placement 2 Placement'; do
  read -r block depth struct <<<"$check"
  used=$(keys "$block" "$depth")
  [[ -n $used ]] || fail "$STORAGE: no YAML example sets $block"
  unknown=$(comm -23 <(echo "$used") <(fields "$struct" | sort))
  [[ -z $unknown ]] && ok "$STORAGE: every key of $block is a field of $struct" ||
    fail "$STORAGE: $block keys photolibd refuses: ${unknown//$'\n'/ }"
done

BACKUPS=docs/admin/backups.md
assert_matches "$BACKUPS" '^## The admin-succession kit$' "documents the admin-succession kit"
KIT=$(awk '/^## / {s = ($0 == "## The admin-succession kit")} s' "$BACKUPS" | tr '\n' ' ')
kit_has() { grep -Eqi -- "$1" <<<"$KIT" && ok "$BACKUPS: the kit $2" || fail "$BACKUPS: the kit $2 (not /$1/)"; }
kit_has 'second administrator' "names a second administrator"
kit_has 'sealed secrets.*keys/opaque\.key' "holds the sealed OPAQUE key"
kit_has 'sealed secrets.*`\.env`' "holds the sealed settings and passwords"
kit_has 'where the backups are' "says where the backups are"
kit_has 'recovery runbook[^.]*\(runbooks\.md#replace-a-failed-node\)' "carries the recovery runbook"
assert_patterns assert_prose "$BACKUPS" \
  'Backing up the originals.*restic.*backup data --exclude data/tmp' "gives a recipe for the data directory" \
  'rclone copy --metadata' "gives a recipe for the originals on a bucket"
for page in docs/admin/install.md docs/admin/users.md; do
  assert_prose "$page" 'second (person|administrator)[^.]*administrator' "onboarding recommends two administrators"
done
assert_prose docs/admin/upgrades.md 'PHOTOLIB_VERSION=beta' "upgrades say how to follow the release candidates"
assert_prose docs/dev/releasing.md 'two people who did not write them' "a release has the guides validated"
for page in storage runbooks; do
  assert_matches docs/admin/README.md "\]\($page\.md\)" "the administrator guide links $page.md"
done

# Every `photolibd <command> [<subcommand>]` the guides show in code is one of main.rs's subcommands.
MAIN=server/crates/photolib-server/src/main.rs
variants() {
  sed -n "/^enum $1 {/,/^}/s/^    \([A-Z][A-Za-z]*\).*/\1/p" "$MAIN" | sed -E 's/([a-z])([A-Z])/\1-\2/g; s/.*/\L&/'
}
COMMANDS=$(variants Command)
[[ $COMMANDS == *recover* && $(variants Doctor) == schema ]] || fail "cannot read photolibd's subcommands from $MAIN"
unknown_commands() {
  # Code blocks without their comments, and code spans.
  awk '/^```/ {c = !c; next} c {sub(/(^| )#.*/, ""); print; next}
    {while (match($0, /`[^`]*`/)) {print substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH)}}' "$@" |
    grep -oE 'photolibd( --config [^ `]+)? [a-z][a-z-]*( [a-z][a-z-]*)?' | sort -u |
    while read -r -a words; do
      [[ ${words[1]} == --config ]] && words=("${words[@]:0:1}" "${words[@]:3}")
      local command=${words[1]} sub=${words[2]:-}
      if ! grep -qx "$command" <<<"$COMMANDS"; then echo "${words[*]}"; continue; fi
      local enum=${command^}
      if [[ -n $sub ]] && grep -q "^enum $enum {" "$MAIN" && ! grep -qx "$sub" <<<"$(variants "$enum")"; then
        echo "${words[*]}"
      fi
    done
}
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
printf '%s\n' '# Sample' '' 'Run `photolibd rotate-keys`, then `photolibd doctor schema`.' '' '```sh' \
  'photolibd --config photolib.yaml doctor storage' 'docker compose run --rm photolibd recover --from-storage local' \
  'rclone copy old: new:    # while photolibd runs' \
  '```' 'photolibd starts in prose.' >"$SANDBOX/sample.md"
caught=$(unknown_commands "$SANDBOX/sample.md" | tr '\n' ',')
[[ $caught == 'photolibd doctor storage,photolibd rotate-keys,' ]] && ok "the command check flags unknown commands" ||
  fail "the command check flagged '$caught' in its sample"
unknown=$(unknown_commands docs/admin/*.md)
[[ -z $unknown ]] && ok "every photolibd command in docs/admin exists" ||
  fail "docs/admin names photolibd commands that do not exist: ${unknown//$'\n'/; }"

finish
