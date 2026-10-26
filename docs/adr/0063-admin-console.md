# ADR-0063 — Admin console: one admin service, pauses that end by themselves, the doctor inside the server

* **Status**: Accepted — 2026-10-17. The owner answered M2-32's provisional choices in
  photolib-design#376
  and corrected the last: a
  job class stays a job type and `backup`, `purge` and `scrub` the maintenance a key cannot pause; an administrator's
  key does what its scopes allow (M2-06); the policy defaults stand but the disk floor, now the smaller of 5 % and
  20 GB; `/diagnostics` keeps `metrics.token`. The owner added that a maintenance pause lasts at most 7 days with a
  banner, and answered
  how (photolib-design#699, 2026-10-23): up to 7 days in one request, 24 hours for any other type, with no clamp to
  a week after a pause began; the floor's 20 GB stays a setting.
* **Requirements**: NFR-OBS-1. **Design**: 15 §10, [ADR-0022](0022-object-store-backends.md),
  [ADR-0034](0034-job-queue.md), [ADR-0038](0038-authorization-policy.md).

## Context

M2-32 asks for every admin operation in the app, targeted reprocessing that touches only its scope, job-type pauses
that resume by themselves (60 minutes by default, 24 hours at most) and cannot stop maintenance from an API key, and a
`photolibd doctor` whose output goes into a diagnostics bundle. The design leaves open what a "job class" is, what
counts as maintenance, where instance settings live, how the CLI sees proxy headers that only the server sees, and what
an API key ([ADR-0055](0055-scoped-api-keys.md)) may do there.

## Decision

* **One `AdminService`** next to `UserService`: status (usage per account and file role, libraries, backups, open jobs,
  pauses), stores, jobs (list, retry, cancel, pause, resume), reprocessing, the audit log, the log tail, settings and
  the doctor. Its procedures need the new `Action::ManageServer`; each change commits with its audit event.
* **A job class is a job type.** A pause is a row of `job_pauses` (type, `until`); workers lease no job of a paused
  type before `until`, so a pause ends without any job or timer; pausing a paused type again sets its end anew.
  `backup`, `storage-purge` and `scrub` are maintenance: an administrator's pause of one lasts up to 7 days in one
  request, any other type's up to 24 hours, and the console shows a banner for every pause while it is active.
* **An administrator's API key does what its scopes allow.** `manage_server` runs the server and `manage_users`
  manages accounts ([ADR-0055](0055-scoped-api-keys.md)); a key never pauses maintenance or manages keys, which need
  the administrator's session. The key columns of both authz matrices pin it.
* **Reprocessing** queues a `metadata`, `renditions` or `faces` job per asset of the scope, keyed `<type>:<asset>` and
  re-armed like the reconciler's. A folder is a prefix of the original's key, subfolders included; private libraries
  are skipped, since their devices process them.
* **Instance settings** are one database row with checks: second factor required, face recognition for new accounts
  (off: design 09 makes faces opt-in), trash retention (60 days, domain model §4) and the disk floor: uploads pause
  below the smaller of 5 % and 20 GB free on any filesystem they fill, `work_dir`, `data_dir` when the library's store
  is the local one, and `database.data_dir` when set (`503`, `disk.low`; clients try again). Both are settings,
  `min_free_disk_percent` and `min_free_disk_gb` (GB of 10^9 bytes); external libraries are never written and object
  stores are not checked.
* **The doctor runs in the server.** It answers `/diagnostics` beside `/metrics`, for the bearer of `metrics.token`
  (ADR-0046), and `GetDiagnostics`, so it sees how the API's last request arrived (proxy headers) and the log tail.
  `photolibd doctor` prints the running server's report and checks on its own when none answers. The bundle holds
  versions, the configuration's differences from the defaults with secrets as `[redacted]`, the checks and the last
  1,000 log lines.
* **The app's console** is a page behind the signed-in administrator's connection; until sign-in exists (M2-02) it
  stays hidden.

## Consequences

* ✅ No pause outlives its end: a crash or restart changes nothing, and the dashboard shows exactly what workers obey.
* ✅ A key leaked to an integration cannot stop backups or scrubs.
* ⚠️ The proxy check knows only the last API request; a process that served none says so.
* ⚠️ The handlers of `metadata`, `renditions` and `faces` arrive with ingest (M2-08), renditions (M2-09) and faces
  (M5); until then reprocessing only queues. Scans (M2-27), sessions (M2-02), backups now and restores (M2-31) and
  scrub egress (M2-33) join the console with their items.

## Options considered

* Pausing a worker class (`cpu`, `io`, …): too coarse to pause thumbnails but not imports, and classes do not tell
  maintenance apart.
* A scheduler that resumes pauses: one more moving part that a crash could leave paused.
* Settings in the YAML file: the console could not change them without editing files.
* A doctor only in the CLI: it cannot see requests or the log; one only in the server: no answer when it is down.
* A floor of 5 % free alone (the provisional choice): it keeps 50 GB idle on a 1 TB disk.
* A maintenance pause held to a week after it began, each request at most 24 hours (the provisional reading):
  the owner asked for a week in one request instead.
* An administrator's key limited to `manage_server` (the provisional choice before M2-06 gave keys their scopes).
