# ADR-0046 — Observability: metrics behind a token on the one port, a Prometheus and Grafana bundle, opt-in traces

* **Status**: Accepted — 2026-10-16. The owner answered the provisional choices of the observability baseline (M0-20)
  in photolib-design#342:
  a server opens one port only, so `/metrics` moved from a loopback admin listener to `listen`, behind a token. The
  owner deferred ("I do not know") the opt-in traces, the bundle on the host network and the backup age, which stand.
  On 2026-10-17 the owner kept the token for `/metrics` and `/diagnostics` and added that the reverse-proxy templates
  refuse `/metrics` and `/diagnostics`, so Prometheus scrapes photolibd directly on the internal network
  (photolib-design#375).
* **Requirements**: NFR-OBS-1. **Design**: 15 §10, 05 §2.

## Context

Design 15 §10 asks for Prometheus metrics, optional OpenTelemetry traces and default alerts; the work item adds
dashboards in the repository and a separate listener on localhost for `/metrics` and admin-only endpoints, so that
publishing the API never publishes them (lessons LL-81). The owner wants a server to open one port only. The work item
leaves open what the metrics measure before uploads, sync and scheduled backups exist, how the dashboards run before
`photolibd` has a container image (M2-30), and where traces may go.

## Decision

* **One port.** `photolibd` listens on `listen` only ([ADR-0021](0021-photolibd-startup-contract.md)), which serves
  health, the API, uploads and `/metrics`; admin-only endpoints will be API procedures under the authorization policy
  ([ADR-0038](0038-authorization-policy.md)). `/metrics` answers only `Authorization: Bearer` with `metrics.token` (at
  least 32 characters, compared in constant time), else `401`; without the setting there is no `/metrics`. Scrapes log
  at debug, like health probes. The reverse-proxy templates of `deploy/` answer `/metrics` and `/diagnostics` with
  `403`: Prometheus and `photolibd doctor` reach `listen` directly.
* **Metrics** are OpenMetrics text from `prometheus-client`. Requests are timed by route pattern or Connect
  procedure, and every other path is `unmatched`, so probing adds no series. Each scrape reads, within 2 s or not at
  all, the queued, running and dead jobs by type (with zeros, so that dead-letter growth starts at 0, and through a
  partial index, migration 0004). It also reads the filesystems of the state directories and the time of the newest
  `*.dump` in `<data_dir>/backups` (0 without one), where scheduled dumps will join the pre-upgrade ones. A process
  running the scheduler also exports the sync watermark lag it samples ([ADR-0053](0053-change-capture.md), as the
  owner confirmed in photolib-design#361 and, replacing the age of the oldest open transaction, photolib-design#569).
  Upload metrics come with the upload API.
* **Bundle.** `deploy/observability` runs Prometheus 3.15.0 and Grafana 13.2.4 in compose on the host network, so
  that Prometheus scrapes `listen` on loopback with the token from `.env` (a compose secret), with both listening on
  loopback, Grafana's password from `.env` and its calls home switched off. The gate runs that release's promtool
  (`tools/promtool.sh`) on the configuration, the rules, a unit test that makes each alert fire and the PromQL of every
  dashboard query; a Rust test fails when they query a metric that `photolibd` does not export.
* **Alerts**, as examples: `photolibd` down, newest dump older than 48 h or none, more dead jobs of a type than an
  hour ago, disk over 90%, watermark lag over 5 min. Scrub findings, offline libraries and model coverage come with
  those features.
* **Traces** go only to `traces.otlp_endpoint`, an OTLP/HTTP collector the administrator runs, without TLS for now;
  unset by default, and then no exporter exists.

## Consequences

* ✅ One port to publish, proxy and firewall; a leaked token is of no use through the templates' proxies, and a proxy
  of one's own that forwards everything shows the metrics only to the token.
* ✅ A dashboard or alert that queries a missing metric, invalid PromQL or an alert that never fires fails the gate.
* ⚠️ Without `metrics.token` there are no metrics; Prometheus needs the token even on the same host.
* ⚠️ Host networking is Linux only (Docker Desktop must enable it). With an image (M2-30) the bundle joins
  `photolibd`'s compose network and scrapes `listen` there.
* ⚠️ Until scheduled backups exist, the backup alert fires 48 h after the last upgrade.
* ⚠️ The gate's first run downloads the 110 MB Prometheus release for promtool (then cached).

## Options considered

* **A separate admin listener on loopback** (`admin_listen`, `127.0.0.1:8081`, the provisional choice): the owner wants
  one port per server.
* **Metrics on `listen` without a token:** publishing the API would publish them (LL-81).
* **Metrics only for loopback clients:** behind a reverse proxy on the same host every client is loopback.
* **`metrics` with `metrics-exporter-prometheus`:** a global recorder; values read at scrape time fit a registry per
  scrape better.
* **Job counters kept by the workers:** per process, reset by restarts and blind to the queue; the database is the
  truth.
* **Counting every job at each scrape:** reads millions of finished jobs every 30 s on a large library.
* **Dead-letter growth as `X > X offset 1h`:** fires for every existing dead job while Prometheus has less than an
  hour of data, after each restart.
* **A bridge network with published ports:** Prometheus cannot reach a loopback `listen` without exposing it.
* **OTLP over gRPC or with reqwest:** more dependencies for the same spans; HTTP over hyper reuses the server's.
