# Administrator guide

The self-hosted server is being built, so this guide is short. It grows with the server: a change that alters
installation, configuration, backup or upgrades updates this guide in the same pull request.

* [Installing photolibd](install.md): the all-in-one compose bundle behind Caddy, upgrades without edits, NAS app
  stores, the Helm chart, and the deb with its own PostgreSQL for a machine without Docker.
* [Configuring photolibd](configuration.md): settings, roles, health endpoints, sync delays, the instance marker,
  network filesystems, the media sandbox and shutdown.
* [Upgrades and maintenance mode](upgrades.md): release channels, schema upgrades at startup, the dump before them,
  maintenance mode, `photolibd restore`, PostgreSQL major upgrades and `photolibd doctor schema`.
* [Backups and recovery](backups.md): daily backups on any store, restore drills, restores from the console,
  manifests and `photolibd recover --from-storage`, backing up the originals and the admin-succession kit.
* [Object storage](storage.md): Garage, Cloudflare R2, Backblaze B2 and AWS S3, what goes on a bucket, costs, why a
  bucket is not a backup and what the provider can read.
* [Runbooks](runbooks.md): upgrades and failed ones, restores, recovery from storage, moving the data or the storage,
  reprocessing, rotating secrets, lost recovery kits, a full disk and a failed node.
* [Accounts and the first administrator](users.md): the setup token, each account's library, roles, deletion,
  `photolibd admin password-setup`, API keys and the audit log.
* [The admin console and `photolibd doctor`](console.md): jobs and pauses, reprocessing, storage, policies and the
  diagnostics bundle.
* [Monitoring](monitoring.md): metrics behind a token, the Prometheus and Grafana bundle, example alerts and
  traces.
* [ML models](models.md): the licence-checked registry, `photolibd models fetch`, bundles for air-gapped servers and
  bring-your-own models.
* [Reaching photolibd from the apps](clients.md): private CAs, client certificates, self-signed servers, several
  addresses, discovery on the LAN, pairing links, the connection check, and what reverse-proxy limits and error pages
  do to the apps.
* [Reverse proxies](reverse-proxy.md): trusted proxies, sign-ins only over HTTPS, and serving under a path.
* [Remote access without port-forwarding](remote-access.md): Tailscale or Headscale, WireGuard and Cloudflare Tunnel,
  and a test of the public address from outside.
* [Integrations](integrations.md): the events API, signed webhooks and the random photo for Home Assistant, frames
  and kiosks.
* [Outbound connections](privacy.md): the privacy manifest, every connection to anything but your own servers, with
  its kill switch and a self-hosted alternative.

For the planned behaviour that is not built yet, see reliability, migrations and operations and
storage and libraries.
