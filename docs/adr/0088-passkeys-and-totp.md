# ADR-0088 — Passkeys and TOTP: a verifier on ring, a relay page for apps, a policy checked on every request

* **Status**: Accepted — 2026-10-20. The owner accepted all four decisions of M2-05 as made, the verifier on ring, the
  relay page, the policy for every account and TOTP secrets in the clear, reviewed on 2026-10-18 before the item landed
  (photolib-design#474).
* **Requirements**: R-SEC-1, PRIV-14, OPS-23. **Design**: 06 §2 and §10, research §8.5,
  server stack §6.1 and §6.4; the admin console's setting is [ADR-0063](0063-admin-console.md)'s.

## Context

Design 06 wants WebAuthn passkeys as a primary or second factor, TOTP with recovery codes and an instance policy that
can require a second factor; the research asks for single-use TOTP codes and WebAuthn challenges (Ente's audit found
both replayable) and names webauthn-rs and totp-rs. webauthn-rs needs OpenSSL, which photolibd does not link. A passkey
is bound to a relying party, the host of the server; Android accepts a native app for a host only through that host's
`assetlinks.json`, Apple only through an Associated Domains entitlement compiled into the app, so an app built once
cannot run native ceremonies for every self-hosted domain, and Linux has no platform passkey API at all. Password
sign-in (ADR-0052) opens a session in two steps and locks handles out.

## Decision

* **A small relying party on ring.** `webauthn.rs` checks WebAuthn Level 3 ceremonies in their JSON serialisation:
  type, challenge, origin (not cross-origin), relying party hash, user presence, user verification, the signature and
  a counter that must rise unless both counts are zero (synced passkeys). Attestation is `none`: the key is the
  authenticator's word, as for every consumer passkey. Keys are ES256, EdDSA or RS256 (Windows Hello), read from COSE
  with a definite-length CBOR reader bounded in depth and length, and checked with ring, which photolibd already links
  through rustls. Registration asks for a discoverable credential that verifies its user.
* **Passkeys alone or second.** A passkey that verifies its user signs in alone (`StartPasskeyLogin`,
  `FinishPasskeyLogin`), as two factors. An account with a passkey or TOTP finishes a password sign-in with either or
  with a recovery code (`FinishLoginResponse.second_factor`, `FinishSecondFactor`); there, presence suffices.
* **Single use everywhere.** Each challenge is 256 random bits held, with what it belongs to, under an id only the
  client knows, and taken on use. TOTP is RFC 6238 (SHA-1, six digits, 30 s, one step either side) and stores the last
  step a code counted for. Recovery codes are ten 80-bit base32 codes, stored as SHA-256, deleted when used; the first
  second factor of an account without codes comes with ten.
* **Guessing costs a sign-in.** A sign-in waiting for its second factor ends after five wrong answers, and the handle's
  lockout (ADR-0052) is cleared only when the second factor answers, so every five guesses cost a password sign-in and
  then a growing pause.
* **The policy is checked on every request.** Administrators require a second factor with the admin console's
  `require_two_factor` setting and reset an account's factors (`UserService.ResetSecondFactors`). While it is on, the
  session lookup marks an account without a passkey or TOTP, and every procedure but the auth service refuses it with
  `permission_denied` `second_factor.required`, which never signs the app out: a password sign-in opens a session that
  must enrol first, and turning the setting on restricts existing sessions at their next request. The setting applies
  to every account, not only new ones.
* **One relay for every app.** `public_url` names photolibd's origin; passkeys bind to its host. Without it there are no
  passkeys and `GetServerInfo` lists no `AUTH_METHOD_PASSKEY`. Apps run ceremonies on `/passkey` beneath `base_path` in
  the system browser (an `ASWebAuthenticationSession` on Apple platforms, a Custom Tab on Android, the default browser
  with a loopback port on desktops): the fragment carries the options, the app's label for the button and its return
  address, which may only be the `photolib:` scheme or `http://127.0.0.1`/`[::1]`; the page returns the credential
  there. The id that redeems a credential never leaves the app. The web app runs the same ceremony on its own origin.

## Consequences

* Passkeys work for every self-hosted domain on all six targets without per-domain app builds, at the cost of a
  browser sheet before the passkey prompt; native ceremonies can come later where a host serves `assetlinks.json`.
* On Android another installed app may claim `photolib:`; it can start its own sign-in and receive the assertion only
  if the person approves the passkey prompt for this server, as it could phish a password. A Custom Tab with an
  https App Link or Credential Manager would close it.
* The verifier is ours to keep correct: unit tests drive a software authenticator, an RS256 signature made by OpenSSL
  and mutated CBOR, and the gate's `web` part signs in with Chrome's virtual authenticator through the relay. An
  external review belongs to the pre-1.0 audit.
* The database holds TOTP secrets in the clear, which checking codes needs; a thief of the database alone still lacks
  the OPAQUE key file for passwords. Pending ceremonies live in the API process like pending logins (ADR-0052).
* Forced enrolment trusts the first enrolment: someone with only the password of an account without a second factor
  can enrol theirs. API keys are not restricted by the policy; they were made by a session.
* A person who lost every factor and code needs an administrator, who could already set a new password for them.
* The apps sign in with a password through the kernel's OPAQUE and answer a second factor with a code or, on desktops,
  a passkey through the relay ([ADR-0125](0125-sign-in-from-the-app.md)); passkeys on phones and the web, passkey-only
  sign-in and passkey PRF unlock (M6-03) are follow-up work.

## Options considered

* **webauthn-rs**: audited and complete, but it links OpenSSL into photolibd, its builds and images.
* **Native ceremonies per target** (Credential Manager, ASAuthorization, webauthn.dll): need the domain baked into
  App Store builds on Apple platforms and do not exist on Linux.
* **Checking the policy only at sign-in, or only for new accounts**: existing sessions or accounts would keep working
  without a second factor, the first until they expire, 90 days, the second for ever.
* **Refusing to sign in accounts without a second factor**: locks out everyone the moment an administrator turns the
  policy on.
* **TOTP secrets encrypted under a key outside the database**: would stop only a thief of the database, who cannot pass
  the password step without the OPAQUE key file anyway.
