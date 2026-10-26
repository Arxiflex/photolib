# ADR-0052 — Password login: OPAQUE with a key file, setup tokens, device sessions and a progressive lockout

* **Status**: Accepted — 2026-10-17. The owner answered M2-02's provisional choices in
  photolib-design#370
  (whose questions call this ADR 0043): setup tokens stay, shown as a link and a QR code, with a host command and a
  reset that says what private libraries need (1); the key file's path is configurable and never in `data_dir` (2); the
  thresholds and the in-memory state stay, with device secrets and a count per address (3); 90-day sessions stay,
  renewed at every start with a grace for the old token (4). Applied in photolib-design#402. The owner kept #402's
  choices (photolib-design#591,
  2026-10-21): thirty free attempts per address, then the handle's pauses; the device secret each sign-in renews; the
  setup link with the token in the fragment, which photolibd's page hands to the app (ADR-0243); and the notice about
  private libraries before a reset by token.
* **Requirements**: R-SEC-1, R-PRIV-1, PRIV-15, PRIV-22, PRIV-23. **Design**: 06 §3 and §10,
  research §6.6 and §8.5, [crypto spec][crypto].

## Context

Passwords must never reach the server, and nothing it stores may let a thief of the database test guesses offline
(06 §3: OPAQUE, RFC 9807). The crypto spec fixes the OPAQUE configuration and puts the OPRF seed and the server key
outside the database. Sessions must be revocable from any device and bound to one; guessing must be rate limited with
progressive lockout and uniform errors (research §8.5). M2-01 created accounts but nobody could sign in.

## Decision

* **OPAQUE on the server** with `opaque-ke` 4.0.1 and the spec's configuration (context `photolib/v1/opaque`, default
  identities); a test replays the spec's vectors through the server's functions. The credential identifier is the
  account id and 16 random bytes, new for every password (`registration_id`): with the account id alone, every
  password setup would evaluate the OPRF key of the password that signs in, so a session or a setup token could test
  guesses offline, past the lockout. Clients run the KSF (Argon2id with the account's parameters, which the server
  stores next to the record, checks against the account policy and returns at login); the server never runs it.
* **The key file** `opaque_key_file` (mode 0600; also `PHOTOLIB_OPAQUE_KEY_FILE`, so that a Docker secret works) holds
  the OPRF seed and the server key pair: by default `opaque.key` beside the configuration file, never in `data_dir`.
  The library root is synced, shared and copied and holds the pre-upgrade dumps in `<data_dir>/backups`, so a copy of
  it would carry both the dump and the key; photolibd refuses a key file there. It makes the key on the first start and
  refuses to start without it once a password exists, rather than silently breaking every login. Without a
  configuration file an `api` process needs the setting; the compose bundle mounts `keys/`.
* **Password setup tokens**: a person sets their own password with a one-time token (256 bits, stored as SHA-256,
  seven days), which `CreateFirstAdmin` returns for the first administrator and `UserService.CreatePasswordSetup`
  makes for anyone else; a signed-in session may change its own password. Administrators never learn a password. The
  console shows a token as a link and a QR code, `<server>/#/password-setup?handle=<handle>&token=<token>` (the token
  in the fragment, which reaches no server's log), to send by any channel; by e-mail too once SMTP is configured
  (M3-11). The apps' *Add a server* takes the link. `photolibd admin password-setup <handle>` prints one on the host,
  with the configuration and the database and no account acting, so that an instance whose only administrator forgot
  the password is not lost. `StartPasswordSetup` says when a reset's account has private libraries, and the app says
  first that a new password does not reopen them: the recovery kit, a passkey or a device still signed in does (06 §6).
* **Two-step login** (`StartLogin`, `FinishLogin`). An unknown handle, an inactive account or one without a password
  gets a fake KE2 and Argon2id parameters that cost what those of an account picked by a keyed hash of the handle
  cost, with a salt keyed by that cost and the handle, so a fake stays the same per handle and changes its salt with
  its cost, as a real password does. One statement serves every handle, so a fake takes no longer to answer.
* **Sessions**: a 256-bit token sent as a bearer, stored as SHA-256, tied to a device row (created at login, or reused
  when the client names its device). Every request looks the token up, so revoking a device (deleting its row and,
  by cascade, its sessions) or disabling the account takes effect at the next request. A session lasts 90 days;
  `RotateSession` replaces its token and extends it, and the apps rotate at a start once fewer than 60 of its 90 days
  are left (ADR-0125, photolib-design#719), so a device in use never expires and a lost one does after 90 days.
  After a rotation the old token keeps working until the new one is first
  used, or for 24 hours, so that a lost response never signs a device out. Logins, password changes and revocations
  go to the audit log.
* **Progressive lockout** (PRIV-22): every `StartLogin` counts, because a client learns from KE2 whether its guess was
  right without sending KE3; five are free, then the pause starts at 30 s and doubles up to an hour; a sign-in clears
  the handle and a quiet day forgives it. Unknown handles count the same. No account lock waits for an administrator.
  A device that has signed in before proves it with the secret its last sign-in gave it (`Session.device_secret`,
  stored as SHA-256 on its device row, new at each sign-in) and counts its attempts apart from everyone else, so
  guessing at a known handle locks out only the guesser. Signing a device out keeps it known; revoking it from another
  device forgets it. Every other attempt also counts per address now that `trusted_proxies` exists (15 §9): the
  client's address as a trusted proxy forwards it, else the peer's, IPv6 per /64; thirty are free, then the same
  pauses, and a sign-in does not clear them. Loopback and a trusted proxy that names no client are not counted, as
  every client behind them would share their address; an untrusted peer is the client whatever headers it sends, so
  that no guesser leaves the count by adding one.
* **Pending logins and the lockout live in the API process's memory**, bounded (10 000 logins, 100 000 handles,
  devices and addresses; when full, new ones wait).

## Consequences

* A stolen database without the key file checks no password guess; losing the key file breaks password login (not
  data, whose KEK is independent) until it is restored from a backup, so it is backed up apart from the database
  dumps, never beside them.
* With several API processes, a client's two login steps must reach the same process (sticky routing) and each
  process counts attempts separately; a restart forgets the counts. Moving both to PostgreSQL is the change if that
  matters.
* One address spraying guesses across handles gets thirty, then about one an hour. A household or office behind one
  address gets thirty sign-ins of new devices a day before the pauses start; its known devices count apart.
* An operator whose only administrator forgot the password, or whose setup stopped before it was set, gets back in
  from the host, never through the API.
* The setup link names no host of its own: followed in a browser, photolibd's page at its address hands it to the app
  (ADR-0243) until photolibd serves the web app (M2-25).
* Clients sign in with the kernel's OPAQUE (M6-01); every account lists its devices and signs them out on the app's
  server page (*Your devices*).

## Options considered

* **SRP-6a or Argon2id hashes on the server**: the server would learn the password or a precomputable verifier.
* **The OPRF seed in the database or derived from an admin secret**: a leaked database would allow offline guessing,
  or the secret would become one more thing to type.
* **Initial passwords set by administrators**: simpler, but the administrator knows the password that later unlocks
  private libraries.
* **Stateless signed tokens (JWT)**: cannot be revoked within one request without a lookup anyway.
* **Lockout state in PostgreSQL**: survives restarts and works across processes, but unknown handles would fill a table
  without a cleanup job; kept for when several API processes are supported.
* **Counting only failed `FinishLogin`s**: an attacker who never sends KE3 would never be counted.

[crypto]: ../dev/crypto-v1.md#opaque
