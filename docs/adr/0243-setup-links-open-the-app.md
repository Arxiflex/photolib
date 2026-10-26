# ADR-0243 — A password setup link opens the app: photolibd's page hands it over through `photolib:`

* **Status**: Accepted — 2026-10-21. The owner confirmed all three decisions
  (photolib-design#610,
  the provisional choices of photolib-design#592): the `photolib:` hand-off page, the residual risk of another app
  claiming the scheme (T79), and what a link does when the install has a server.
* **Requirements**: R-SEC-1, R-APP-5. **Design**: 06 §3, 10 §7,
  [ADR-0052](0052-password-login-and-sessions.md), [ADR-0088](0088-passkeys-and-totp.md),
  [ADR-0125](0125-sign-in-from-the-app.md).

## Context

A password setup link, `<server>/#/password-setup?handle=…&token=…` (ADR-0052), worked only pasted into *Add a
server*: followed in a browser, or scanned from the console's QR code with a phone, it opened nothing, as photolibd
served nothing at its address and no app took links. The web app that will route it is M2-25's. Self-hosted servers
have no domain the apps could verify for https app links.

## Decision

* **photolibd serves a page at its address** (`/` beneath `base_path`, `relay.rs`) wherever passwords are on, until
  the web app takes its place. Its script turns the fragment into
  `photolib:/password-setup?handle=…&token=…&server=<the page's address>` behind an *Open in Photolib* link, and says
  in every launched language how to paste the page's address into *Add a server* instead. It runs under the relay's
  CSP, which the request middleware now keeps; the token stays in the fragment, which reaches no server.
* **Every app registers `photolib:`**: Android's intent filter and iOS's URL type through Flutter's deep links, macOS's
  URL type as Finder's opened files, the Linux desktop entry (`x-scheme-handler/photolib`, `%U`) and the MSIX protocol
  as arguments. The router's `/password-setup` route, on the web the link itself, hands it over.
* **The app only fills in what the person confirms**: without a server, *Add a server* with the link in its addresses;
  for the saved server, signed out, its password page; otherwise the server's page says to sign out or remove it
  first, as an install has one server (ADR-0125).

## Consequences

* A link followed on a phone or a desktop with the app installed opens *Add a server*; without the app, the page says
  what to do.
* Any app may claim `photolib:` on Android and desktops (T79): one that does receives the token when the person picks
  it, or when Photolib is not installed, and can set the password first. The token is single-use and expires in seven
  days; https app links would close this but need a verified domain per server. The owner accepts this residual risk,
  as ADR-0088 accepted it for passkey assertions.
* The page is the first server-side text in every launched language; `tools/tests/test_setup_page.sh` holds it to the
  apps' locales and their words.
* M2-25's web app replaces the page at `/` and takes the same route.

## Options considered

* **Instructions only, no hand-off**: no interception, but a phone user copies an address and switches apps.
* **A `photolib:` link in the QR code itself**: opens nothing without the app, and cameras differ in what they open.
* **https app links**: need `assetlinks.json` and associated domains per self-hosted server, baked into store builds.
