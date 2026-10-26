#!/usr/bin/env bash
# Migration rules CI enforces (M0-15): tools/migrations.sh runs squawk and keeps released migrations immutable,
# numbered in order and, on release branches, identical to main's.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

# The git commands below must never run outside a sandbox.
SANDBOX=$(mktemp -d) || { echo "FAIL: cannot create a temporary directory" >&2; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT
GIT=(git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c init.defaultBranch=main)
DIR=server/migrations
# CI sets these for every step; each case below sets what it needs.
unset GITHUB_BASE_REF GITHUB_REF_NAME

# A squawk on PATH that logs its arguments and fails when $SQUAWK_FAILS is set; tools/squawk.sh prefers it.
mkdir "$SANDBOX/bin"
printf '#!/bin/bash\necho "squawk $*" >>"$SQUAWK_LOG"\n[[ -z ${SQUAWK_FAILS:-} ]] || { echo squawk-finding; exit 1; }\n' \
  >"$SANDBOX/bin/squawk"
chmod +x "$SANDBOX/bin/squawk"
export SQUAWK_LOG=$SANDBOX/squawk.log

git_in_repo() { "${GIT[@]}" -C "$REPO" "$@"; }

# new_repo <name> <migration...>: a repository whose main (and origin/dev) holds these migrations
new_repo() {
  REPO=$SANDBOX/$1
  shift
  mkdir -p "$REPO/$DIR"
  git_in_repo init --quiet
  : >"$REPO/$DIR/.squawk.toml"
  local file
  for file in "$@"; do echo "CREATE TABLE t${file:0:4} (x int);" >"$REPO/$DIR/$file"; done
  git_in_repo add -A
  git_in_repo commit --quiet -m "feat(db): migrations"
  git_in_repo update-ref refs/remotes/origin/dev HEAD
}

# run_check [args...]: tools/migrations.sh in $REPO; output in $OUT, exit status in $STATUS
run_check() {
  OUT=$(cd "$REPO" && PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/tools/migrations.sh" "$@" 2>&1)
  STATUS=$?
}

# expect pass <description> | expect fail <description> <pattern the output must match>
expect() {
  local want=$1 description=$2 pattern=${3:-}
  run_check "${ARGS[@]}"
  if [[ $want == pass && $STATUS -eq 0 ]]; then ok "$description"
  elif [[ $want == fail && $STATUS -ne 0 && $OUT =~ $pattern ]]; then ok "$description"
  else fail "$description (exit $STATUS): $OUT"; fi
}
ARGS=()

new_repo unchanged 0001_a.sql 0002_b.sql
: >"$SQUAWK_LOG"
expect pass "unchanged released migrations pass"
[[ $(cat "$SQUAWK_LOG") == "squawk --config $DIR/.squawk.toml $DIR/0001_a.sql $DIR/0002_b.sql" ]] &&
  ok "squawk lints every migration with the configuration next to them" || fail "squawk was run as: $(cat "$SQUAWK_LOG")"
SQUAWK_FAILS=1 expect fail "a squawk finding fails the check" "squawk-finding"

new_repo edited 0001_a.sql 0002_b.sql
echo "-- a comment changes the checksum too" >>"$REPO/$DIR/0001_a.sql"
expect fail "editing a released migration fails" "0001_a.sql.*released.*edited"

new_repo removed 0001_a.sql 0002_b.sql
git_in_repo mv "$DIR/0002_b.sql" "$DIR/0002_renamed.sql"
expect fail "renaming or deleting a released migration fails" "0002_b.sql.*released"

new_repo added 0001_a.sql 0002_b.sql
echo "CREATE TABLE c (x int);" >"$REPO/$DIR/0003_c.sql"
expect pass "a new migration numbered above the newest released one passes"

new_repo below 0001_a.sql 0003_c.sql
echo "CREATE TABLE b (x int);" >"$REPO/$DIR/0002_b.sql"
expect fail "a new migration numbered below the newest released one fails" "0002_b.sql.*newest released.*0003"
new_repo same 0001_a.sql 0002_b.sql
echo "CREATE TABLE b2 (x int);" >"$REPO/$DIR/0002_mine.sql"
expect fail "a new migration that reuses a released number fails" "0002_mine.sql"

new_repo badname 0001_a.sql
echo "CREATE TABLE z (x int);" >"$REPO/$DIR/2_z.sql"
expect fail "a migration named other than NNNN_description.sql fails" "2_z.sql.*NNNN_description.sql"

new_repo renumber 0001_a.sql 0002_b.sql
echo "CREATE TABLE m (x int);" >"$REPO/$DIR/0002_mine.sql"
echo "CREATE TABLE n (x int);" >"$REPO/$DIR/0003_next.sql"
ARGS=(--renumber)
expect pass "--renumber moves new migrations above the newest released one"
[[ -f $REPO/$DIR/0003_mine.sql && -f $REPO/$DIR/0004_next.sql && ! -e $REPO/$DIR/0002_mine.sql ]] &&
  ok "--renumber keeps the order of the new migrations" || fail "after --renumber: $(ls "$REPO/$DIR")"
ARGS=()
expect pass "renumbered migrations pass the check"

new_repo release 0001_a.sql 0002_b.sql
git_in_repo checkout --quiet -b release/1.0
git_in_repo reset --quiet --hard HEAD
git_in_repo rm --quiet "$DIR/0002_b.sql"
git_in_repo commit --quiet -m "chore: cut"
expect pass "a release branch may carry a subset of main's migrations"
echo "CREATE TABLE hotfix (x int);" >"$REPO/$DIR/0002_hotfix.sql"
expect fail "a release branch may not carry a migration that main lacks" "0002_hotfix.sql.*identical to main"
rm "$REPO/$DIR/0002_hotfix.sql"
git_in_repo checkout --quiet main
GITHUB_BASE_REF=release/1.0 expect pass "the target branch of a pull request decides the rules"
echo "CREATE TABLE x (x int);" >"$REPO/$DIR/0003_x.sql"
GITHUB_BASE_REF=release/1.0 expect fail "a pull request into a release branch may not add a migration main lacks" \
  "0003_x.sql.*identical to main"

# --- upgrade fixtures (fixtures/<migration>.sql and .resolved) are released with their migration
new_repo fixtures 0001_a.sql 0002_b.sql
mkdir "$REPO/$DIR/fixtures"
for file in 0001_a.sql 0001_a.resolved 0002_b.sql; do echo "-- $file" >"$REPO/$DIR/fixtures/$file"; done
git_in_repo add -A && git_in_repo commit --quiet -m "test(db): fixtures" && git_in_repo update-ref refs/remotes/origin/dev HEAD
echo "-- edited" >>"$REPO/$DIR/fixtures/0001_a.resolved"
expect fail "editing a released fixture fails" "fixtures/0001_a.resolved.*released fixture.*edited"
git_in_repo checkout --quiet -- "$DIR"
rm "$REPO/$DIR/fixtures/0002_b.sql"
expect fail "deleting a released fixture fails" "fixtures/0002_b.sql.*released fixture"
git_in_repo checkout --quiet -- "$DIR"
echo "CREATE TABLE m (x int);" >"$REPO/$DIR/0002_mine.sql"
for ext in sql resolved; do echo "-- mine" >"$REPO/$DIR/fixtures/0002_mine.$ext"; done
ARGS=(--renumber)
expect pass "--renumber renumbers a new migration's fixtures with it"
[[ -f $REPO/$DIR/fixtures/0003_mine.sql && -f $REPO/$DIR/fixtures/0003_mine.resolved &&
  ! -e $REPO/$DIR/fixtures/0002_mine.sql && -f $REPO/$DIR/fixtures/0002_b.sql ]] &&
  ok "--renumber leaves released fixtures alone" || fail "after --renumber: $(ls "$REPO/$DIR/fixtures")"
ARGS=()

new_repo no-baseline 0001_a.sql
git_in_repo update-ref -d refs/remotes/origin/dev
expect fail "the check fails loudly without origin/dev" "origin/dev"

# --- the real squawk with the real configuration rejects unsafe changes to existing tables
lint_rejects() {
  local sql=$1 rule=$2 file=$SANDBOX/lint.sql output
  printf '%s\n' "$sql" >"$file"
  output=$(bash tools/squawk.sh --config $DIR/.squawk.toml "$file" 2>&1)
  if [[ $? -ne 0 && $output == *"$rule"* ]]; then ok "squawk rejects: $sql"; else fail "squawk did not reject ($rule): $sql: $output"; fi
}
lint_rejects "ALTER TABLE users ADD COLUMN x int NOT NULL;" adding-required-field
lint_rejects "ALTER TABLE users DROP COLUMN email;" ban-drop-column
lint_rejects "ALTER TABLE users RENAME COLUMN email TO mail;" renaming-column
lint_rejects "CREATE INDEX users_locale ON users (locale);" require-concurrent-index-creation

# --- ADR-0028 as the owner confirmed it (photolib-design#299)
ADR=docs/adr/0028-postgresql-migrations.md
assert_prose $ADR '\* \*\*Status\*\*: Accepted — 2026-10-15\. The owner confirmed [^*]*photolib-design#299' \
  "is Accepted, recording the owner's confirmation (#299)"
assert_patterns assert_prose $ADR \
  'Released means merged to `main`' "released means merged to main" \
  'photolibd restore <dump>.*CLI command, not an HTTP endpoint' "the way back is a CLI command" \
  'newest 3 are kept \(`database\.keep_dumps`\)' "three pre-upgrade dumps are kept" \
  '`cargo test` needs the PostgreSQL 16\+ programs and fails without them' "database tests fail without PostgreSQL"
assert_matches docs/adr/README.md '\(0028-postgresql-migrations\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0028 as Accepted"
if grep -Eqi 'not yet confirmed|owner to confirm' docs/admin/upgrades.md docs/dev/migrations.md; then
  fail "the upgrade or migration docs still call ADR-0028 unconfirmed"
else ok "the upgrade and migration docs treat ADR-0028 as decided"; fi

finish
