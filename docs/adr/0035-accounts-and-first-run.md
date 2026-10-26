# ADR-0035 — Accounts: a logged setup token, a database-enforced audit trail, viewers and delayed deletion

* **Status**: Accepted — 2026-10-16. The owner confirmed the fixed seven-day deletion delay and viewer as a role, and
  deferred the in-memory setup token and audit events that name personal fields without copying them
  (photolib-design#322).
* **Requirements**: R-SEC-1, R-SEC-2, OPS-01, OPS-22, OPS-27, PRIV-32. **Design**: 06 §10,
  04 §3 and §10, 18 §17.

## Context

A new server must not ship a default password, and must not hand the administrator role to whoever reaches it first
(Immich's first sign-up becomes the administrator). Every account change must leave an audit event (design 04 §10:
append-only and hash-chained), including changes that later code or an operator in psql make. Sessions arrive with
M2-02 and the central authorization policy with M2-03, so M2-01 cannot sign anybody in yet.

## Decision

* **First run.** An API process that starts on a database without any administrator makes a 256-bit random setup
  token, keeps it in memory and logs it once at WARN in the `setup_token` field. `SetupService.CreateFirstAdmin`
  compares it in constant time and creates the first administrator, under the accounts lock, only while none exists;
  then it answers `setup.done`. A restart replaces the token. Each API process logs its own token, valid on that
  process.
* **Audit by the database.** A trigger on `users` appends an event in the same transaction for every insert
  (`user.create`), update (`user.update`) and delete (`user.purge`), whoever makes it. photolibd names the acting user
  in the transaction setting `photolib.actor`; a change made around photolibd has no actor, and the first
  administrator is their own. The details list the changed fields and the new values of role, status, quota, locale
  and purge date; handle, display name and email are named, never copied, so the append-only chain keeps no personal
  data of a purged account. `audit_append` chains each event to the previous one with
  `audit_hash` (SHA-256 over the previous hash and the event's fields), holding a table lock until commit so the chain
  stays linear; other events (logins, grants) append through the same function.
* **Roles** are `admin`, `user` and `viewer` (OPS-27: browses what is shared with them, never uploads; the policy of
  M2-03 enforces it). **Statuses** are `active`, `disabled`, `invited` and `deleted`.
* **Delayed deletion** (OPS-22). `DeleteUser` sets `deleted` and `purge_at` seven days later; setting another status
  before then restores the account. A database check ties `purge_at` to `deleted`.
* **The last active administrator stays.** Under the same advisory lock, no change may demote, disable or delete it.
* **Until sessions exist**, the `Sessions` port of the API signs nobody in, so `UserService` answers
  `unauthenticated`; M2-02 replaces it.

## Consequences

* No code path, present or future, can change an account without an audit event; psql changes are visible too.
* The setup token sits in the log until it is used; it is useless once an administrator exists.
* With several API processes behind a load balancer, the setup call must reach the process whose token it carries;
  setting up with one API process avoids that.
* The purge of deleted accounts and their files needs the job queue (M0-17) and storage cleanup; until then a
  deleted account stays deleted.
* Clients show the honest notice of PRIV-32 when they sign in to a server with other accounts (M2-02's sign-in UI).

## Options considered

* **Default credentials, or the first visitor becomes administrator**: rejected by R-SEC-1.
* **The token's hash in the database, valid on every API process**: survives restarts and load balancers, but keeps
  an old token valid after a restart. The in-memory token is the smaller change.
* **Audit calls in the Rust code that changes accounts**: misses changes by future code paths and by operators.
* **Viewer as a quota of zero** (Immich's workaround): says nothing about uploads to shared albums or about the UI.
* **A configurable deletion delay**: seven days is Immich's default; a setting can follow if owners ask for it.
