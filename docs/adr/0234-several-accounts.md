# ADR-0234 — Several accounts: a replica each, the list in the store's `server` object, switching without reopening

* **Status**: **Proposed** — owner to confirm. M2-38 had to choose where the list of accounts lives, which replica an
  account gets, what a switch keeps open and what removing an account does to its replica. Becomes
  *Accepted — YYYY-MM-DD* when the owner decides.
* **Requirements**: R-MODE-2. **Design**: 05 §7, 10 §2,
  [ADR-0120](0120-client-sync-engine.md), [ADR-0125](0125-sign-in-from-the-app.md),
  [ADR-0209](0209-server-session-in-the-store.md).

## Context

ADR-0125 kept one server and its session in one entry, now the store's class B object `server` (ADR-0209), and the
replica synced with that server alone. Design 10 §2 asks for one replica per account, the device's own adopted by the
first account to connect, and an `accounts.db` for the list and per-account settings. M2-38 asks that switching
between two accounts on two servers take under a second and never mix data between replicas; the merged timeline
stays in M11-06.

## Decision

* **The list stays in the `server` object** (ADR-0209): every server with its session and the name of its replica, and
  the one in use. A build before this one reads its single server as the one account. The list is a
  few secrets; `accounts.db` waits for the per-account settings it would hold (storage policies, M3-21).
* **One replica per account** in the vault: the first account to connect adopts the device's (`replica`, docs/05 §7),
  every other gets `replica-<16 hex digits>`, never reused. Each has its own data isolate, cursors and device index
  (folders, MediaStore, PhotoKit).
* **A switch is a state change**: the account in use changes at once and the store follows. Its replica opens if
  this process has not opened it yet and then stays open, so switching back costs a query. Every tab's page is built
  anew for the account, pages a tab pushed close, and the device index of the new replica is brought up to date.
  What a view keeps across restarts (ADR-0208: scroll, selection, viewer, search) is kept per account (`keptKey`).
* **The app syncs the replica of the account in use** with that account's server: once the accounts are read, at
  each sign-in and at each switch. A sync still running for another account ends in that account's data isolate.
* **What a session brings lands on its own account**: a revocation answered after a switch ends the session it was
  made with, and a sign-in that ends after a switch signs in the account it started on. Each account's session is
  renewed at start (ADR-0052), and a password setup token is kept per account.
* **Removing an account** signs it out and drops it; when its replica was the device's, what its server synced there
  is forgotten as after a restore (ADR-0120: synced rows and cursors dropped, backed-up items re-verified with the next
  server), in its data isolate after any sync of it still running, so the device alone, or the next account to adopt
  it, shows none of it.
* **Where to switch**: a menu in the app bar while there are several accounts, and Settings, which lists each server
  and opens its page on it.

## Consequences

* Switching took 20 to 130 ms on the gate machine, to a replica not yet open and back to one open, each the fastest of
  three rounds (`app/test/core/account_replicas_test.dart`).
* The replica of a removed account other than the device's stays on disk, unused, until a follow-up deletes it.
* The same folders, or MediaStore, are indexed once per account that uses them; settings stay the device's.
* Browsers have no data worker to sync in yet (ADR-0120): there a switch changes the session and the replica only.

## Options considered

* **`accounts.db` now**: an encrypted database for a list of secrets the store already seals as one object.
* **One replica with a server column**: a migration of every synced table and query, and each account's rows one
  missing `WHERE` away from another's.
* **Closing the replica switched away from**: every switch back would start a data isolate, or a browser's worker.
* **Opening every account's replica at start**: every account's indexing and metadata extraction at once.
* **Deleting a removed account's replica now**: needs a data isolate stopped per database natively and a database
  deleted per name in browsers; left to a follow-up.
