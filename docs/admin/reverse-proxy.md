# Reverse proxies

photolibd serves plain HTTP on one port and expects a reverse proxy in front of it to terminate TLS.

## What photolibd believes

`X-Forwarded-For` and `X-Forwarded-Proto` (or `Forwarded`) count only from the addresses in `trusted_proxies`
(loopback by default). From any other address they are ignored, and a warning is logged at most every ten minutes.
Behind trusted proxies the client is the last address in `X-Forwarded-For` that is not itself a trusted proxy.

Sign-ins and the first administrator's setup (`AuthService` and `SetupService`) are refused with
`login.insecure_http` unless the client reached the proxy over HTTPS (the trusted proxy said `X-Forwarded-Proto:
https`) or comes from a loopback, private or link-local address. `allow_insecure_http: true` turns the refusal off
and logs a warning at startup. `photolibd doctor` warns about a proxy that sends no `X-Forwarded-Proto: https` or no
`X-Forwarded-For`, and about forwarded headers from an address outside `trusted_proxies`.

## Under a path

With `base_path: /photos`, every endpoint moves beneath `/photos`: `https://example.org/photos/` is the address the
apps connect to. The proxy passes paths unchanged; it does not strip the prefix.

## Templates

`deploy/` has a template for each proxy; `${PHOTOLIB_DOMAIN}`, `${PHOTOLIB_BASE_PATH}` (empty, or the `base_path`) and
`${PHOTOLIB_UPSTREAM}` (photolibd's `host:port`) come from the proxy's environment or are replaced by hand. Each
redirects plain HTTP to HTTPS, serves HTTP/2, forwards the client's address and `X-Forwarded-Proto`, lets uploads of
any size and long streams through, and never buffers server-sent events. They refuse `/metrics` and `/diagnostics`
with `403`: Prometheus and `photolibd doctor` reach photolibd directly, so a leaked metrics token is of no use from the
internet. The gate proves it for every template at `/` and under `/photos`
(`server/crates/photolib-server/tests/proxies.rs`), including first sign-in and an upload in pieces.

| Proxy | Template | Notes |
|---|---|---|
| Caddy (recommended) | `compose/Caddyfile` | Gets its certificate itself; the [compose bundle](install.md) runs it. |
| Traefik 3 | `proxy/traefik/traefik.yml`, `proxy/traefik/photolib.yml` | The static configuration lifts Traefik's 60 s request timeout. |
| nginx 1.18+ | `proxy/nginx.conf` | Certificate from certbot. |
| Apache httpd 2.4.47+ | `proxy/apache.conf` | `a2enmod ssl http2 proxy_http headers alias`; certificate from certbot. |
| Nginx Proxy Manager | `proxy/npm.conf` | Paste it into the proxy host's *Advanced* tab, with *Force SSL* and *HTTP/2 Support* on. |
| Cloudflare Tunnel | `proxy/cloudflared.yml` | Cloudflare's edge terminates TLS; its 100 MB request limit is above the 32 MiB that photolibd takes per upload request. Only the recipe is checked here, with `cloudflared tunnel ingress validate`. |

Set `trusted_proxies` to the address the proxy connects from: loopback when it runs on the same host, the network of
its containers otherwise (the compose bundle does so), cloudflared's address for a tunnel.
