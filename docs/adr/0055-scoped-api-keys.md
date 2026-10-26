# ADR-0055 — Scoped API keys: a key acts as its account within its scopes

* **Status**: Accepted — 2026-10-17. The owner confirmed all four decisions as made
  (photolib-design#369,
  whose questions call this ADR 0041): a required expiry, the policy's actions as scopes with no key managing keys, a
  bucket of 600 requests a minute per key in each API process, and a service of its own.
* **Requirements**: R-SEC-1. **Design**: 16 §3, §6, 06 §10, feature PRIV-16.

## Context

Scripts, the CLI and other programs need a credential that is not a person's password or session: one with explicit
scopes, an expiry, its last use and a rate limit of its own (PRIV-16). The design leaves the scopes, the secret's form,
whether an expiry is required and how the rate is counted open. Every request already passes one policy
([ADR-0038](0038-authorization-policy.md)).

## Decision

* **A key is its account, narrowed.** `Principal::Key` carries the account, its role and the key's `Scopes`: a set of
  the policy's actions (view, download, contribute, edit, delete, share, manage users). For an action in its scopes a
  key is its account, for any other nobody, in route rules, `can` and `scope` alike; so it never exceeds what its
  account may do, and a viewer's key never edits. Refused for a missing scope, a call answers `permission_denied` with
  `api_key.scope_missing`.
* **No key manages keys.** `ApiKeyService` (list, create, revoke) needs the new action `ManageKeys`, which every
  active account has and no scope gives, so a leaked key can neither mint nor keep others. It reads and revokes only
  the caller's keys. A separate service rather than design 16's `AuthService` keeps it apart from sign-in.
* **The secret** is `plk_` and 64 hexadecimal digits, 256 random bits sent as `Authorization: Bearer <secret>`; the
  prefix tells it from a session token and lets secret scanners find it. Only its SHA-256 is stored, as for link
  tokens: an unsalted fast hash suffices for a random secret. The server shows it once.
* **Expiry is required**, at most at the end of year 9999. An unknown, revoked or expired key, or one of an account
  that cannot sign in, signs nothing: the request is anonymous.
* **Last use** is recorded to the minute, so that a busy key does not write on every request.
* **The rate** is requests per minute, 600 unless set (1 to 60,000), counted per key in each API process by a bucket
  holding a minute's worth: a full minute may come at once, then requests refill at the rate. Beyond it a call
  answers `resource_exhausted` with `api_key.rate_limited`.
* Creating and revoking a key are audit events (`api_key.create`, `api_key.revoke`).

## Consequences

* Both authz matrices have key columns; a new action decides whether it is a scope.
* Several API processes each allow the full rate; a shared limit would need the database or another service.
* Keys of a disabled or deleted account stop at once and work again if the account is restored before its purge.
* Owners rotate keys by creating a new one and revoking the old; there is no renewal of the expiry.

## Options considered

* **Keys with every right of their account**: what PRIV-16 asks to avoid.
* **Free-form scope strings** (`assets:read`): a second vocabulary beside the policy's actions to keep in step.
* **Optional expiry**: never-expiring keys are what leaks; requiring one first is the reversible choice.
* **Argon2id over the secret**: costs every request and adds nothing for 256 random bits.
* **A rate limit in PostgreSQL**: exact across processes, at a write per request.
