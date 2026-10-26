# ADR-0125 — Signing in from the app: one server per install, its session in the keystore, the bearer on its endpoint

* **Status**: Accepted — 2026-10-20. The owner kept where the app keeps a server and its session, one server per
  install, folder backup with M2-18 and sign-in with an email, and changed how the session crosses plain HTTP and how
  new passwords' Argon2id is set (photolib-design#480). On 2026-10-23 the owner kept the
  three choices photolib-design#522 made (photolib-design#674): passwords set before keep
  their parameters until photolibd can change a password; in browsers only an address or `localhost` counts as local;
  and ADR-0057 and ADR-0065 were not accepted on that answer's mention: both have since been accepted on their own
  answers. On the same day the owner kept photolib-design#481's choices: the library each account gets, passkeys
  through the relay on desktops only, renewal once fewer than 60 of 90 days are left, sync every five minutes and the
  4 GiB line for Argon2id's start cost (photolib-design#719).
* **Requirements**: R-SEC-1, R-APP-5. **Design**: 06 §3, 10 §9,
  [ADR-0032](0032-one-network-stack.md), [ADR-0052](0052-password-login-and-sessions.md),
  [ADR-0065](0065-photolib-upload.md).

## Context

photolibd signs devices in with OPAQUE and device-bound sessions (ADR-0052) and the kernel runs the client's side, but
no screen let a user add a server or sign in, so the admin console and everything else that talks to a server was
unreachable from the apps. The replica syncs with one server (its cursors name no server), and the design leaves open
where the app keeps a session and how it tells an administrator from anyone else.

## Decision

* **One server per install**, in Settings: addresses, a private CA, a client certificate (PKCS#12, any target but the
  web, whose browser owns TLS), an HTTP proxy and headers (docs/admin/clients.md),
  a confirmed self-signed certificate's SHA-256 and the instance id of the first answer. Several servers, a replica
  each, came with M2-38 ([ADR-0234](0234-several-accounts.md)).
* **The server and its session are one entry of the platform keystore** (`photolib.keystore.server`, JSON), as the
  device data key's keys are (ADR-0057): the session token and custom headers are secrets, and the replica would need
  a migration for no gain. A revocation deletes the session; an unreachable server or a proxy's page never does.
  [ADR-0209](0209-server-session-in-the-store.md) moves the entry into the local store, class B.
* **The session is a bearer on every request to the endpoint in use**: over HTTPS, or over plain HTTP only to an
  address photolibd itself counts as local (`proxy::local`: loopback, private and link-local; IPv6 loopback,
  unique-local and link-local), judged at every call by every address the endpoint's name resolves to. A session is a
  plain 256-bit bearer (ADR-0052), so one sniffed on a public network is the whole session until it is revoked. To any
  other address over plain HTTP the app sends no session, chooses an endpoint the session may go to if there is one,
  and says the server needs HTTPS (`HttpsRequired`), as it does when photolibd refuses a sign-in there
  (`login.insecure_http`). The session never goes on the `GetServerInfo` probes that choose an endpoint, which may
  reach another machine at the same address. A call that finds no endpoint chooses again at the next.
* **People sign in with an email or a sign-in name**: `StartLogin` takes either; they never collide, as a handle has
  no `@`.
* **New passwords are calibrated at enrolment** as docs/dev/crypto-v1.md says, to about a second on the enrolling
  device: the app times one Argon2id derivation `T` at 256 MiB and three passes, or at 128 MiB and six where 256 MiB
  cannot be had (the kernel fails the derivation, or an Android phone has less than 4 GiB of memory), and takes
  `t = ⌈t₀ · 1 s / T⌉` passes, never fewer than those three or six and at most 64, within the account policy, with a
  fresh salt. Only enrolment pays for it: a sign-in uses the account's parameters.
* **The console shows to an account that may read the server's settings**, which the app asks at sign-in, at each
  start and when the console is refused `user.admin_required`.
* **The session is renewed at a start once fewer than 60 of its 90 days are left** (`RotateSession`, ADR-0052), as
  the owner kept it in photolib-design#719, where ADR-0052's answer had renewed it at every start: the owner is asked
  again which stands. A call that the renewal outran, refused with the old token, signs nothing out.
* **A second factor challenge** (ADR-0088) is answered with an authenticator code or a recovery code
  (`FinishSecondFactor`), or on desktops with a passkey through photolibd's relay page in the default browser, which
  returns to a port on `127.0.0.1`. Phones (the `photolib:` scheme) and the web app need native or own-origin
  ceremonies first; until then they, and a server offering passkeys only, say that this version cannot sign in there.
* **Folder backup stays with M2-18** (ADR-0065), which carries the desktop app's folder items, BLAKE3 hashing in the
  app and a library for the account. Its first part landed with photolib-design#481: desktops back their folders up
  after each sync, into the account's upload target, the managed library photolibd gives every account that may
  upload: in the data isolate, hashing with BLAKE3 on a worker, each present folder item goes through `backup_state`
  (hashing, uploading, backed_up, or failed with the server's reason and a retry an hour later) with
  `Server.createUpload`/`sendUpload`. Selection, conditions, deduplication before upload, its 10k-item test and the
  phones' galleries stay with M2-18, whose engine (ADR-0226) keeps the refusal's hour, then waits longer each time.

## Consequences

* The admin console, sync (M2-15) and backup (M2-18) have a signed-in `NetworkConfig` to use. The replica syncs at
  start and sign-in, then every five minutes while the app runs (natively; browsers have no data worker yet).
* Passwords set before keep their parameters until they are set again: crypto-v1's re-derivation at the next entry
  needs a password change, which photolibd has no procedure for yet.
* A native kernel that cannot allocate 256 MiB aborts the app rather than failing the derivation, so the fallback to
  128 MiB serves the web's module, whose memory may not grow, and Android phones with less than 4 GiB of memory
  (`/proc/meminfo`); another phone the system would deny 256 MiB is not detected.
* A forgotten administrator password, or a first setup that failed half-way, is recovered from the host:
  `photolibd admin password-setup <handle>` prints a new setup link (ADR-0052). A setup that stops after the first
  administrator is created keeps their password setup token with the server in the store until the password is set,
  so *Set a password* finishes it after a restart.
* A web app kept the session in the browser's storage under the plugin's WebCrypto key, weaker than the native
  keystores, until ADR-0209 sealed it in the store.
* The endpoint is chosen again only after a failure, not on every network change; over plain HTTP a name is looked up
  at every call with the session, so on another network it is judged where it resolves there.
* A browser resolves names itself and does not say to what, so there only an address or `localhost` counts as local: a
  plain-HTTP server named otherwise needs HTTPS in the web app.

## Options considered

* **Servers in the replica**: encrypted already, but a schema change and a migration, and a session would sync into the
  replica's backups of local-only data.
* **Several servers now**: the replica's cursors and the sync engine assume one; M2-38 owns switching.
* **The bearer over plain HTTP to any endpoint in use**, as first decided: a session sniffed beyond the local networks
  is the whole session.
* **The bearer over HTTPS only, like custom headers**: a LAN server on plain HTTP could not be used at all.
* **256 MiB and three passes for every device**, as first decided: a fast device's password costs a guesser less than
  the second crypto-v1 asks for.
* **A role in the session**: photolibd's `Session` has none, and probing a setting needs no API change.
