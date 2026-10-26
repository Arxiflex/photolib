# ADR-0242 — Step-up: a fresh proof on the session before a way in is added, removed or replaced

* **Status**: Accepted — 2026-10-23. The owner kept that an OIDC sign-in is no proof and that a passkey must verify its
  user, and changed which calls ask: adding a passkey and changing the password need a step-up too, a first TOTP
  secret and an account with nothing to prove itself with do not
  (photolib-design#717).
* **Requirements**: R-SEC-1, PRIV-14. **Design**: 06 §2 (stolen unlocked device); extends
  [ADR-0088](0088-passkeys-and-totp.md).

## Context

With ADR-0088 a session alone deletes a passkey, turns TOTP off, replaces the recovery codes or the TOTP secret. Whoever
holds a signed-in, unlocked device can strip the account's second factor, or swap in their own, and keep the account
after the device is revoked.

## Decision

* **The proof lives on the session.** `sessions.proved_at` records when the session last proved its person; no
  request carries a proof. A sign-in that opens the session counts: a password, a password and a second factor, or a
  passkey alone. An OIDC sign-in does not: the provider's browser session may live on the stolen device.
* **Five minutes.** DeletePasskey, DeleteTotp, CreateRecoveryCodes, StartTotpSetup on an account that has a TOTP
  secret, StartPasskeySetup, and StartPasswordSetup and FinishPasswordSetup with a session rather than a setup token
  answer `permission_denied` `step_up.required` (which never signs the app out) unless `proved_at` is younger.
  A TOTP setup started without a proof never replaces a secret enabled meanwhile.
* **Nothing to prove with, nothing asked.** A first TOTP secret needs no proof, as forced enrolment (ADR-0088) relies
  on it; nor does a first passkey or password of an account with no password, second factor or recovery code yet, such
  as one that signs in with OIDC alone, which could not step up.
* **StartStepUp, FinishStepUp.** The session proves its person with the password (OPAQUE, as a sign-in), a TOTP code,
  a recovery code, which it uses up, or a passkey that verifies its user: the thief may hold the device that holds a
  platform passkey, so presence alone is not enough. Each start counts towards the handle's lockout (ADR-0052) and
  takes one answer; a right one clears the count, sets `proved_at` and is audited as `session.step_up`.
* **Apps ask and retry once.** The server page's *Second factors* and the admin console's section of the same name
  list the passkeys, the authenticator app and the recovery codes, and on desktops add a passkey through the relay; a
  change answered with `step_up.required` asks for the password or a code, steps up and runs once more (`withStepUp`).

## Consequences

* A thief of an unlocked device can no longer remove or replace a second factor, add their own passkey or change the
  password without the password or a factor.
* A thief can still enrol a first TOTP secret, and add a way in to an account that had none: there was nothing to
  protect it with.
* The apps set no password with a session yet; when they do, the call goes through `withStepUp`.
* The apps offer no passkey step-up yet, though desktops run passkey ceremonies through the relay: an account signed
  in with a password proves itself with it.
* Sessions from before the migration have no proof: their first change asks for one.

## Options considered

* **A proof in each request** (a password-derived token or an assertion per call): the issue rules it out, and a
  request replayed within its window would carry it.
* **Keeping the proof in the API process**, like pending sign-ins: another process would not see it.
* **Counting an OIDC sign-in**: the provider's own session on the stolen device would re-authenticate the thief.
* **Only removals and replacements**, as first proposed: a thief could add their own passkey and keep the account.
* **A step-up for every factor change, first TOTP too**: a forced enrolment older than five minutes would have to step
  up first, and an account with nothing to prove itself with could not.
* **Presence-only passkeys** as at a second-factor sign-in: there the password came first; here the passkey stands
  alone.
