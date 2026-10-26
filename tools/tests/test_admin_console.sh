#!/usr/bin/env bash
# The admin console (ADR-0063, M2-32) as the owner answered it (photolib-design#376, #699); the authz matrices, the
# pause and the upload tests pin the same rules in code.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0063-admin-console.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17\. The owner answered [^*]*photolib-design#376' \
  "is Accepted, recording the owner's answers (#376)"
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted[^*]*photolib-design#699[^*]*up to 7 days in one request' \
  "records the owner's answer on the 7 days (#699)" \
  'are maintenance: an administrator.s pause of one lasts up to 7 days in one request, any other type.s up to 24 h[^*]*banner' \
  "a maintenance pause lasts up to 7 days in one request, others a day, with a banner while active" \
  '.min_free_disk_gb.[^*]*GB of 10\^9 bytes' "the 20 GB is a setting, in decimal GB (#699 kept it)" \
  'API key does what its scopes allow\.\*\*[^*]*.manage_server.[^*]*.manage_users.[^*]*never pauses maint' \
  "an administrator's key does what its scopes allow, never pausing maintenance or managing keys" \
  'uploads pause below the smaller of 5 % and 20 GB free[^*]*work_dir[^*]*data_dir[^*]*database\.data_dir' \
  "uploads pause below the smaller of 5 % and 20 GB free on each filesystem they fill" \
  'The doctor runs in the server\.\*\*[^*]*for the bearer of .metrics\.token.' \
  "/diagnostics keeps the metrics token (the owner's correction)"
assert_matches docs/adr/README.md '\(0063-admin-console\.md\) \| [^|]* \| Accepted \(owner answered[^|]*2026-10-23\) \|' \
  "the index lists ADR-0063 as Accepted"
check "ADR-0063 holds no pause to a week in a row and asks nothing more" \
  bash -c "! grep -qE 'in a row|asked to confirm|asked again|\`since\`' $ADR docs/admin/console.md"
assert_patterns assert_prose docs/admin/console.md \
  'for up to 7 days at a time' "says how long maintenance pauses last" \
  'smaller of 5 % and 20 GB' "names the free-disk floor"
assert_prose docs/admin/configuration.md 'smaller of 5 % and 20 GB' "names the free-disk floor"
assert_prose server/crates/photolib-authz/tests/matrix.rs '.root/MKAP.[^.]*never manages keys or pauses maintenance' \
  "the policy matrix has the key column"
assert_prose server/crates/photolib-server/src/rpc/authz.rs '.serverkey.[^.]*never manages keys, and never pauses' \
  "the API matrix has the key column"

finish
