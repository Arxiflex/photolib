# ADR-0311 — Reaching the server without a network degree: discovery, pairing, guided tunnels and a relay later

* **Status**: Accepted — 2026-10-23 (roadmap M2-47). The owner kept all four decisions as made: photolibd answers
  LAN discovery by default, check-host.net tests the public URL only when an administrator asks, no relay in 1.0,
  and a metered network is mobile data without Wi-Fi or Ethernet
  (photolib-design#713).
* **Requirements**: R-OPS-1, R-COMP-1; OPS-28, OPS-29, OPS-30, MOB-16, MOB-17. **Design**:
  10 — client app,
  15 — operations,
  Play reviews §1.

## Context

After backup, reaching the server is why people give up on a self-hosted photo server (Immich: "you need a computer
science degree", 31 reviews; "the browser works but the app says not reachable", 18; Synology: QuickConnect, VPN, DDNS
and ports, 75; "error 117", 48 reviews of errors nobody could act on). Photolib already had one network configuration
per server with several addresses, pinned self-signed certificates and appends under a proxy's cap (ADR-0032). What was
missing: finding the server without typing, carrying its addresses to a second device, a way in from outside without
port-forwarding, saying which step of a connection fails, and errors that name a cause and a next step.

## Decision

We will:

1. **Discover on the LAN by multicast DNS**: photolibd answers DNS-SD questions for `_photolib._tcp.local` with its
   port, instance, base path and `public_url` (`discovery: true` by default, only when it listens beyond loopback and
   runs `api`), and never announces on a timer. Apps ask from an ephemeral port, which responders answer by unicast
   (RFC 6762 §6.7): no multicast port to share with the system's responder and no location permission. A container needs
   the host's network for it.
2. **Pair by link**: the admin console's *Pair a device* shows a link and its QR code, the server's first address with
   the other addresses, the certificate pin and the instance in the fragment (never in a server log); *Add a server*
   takes it, and a password setup link carries the same.
3. **Switch addresses on network changes**: a session's link selects its address again whenever the device joins or
   leaves a network (connectivity_plus), so the WAN takes over at once rather than after a failed call.
4. **Guide remote access without port-forwarding** ([remote access](../admin/remote-access.md)): Tailscale or Headscale
   (`tailscale serve`), WireGuard (one UDP port, or a hub) and Cloudflare Tunnel (`deploy/proxy/cloudflared.yml`), with
   the configuration filled in by the admin console, and the 100 MB request cap of Cloudflare's free plan answered by
   8 MiB appends.
5. **Test the public URL from outside through check-host.net**, a free, relay-free service whose nodes fetch a URL and
   report the status: only when an administrator taps *Test from outside* and confirms the host, so nothing is sent by
   default (privacy manifest). The connection check on a phone on mobile data is the self-hosted alternative.
6. **Check a connection step by step** in every app: DNS, TCP, TLS and the certificate, photolibd's answer and versions,
   the session, an upload append through the proxies (`POST /healthz`), the metered network and the clock; the failing
   step names its cause, the next step and a fix.
7. **Speak plainly**: every reason photolibd sends has a cause and a next step in every language (the catalogue of
   `app/lib/core/problems.dart`), technical detail only behind *Details* with copy, enforced by
   `tools/tests/check_errors.py`.
8. **Leave the relay for later**: no hosted or end-to-end encrypted relay of our own in 1.0 (options and costs below).

## Consequences

* A fresh install on a host network is listed by every desktop and Android app on its LAN; the iOS app needs Bonjour
  through `NWBrowser` and a local network usage string, which this decision leaves to a follow-up, as it does scanning a
  QR code inside the app and registering the link with the operating systems.
* check-host.net learns the public URL of a server whose administrator runs the test; it can rate-limit or change its
  API, which fails the test, never the server.
* `POST /healthz` takes up to 16 MiB from anyone who can reach photolibd, as any upload request already does.

## Options considered

* **A relay the project hosts (QuickConnect-like)**: everything works without any setup, but every remote byte crosses
  our servers: at about 0.01–0.09 USD per GB of egress, a family backing up 50 GB a month and browsing 20 GB costs us
  0.70–6.30 USD a month each, plus operations, abuse handling and a privacy promise to keep. Synology's reviews show it
  slow even so. Not for 1.0.
* **An end-to-end encrypted relay of our own** (a TURN-like rendezvous that sees only ciphertext): the privacy problem
  goes, the bandwidth cost and the operations stay, and it needs a NAT traversal stack in every app. A later decision.
* **Tailscale Funnel or ngrok as the default**: public HTTPS without a domain, but a third party in every request and
  limits on the free plans; kept as an option the Tailscale path mentions.
* **UPnP or NAT-PMP to open a port**: what users ask to avoid, unsafe by default on many routers.
* **A self-test from photolibd itself** (fetching its own public URL): a router without hairpin NAT fails it falsely,
  and a tunnel is tested from inside; an outside node is the honest test.
* **Announcing on a timer**: more traffic and a periodic task for no gain: apps ask when they show the list.
