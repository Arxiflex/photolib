#!/usr/bin/env bash
# Integrity scrubbing and the backup watchdog (ADR-0234, M2-33) as the owner kept them (photolib-design#604):
# Prometheus alerts until M3-11, silence as no ReportBackup for backup_silent_hours, the pace and silence in the
# console, the re-hash budget per store in the YAML.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0234-integrity-scrubbing-and-backup-watchdog.md
SERVER=server/crates/photolib-server/src
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-21 \(roadmap M2-33\)\. The owner kept [^*]*photolib-design#604' \
  "is Accepted, recording the owner's answer (#604)" \
  'Not backed up\* badge of ADR-0200 and the server.s silence derive from the same data .ReportBackup. reports' \
  "notes for M2-18 and M2-24 that the badge and the silence share ReportBackup's data"
assert_matches docs/adr/README.md \
  '\(0234-integrity-scrubbing-and-backup-watchdog\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-21\)' \
  "the index lists ADR-0234 as Accepted"
# 1. Prometheus alerts are the notification until M3-11.
for alert in PhotolibIntegrityFindings PhotolibDeviceBackupSilent; do
  assert_matches deploy/observability/alerts.yml "^ *- alert: $alert\$" "alerts with $alert"
done
# 2. Devices report their pending count; silent is no report for backup_silent_hours.
assert_prose proto/photolib/api/v1/auth.proto 'message ReportBackupRequest \{[^}]* int64 pending_count = 1;' \
  "ReportBackup carries the pending count"
assert_prose "$SERVER/rpc/admin.rs" 'b\.reported_at < now\(\) - make_interval\(hours => i\.backup_silent_hours\)' \
  "silent is no report for backup_silent_hours"
# 3. The pace and the silence are console policies, the re-hash budget a store's YAML.
assert_prose server/migrations/0021_scrub.sql \
  'ADD COLUMN scrub_days integer NOT NULL DEFAULT 90 [^;]*ADD COLUMN backup_silent_hours integer NOT NULL DEFAULT 48' \
  "scrub_days (90) and backup_silent_hours (48) are instance settings"
assert_prose app/lib/features/admin/admin_page.dart '\.\.scrubDays = [^;]*\.\.backupSilentHours = ' \
  "the console sets both"
assert_prose "$SERVER/config.rs" \
  'pub secret_access_key: Secret<String>, [^}]* pub rehash_gib_per_month: Option<u32>, \}' \
  "the re-hash budget is a store's field in the YAML"

finish
