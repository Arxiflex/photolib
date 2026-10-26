# Remote access without port-forwarding

Reach photolibd from anywhere without opening a port for HTTPS on your router. Pick one of three paths; each gives the
server an HTTPS address. The admin console's *Remote access* (**Settings → Server administration**) shows the same
paths with the configuration filled in from this app's addresses, and *Test from outside* then checks the address from
the internet. The choices behind this page are [ADR-0311](../adr/0311-reaching-the-server.md).

## Tailscale or Headscale

Install Tailscale on the server's machine and on every device, signed in to the same tailnet (or to your Headscale
with `tailscale up --login-server https://headscale.example.org`). On the server's machine:

```sh
tailscale serve --bg http://127.0.0.1:8080
```

Tailscale prints the `https://<machine>.<tailnet>.ts.net` address and gets its certificate. Set it as `public_url`,
keep `trusted_proxies` on loopback, and add it to the apps beside the LAN address. Only devices in the tailnet reach
the server; `tailscale funnel` would open it to the internet through Tailscale's relays.

## WireGuard

WireGuard needs one UDP port open on one side: on the server's router (one port, not HTTPS), or on a small hub server
both sides connect to. `deploy/remote/wg0.conf` is the server's side; make keys with `wg genkey | tee private | wg
pubkey`, give each device its own `[Peer]`, and add `http://10.8.0.1:8080` to the apps (photolibd listening on the
WireGuard address, or on all).

## Cloudflare Tunnel

`cloudflared` connects out to Cloudflare, which serves your domain over HTTPS and sends the requests back through the
tunnel ([template](reverse-proxy.md#templates)). Cloudflare's free plan caps a request at 100 MB: backups never reach
it, as the apps send uploads in pieces of at most 8 MiB and photolibd takes at most 32 MiB per request; a lower cap
answered with 413 halves the pieces ([clients](clients.md#reverse-proxy-limits)). A Cloudflare Access policy in front
needs its token as a custom header in the apps.

## Test from outside

*Test from outside* asks [check-host.net](https://check-host.net/) to fetch `<address>/healthz` from its nodes around
the world, and passes when one gets photolibd's `200`. It sends nothing until you confirm the host it contacts
([privacy](privacy.md)). Without it, open *Check the connection* on a phone on mobile data: it runs the same steps as
the app does at home, from outside.
