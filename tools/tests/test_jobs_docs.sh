#!/usr/bin/env bash
# The job system (ADR-0034, M0-17) as the owner answered it (photolib-design#320): cron in UTC confirmed, the
# reconciler's re-arming and the device placement of private libraries deferred, so all three stand.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0034-job-queue.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed UTC [^*]*deferred [^*]*photolib-design#320' \
  "is Accepted, recording the owner's answers (#320)"
assert_patterns assert_prose "$ADR" \
  'Cron\*\* schedules are five fields in UTC' "cron schedules run in UTC" \
  'A finished job with the key \(done, dead or cancelled\) is queued again' "the reconciler re-arms finished jobs" \
  'Private libraries get `device` jobs' "private libraries' derivatives go to the device"
assert_matches docs/adr/README.md '\(0034-job-queue\.md\) \| [^|]* \| Accepted \(owner confirmed UTC, deferred the rest' \
  "the index lists ADR-0034 as Accepted"
assert_matches docs/admin/configuration.md 'Scheduled jobs use UTC' "administrators are told schedules use UTC"

finish
