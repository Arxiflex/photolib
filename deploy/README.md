# deploy/

Everything needed to run Photolib: the image, compose files, reverse-proxy templates, the Helm chart and NAS catalog
entries.

## Architecture

* Photolib sits behind a reverse proxy that terminates TLS: templates for Caddy (recommended), Traefik, nginx and
  Apache, tested against large uploads and streaming.
* Reference topologies: all-in-one (`photolibd` with all roles plus PostgreSQL in compose), all-in-one with a remote
  ML node, scaled (separate `api`, `worker` and `ml` nodes) and Kubernetes (Helm, migrations as a pre-upgrade job).
* NAS catalogs: Unraid, TrueNAS, Synology Container Manager, CasaOS and Umbrel.
* Secrets are never committed; examples use `.env.example` files.

## Contents

* `Dockerfile`: photolibd's image for amd64 and arm64 (Alpine with FFmpeg, libvips, ExifTool and `pg_dump`, non-root,
  pinned bases; [ADR-0096](../docs/adr/0096-deployment-images-compose-and-proxies.md)); `test_image.sh`, and
  `tools/image.sh` weekly where Docker runs.
* `compose/`: the all-in-one bundle (photolibd, PostgreSQL, Caddy) with `setup.sh`, the one-command quickstart
  ([installing](../docs/admin/install.md)); `test_compose.sh`.
* `proxy/`: Traefik, nginx, Apache, Nginx Proxy Manager and Cloudflare Tunnel templates beside `compose/Caddyfile`
  ([reverse proxies](../docs/admin/reverse-proxy.md)); the gate runs them in `server/crates/photolib-server/tests/proxies.rs`.
* `helm/photolib`: the Helm chart, a Deployment per process and `photolibd migrate` as a pre-upgrade Job
  ([on Kubernetes](../docs/admin/install.md#on-kubernetes)); `test_helm.sh` with the Helm `tools/helm.sh` pins.
* `nas/`: the NAS app stores' entries, for Synology, TrueNAS, CasaOS, Umbrel and Unraid
  ([on a NAS](../docs/admin/install.md#on-a-nas)); `test_nas.sh`.
* `remote/`: the WireGuard side of [remote access](../docs/admin/remote-access.md) without port-forwarding, beside the
  Tailscale command and the Cloudflare Tunnel template.
* `observability/`: Prometheus with example alerts (`alerts.test.yml` makes each fire) and Grafana with the Photolib
  dashboard, in compose next to `photolibd` ([monitoring](../docs/admin/monitoring.md)); `test_observability.sh`.

The development stack (PostgreSQL, Garage, Caddy) is not a deployment: it lives in `tools/dev/`.

## Design

* Reliability, migrations and operations (deployment and the reverse proxy)
* Architecture: deployment topologies
