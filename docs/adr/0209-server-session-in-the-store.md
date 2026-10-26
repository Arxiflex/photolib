# ADR-0209 — The server and its session are sealed in the local store

* **Status**: Accepted — 2026-10-21 (photolib-design#568). The owner kept the class B `server` object on every
  platform, with the one-time move out of the keystore
  (photolib-design#598).
* **Requirements**: R-SEC-1. **Design**: 21 §3, [ADR-0125](0125-sign-in-from-the-app.md),
  [ADR-0154](0154-desktop-open-with-packages-keyring.md).

## Context

ADR-0125 kept the server and its session as one entry of the platform keystore. On Linux without a Secret Service the
store opens under a passphrase instead (ADR-0154), but that entry still needed the Secret Service: signing in there
could not keep its session. Design 21 §3 puts refresh tokens and the account list in the store, class B.

## Decision

We will keep the server and its session as the store's class B object `server` (`VaultText`), on every platform: a
PLB envelope under a key from the keystore key `bg`, which the passphrase keystore holds when the store fell back. The
first read that finds none moves the entry earlier builds kept in the keystore into it and deletes that entry; a
keystore that does not answer then counts as holding none.

## Consequences

* Signing in works wherever the store opens, and the session is readable while the store is locked, for background
  backup (M2-18). On the web the session is sealed in the store, no longer in the plugin's storage (ADR-0125).
* Crypto-erase forgets the server and its session with the store; the server must be added again.
* A store that does not open has no server either; before, a store whose keys were lost still knew its server.

## Options considered

* **The passphrase keystore, only when the store fell back**: two places for one entry, and the passphrase keystore
  holds 32-byte keys, not text.
* **Class C**: unreadable while locked, which background backup needs.
* **The replica**: a schema change, and the session would sync into its backups (ADR-0125).
