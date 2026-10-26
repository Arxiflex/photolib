# ADR-0087 — OIDC single sign-on: a PKCE code flow the client holds, checked claims, identities by issuer and subject

* **Status**: **Proposed** — owner to confirm. M2-04 had to choose how photolibd trusts an OpenID Connect provider,
  how a person's identity finds their account and what the provider's claims may change. Becomes *Accepted —
  YYYY-MM-DD* when the owner decides.
* **Requirements**: R-SEC-2, PRIV-13. **Design**: 06 §4 and §10, 16 §3,
  open decision 16.

## Context

Households and homelabs sign in through Authentik, Keycloak, Authelia or a cloud provider (PRIV-13). Apps must use
the system browser with PKCE, and several providers, account linking, an auto-provisioning policy and roles from
claims are expected. Claims come from another system: a malformed one must fail one sign-in, never the API, a
`data:` picture must be refused and no picture fetched unless allow-listed (lessons P-25). OIDC proves identity but
never unlocks private-mode keys (06 §4).

## Decision

* **photolibd is the relying party**; each provider is `oidc.<id>` in the configuration, a confidential client
  (`client_secret_basic`) or a public one. `StartOidc` returns the authorization URL of a code flow with `state`,
  `nonce` and the client's PKCE S256 challenge; `CompleteOidc` brings the code and the verifier. Only the client that
  started a flow knows its verifier, so another app that catches the redirect to `app.photolib:/oidc` redeems nothing.
  Flows live in the API process's memory for ten minutes, bounded to 10 000, like OPAQUE logins (ADR-0052).
* **Everything from the provider is checked**: the discovery document must name the configured issuer exactly, and
  every endpoint must be HTTPS (HTTP only on loopback); the ID token must be signed by a key of the JWKS for its
  algorithm (RS, PS, ES256/384 or EdDSA; never HMAC or `none`) and name the issuer, the client (`aud`, `azp`) and the
  nonce, unexpired with a minute of skew. Userinfo, when advertised, must name the same subject and adds its claims
  (Authelia sends profile claims only there). Each answer is read within 10 s and 64 KiB, without redirects.
* **The claims photolibd reads have types and sizes** (`sub` up to 255 characters, `email` up to 254 with one `@`,
  `email_verified` a boolean, names up to 255 printable characters, the role claim up to 1 000 strings); a claim
  that breaks them fails that sign-in with `oidc.claim_invalid` and its name. `picture` must be an `https:` URL and is
  never fetched: with no avatars yet there is nothing to allow-list.
* **An identity is its issuer and subject** (`oidc_identities`), never its email; an account may have several. It
  reaches an account when linked; else, with `link_by_email`, through the active account with its verified email;
  else, with `provision`, by creating an account (handle from `preferred_username` or the email, with a suffix when
  taken; the verified email unless taken). Both policies are off by default; otherwise `oidc.not_allowed`. A
  signed-in session links an identity with `link`; one linked elsewhere is `oidc.identity_taken`.
* **Roles from a claim** (`roles: {claim, admin, user, viewer}`): the highest role any value maps to, at every
  sign-in, so the provider stays the source of truth; no match refuses the sign-in, and the last administrator stays
  one. Without a mapping, new accounts are `user` and roles are managed in photolibd.
* **Forward-auth (open decision 16) is not part of this**: identity headers from a proxy stay unsupported until the
  owner decides; the recommended opt-in mode, accepted only from `trusted_proxies`, would be its own task.

## Consequences

* Sign-ins at Keycloak 26.8 and Authelia 4.39 are recorded in `testdata/oidc/` and replayed by the gate;
  `tools/oidc/signin.py` repeats them against live providers. Authentik and cloud providers are covered by a fake
  provider with their claim shapes only, until someone runs the ignored real-provider test against them.
* With several API processes, a flow's two steps must reach the same process (sticky routing), as for OPAQUE.
* A private CA for the provider is trusted through the system's roots (`SSL_CERT_FILE`).
* Groups must be a top-level claim: Keycloak needs a group or role mapper.
* Follow-ups: the apps' and web client's sign-in screens (system browser, the verifier kept on the device), listing
  and unlinking identities, quotas from claims (LIB-18), avatars from an allow-listed picture host.

## Options considered

* **The `openidconnect` crate**: brings reqwest and its own TLS and JOSE stacks; photolibd already has rustls, ring
  and an HTTP client for S3.
* **Trusting TLS instead of the ID token's signature** (OIDC Core §3.1.3.7 allows it for the code flow): no defence
  for loopback HTTP or a compromised token endpoint path, for a few lines saved.
* **The PKCE verifier on the server**: an app that intercepts the custom-scheme redirect could redeem the code.
* **Linking by email by default**: a provider that lets people set unverified or reused addresses would hand over
  accounts; it is opt-in per provider and needs `email_verified`.
* **Fetching pictures from an allow-list now**: there is no avatar storage to put them in.
* **Flows in PostgreSQL**: works across processes but needs a cleanup job; kept for when several API processes are
  supported, as in ADR-0052.
