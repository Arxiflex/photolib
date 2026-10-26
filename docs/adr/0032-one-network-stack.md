# ADR-0032 — One network configuration per server, on dart:io until the OkHttp and URLSession stacks

* **Status**: Accepted — 2026-10-16. The owner confirmed all five choices M0-09 made: dart:io on every native target,
  headers over HTTPS only, no redirects, the epoch as the pinned instance and 8 MiB appends
  (photolib-design#312).
* **Requirements**: R-APP-1, R-APP-3, MOB-16. **Design**: 10 §9, 16 §2,
  [ADR-0027](0027-connect-rpc.md).

## Context

Design decision D5 gives each server one network configuration — endpoints, trust anchors, client identity, proxy,
headers — applied through one stack per platform to API calls, thumbnails, video and uploads: OkHttp on Android,
`URLSession` on iOS and macOS, dart:io on Windows and Linux, fetch on the web. In Immich the API, the player and the
uploader each had their own stack, so private CAs and client certificates worked in one and not the others.

The released plugins cannot carry that configuration yet: ok_http 0.1.0 builds an `OkHttpClient` with no
`SSLSocketFactory` and no key manager, and cupertino_http 3.1.0 has no authentication-challenge delegate, so neither
accepts a private CA or a client certificate. dart:io can, on every native target: its `SecurityContext` takes PEM
trust anchors and a PKCS#12 identity on Android, iOS, macOS, Windows and Linux alike.

## Decision

* **`NetworkConfig` is the one configuration of a server** (`app/packages/photolib_api`): endpoints, a private CA,
  a PKCS#12 client identity, the SHA-256 of a self-signed certificate confirmed on first use, an HTTP proxy, headers
  for every request and a timeout. `httpClient(config)` builds the server's one `package:http` client from it, and
  `Server` sends everything through that client: Connect calls, media with byte ranges and upload appends.
* **Every native target uses dart:io's `HttpClient` with an explicit `SecurityContext`** (system roots plus the
  configured CA and identity); the web uses the browser's fetch, where TLS, client certificates and proxies are the
  browser's, so a private CA or a client certificate must be installed in the browser or the operating system.
* **Players that cannot use the client read through the loopback media proxy**: `MediaProxy` serves the server's
  media on `127.0.0.1` behind a random 256-bit path token, without CORS, and fetches each request, byte ranges
  included, through `Server.get`.
* **Connect runs over the client in the protocol's binary form**: `Server.rpc` implements the `RpcClient` that
  protoc_plugin's generated `…ServiceApi` classes take, so no further code generator is needed. The viewer's
  TypeScript client does the same over fetch with protobuf-es method descriptors.
* **A server's headers and identity stay with it**: the client follows no redirect (a forward-auth login page is
  `Unreachable`), sends the configured headers over HTTPS only, where TLS has proved who answers, and refuses a path
  that resolves to another origin, the loopback proxy included.
* **Only an explicit revocation logs out**: an `unauthenticated` Connect error that carries an `ErrorDetail` reason.
  Anything that is not photolibd's own answer — a reverse proxy's 502, 504, 413 or 401 page, a captive portal, a
  timeout, a TLS or network failure — is `Unreachable`, and the app goes offline. Both clients apply the same rule.
* **The endpoint is the fastest that answers as the pinned instance** (MOB-16): `selectEndpoint` probes every URL
  with `GetServerInfo` and keeps the first whose epoch, the instance id (ADR-0027), matches.
* **Uploads go as appends of at most 8 MiB**, under a proxy's 100 MB request cap and sent within a 60 s proxy timeout
  from 1.2 Mbit/s; the resumable-upload protocol around them is M2-07's.
* **OkHttp and `URLSession` come with the work that needs them**, behind the same `http.Client` and built from the
  same `NetworkConfig`: ExoPlayer's data source (M1-12) and WorkManager and background `URLSession` transfers (M0-32,
  M2-19, M2-20). Cronet stays out: it has no client certificates and needs Play Services.

## Consequences

* A private CA, a client certificate, a pinned self-signed certificate and a proxy work the same on every native
  target today, which tests prove against a stand-in reverse proxy with mutual TLS on Linux and in browsers.
* dart:io speaks HTTP/1.1 only and does not read the system proxy settings; the user enters a proxy per server.
* The epoch changes on restore (design 05 §8), so the endpoint check compares its instance id, before the restore
  count ([ADR-0120](0120-client-sync-engine.md)).
* `RpcClient` is unary; `Server.sync` is the one server-streaming call.
* The viewer's TypeScript stays on 6.x: 7.x starts a native binary, which a checkout on a `noexec` mount cannot run.

## Options considered

* **ok_http and cupertino_http now.** Rejected: neither accepts a private CA or a client certificate, so they would
  break the one configuration that this decision exists for.
* **Our own Kotlin OkHttp factory and Swift `URLSession` delegate now.** Deferred: nothing in M0 needs background
  transfers or a native player, and the native code needs device tests that this work could not run.
* **The `connectrpc` Dart package and `@connectrpc/connect-web`.** Rejected: they need another code generator or a
  larger bundle, and both turn a proxy's HTML 401 into the `unauthenticated` code, the error that logged Immich users
  out.
