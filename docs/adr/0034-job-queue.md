# ADR-0034 — Job queue: leases fenced in the handler's transaction, a reconciler that re-arms by key

* **Status**: Accepted — 2026-10-16. The owner confirmed UTC for cron schedules and deferred the other two choices
  of the job system (M0-17), so they stand: the reconciler re-arms finished jobs, and private libraries' derivatives
  go to the device
  (photolib-design#320).
* **Requirements**: R-REL-1, R-REL-3, R-PRIV-2. **Design**: 03 §5, ADR-0008.

## Context

ADR-0008 puts the jobs in PostgreSQL (`SKIP LOCKED` leases, retries, dead-letter, cron, placement, grants), adds a
derivatives reconciler and allows `LISTEN/NOTIFY` only as a wake-up hint. It leaves open how leases give exactly-once
side effects, what counts as an attempt, the timing, how the reconciler avoids duplicates, the cron time zone and the
payload of derivative jobs.

## Decision

* **Exactly once by fencing.** A handler's database writes go in a transaction whose last statement marks the job
  done only if this worker still holds the lease (owner and attempt) and its grant is active; otherwise it rolls back.
  Work outside the database must be idempotent. The lease (60 s) is renewed every 15 s with the progress; a renewal
  that finds the job cancelled, re-leased or its grant ended stops the handler.
* **Attempts.** Every lease is an attempt. A failure, or a lease that expired because the worker died, retries after
  10 s, doubling; the fifth attempt goes to the dead-letter queue (`dead`), from which `retry` starts over. A
  graceful shutdown requeues its leases without counting them.
* **Idle means reads only.** `NOTIFY photolib_jobs` carries the new job's id and wakes the workers, which otherwise
  poll from 1 s up to every 60 s; the scheduler ticks every minute and reconciles at start and daily. Nothing writes
  unless there is work.
* **The reconciler** wants each profile rendition (media kind, role, render spec id) and an embedding by each active
  model id per asset, finds `asset_files` (`present`, `render_spec.spec_id`) and `asset_embeddings` rows, and queues
  `render` and `embed` jobs keyed `render:<asset>:<role>:<spec>` and `embed:<asset>:<model>`, with JSON payloads, in
  batches of 1,000. A finished job with the key (done, dead or cancelled) is queued again, so one row per derivative
  remembers its history. Private libraries get `device` jobs.
* **Cron** schedules are five fields in UTC; each occurrence is keyed `cron:<name>:<time>`, and runs missed while the
  server was down run once.
* **Placement and grants.** Server workers lease only `server` jobs. A job under a grant runs only while the grant is
  active, and the tick cancels the jobs of ended grants so that the reconciler places them again.
* **Concurrency** is a worker's slots, per class in-process. Concurrent schedulers are safe without a leader: ticks
  lock with `SKIP LOCKED` and both they and the reconciler deduplicate by key.

## Consequences

* ✅ The chaos test kills and freezes worker processes without losing or duplicating a side effect; the idle test
  sees no WAL and no bytes written for ten minutes of default timing.
* ⚠️ A handler holds a connection for its whole run; long renders should compute first and write last.
* ⚠️ Finished jobs are kept: they are the reconciler's memory and the idempotency record. Pruning old ones (in
  daily batches, so idle servers stay idle) is future work.
* ⚠️ Schedules are UTC only, and several schedulers would each reconcile until the scheduler elects a leader.

## Options considered

* Completing a job in its own transaction after the handler commits: a crash between the two runs the effects twice.
* Idempotency keys unique only among active jobs: needs a new index instead of the baseline constraint and loses the
  history that re-arming keeps.
* A `derivative_status` table (design 08 §4.3) next to the jobs: the keyed jobs hold the same state for now.
* A NOTIFY per inserted row: a reconcile pass would send thousands; one hint per batch wakes the workers as well.
* An external queue (riverqueue, pgmq): another runtime or a PostgreSQL extension; still possible behind the
  `JobQueue` port.
