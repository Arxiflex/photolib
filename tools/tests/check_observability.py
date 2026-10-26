#!/usr/bin/env python3
"""Check deploy/observability: the compose file (docker compose config, no daemon), Grafana's provisioning and
dashboard, and the alert rules with promtool from the Prometheus release that the compose file deploys; and the ADRs
behind the metrics."""
import json
import os
import re
import subprocess
import tempfile

import miniyaml
from checklib import ROOT, check, finish, read

DIR = os.path.join(ROOT, "deploy", "observability")
TOKEN_FILE = "/run/secrets/metrics_token"
ALERTS = {
    "PhotolibDatabaseUnreachable": "a database photolibd cannot read",
    "PhotolibBackupTooOld": "backup age",
    "PhotolibJobsDeadLettered": "job dead letters",
    "PhotolibDiskAlmostFull": "disk usage",
    "PhotolibSyncWatermarkLag": "watermark lag",
    "PhotolibIntegrityFindings": "scrub findings",
    "PhotolibDeviceBackupSilent": "devices whose backup went silent",
}


def yaml(name):
    return miniyaml.load(read(os.path.join(DIR, name)))


def promtool(*args):
    run = subprocess.run(["bash", os.path.join(ROOT, "tools", "promtool.sh"), *args], cwd=DIR, capture_output=True,
                         text=True, check=False)
    return run.returncode == 0, (run.stdout + run.stderr).strip()


def compose(env_lines):
    with tempfile.NamedTemporaryFile("w", suffix=".env") as env_file:
        env_file.write("".join(f"{line}\n" for line in env_lines))
        env_file.flush()
        run = subprocess.run(["docker", "compose", "--env-file", env_file.name, "-f", os.path.join(DIR, "compose.yaml"),
                              "config", "--format", "json"], capture_output=True, text=True, check=False)
    return run.returncode, run.stdout, run.stderr


def mounts(service):
    return {volume["target"]: volume for volume in service.get("volumes", [])}


def check_compose():
    status, _, err = compose([])
    check(status != 0 and "GRAFANA_ADMIN_PASSWORD" in err, "Grafana refuses to start without an admin password")
    status, out, err = compose(["GRAFANA_ADMIN_PASSWORD=from-env"])
    if not check(status == 0, f"the compose file is valid ({err.strip()})"):
        return {}
    config = json.loads(out)
    services = config["services"]
    check(set(services) == {"prometheus", "grafana"}, "the bundle runs Prometheus and Grafana")
    prometheus, grafana = services["prometheus"], services["grafana"]
    version = re.search(r"^VERSION=(\S+)$", read(os.path.join(ROOT, "tools", "promtool.sh")), re.MULTILINE).group(1)
    check(prometheus["image"] == f"prom/prometheus:v{version}",
          "Prometheus is the release whose promtool tests the rules")
    check(re.fullmatch(r"grafana/grafana:\d+\.\d+\.\d+", grafana["image"]), "the Grafana image is pinned")
    for name, service in services.items():
        # On the host network, Prometheus reaches photolibd's one listener on loopback, where it is by default.
        check(service.get("network_mode") == "host", f"{name} runs on the host network")
    check(config.get("secrets", {}).get("metrics_token", {}).get("environment") == "METRICS_TOKEN" and
          [secret.get("target", "/run/secrets/" + secret["source"]) for secret in prometheus.get("secrets", [])] ==
          [TOKEN_FILE], f"Prometheus reads photolibd's metrics token from METRICS_TOKEN at {TOKEN_FILE}")
    check("--web.listen-address=127.0.0.1:9090" in prometheus["command"], "Prometheus listens on loopback only")
    check(grafana["environment"].get("GF_SERVER_HTTP_ADDR") == "127.0.0.1", "Grafana listens on loopback only")
    env = grafana["environment"]
    check(env.get("GF_SECURITY_ADMIN_PASSWORD") == "from-env", "Grafana's password comes from the settings")
    quiet = ("ANALYTICS_REPORTING_ENABLED", "ANALYTICS_CHECK_FOR_UPDATES", "ANALYTICS_CHECK_FOR_PLUGIN_UPDATES",
             "NEWS_NEWS_FEED_ENABLED")
    check(all(env.get(f"GF_{key}") == "false" for key in quiet) and env.get("GF_SECURITY_DISABLE_GRAVATAR") == "true",
          "Grafana calls no one: no usage reports, update checks, news feed or Gravatar")
    want = {
        "prometheus": {"/etc/prometheus/prometheus.yml": "prometheus.yml", "/etc/prometheus/alerts.yml": "alerts.yml"},
        "grafana": {f"/etc/grafana/{d}": f"grafana/{d}" for d in
                    ("provisioning/datasources", "provisioning/dashboards", "dashboards")},
    }
    for name, files in want.items():
        found = mounts(services[name])
        for target, source in files.items():
            mount = found.get(target, {})
            check(mount.get("source") == os.path.join(DIR, source) and mount.get("read_only"),
                  f"{name} reads {source} at {target}")
    return services


def check_prometheus():
    configuration = read(os.path.join(ROOT, "docs", "admin", "configuration.md"))
    default = re.search(r"^\| `listen` \| `([^`]+)` \|", configuration, re.MULTILINE)
    jobs = yaml("prometheus.yml")["scrape_configs"]
    targets = [target for job in jobs for static in job["static_configs"] for target in static["targets"]]
    check(default and targets == [default.group(1)], "Prometheus scrapes photolibd's default listen address")
    check([job.get("authorization", {}).get("credentials_file") for job in jobs] == [TOKEN_FILE],
          "Prometheus sends the metrics token that photolibd requires")
    # The token file exists only in the container, so promtool checks the syntax and the rules on their own.
    ok, out = promtool("check", "config", "--syntax-only", "prometheus.yml")
    check(ok, "promtool accepts the Prometheus configuration", out)
    ok, out = promtool("check", "rules", "alerts.yml")
    check(ok, "promtool accepts the alert rules", out)
    ok, out = promtool("test", "rules", "alerts.test.yml")
    check(ok, "the alert rules pass their unit tests", out)
    rules = [rule for group in yaml("alerts.yml")["groups"] for rule in group["rules"]]
    names = {rule["alert"] for rule in rules}
    for name, what in ALERTS.items():
        check(name in names, f"an alert covers {what} ({name})")
    fired = {case["alertname"] for test in yaml("alerts.test.yml")["tests"] for case in test.get("alert_rule_test", [])
             if case.get("exp_alerts")}
    check(names <= fired, f"a unit test sees every alert fire (never: {sorted(names - fired)})")


def check_grafana():
    datasources = yaml("grafana/provisioning/datasources/prometheus.yaml")["datasources"]
    check([(source["type"], source["url"]) for source in datasources] == [("prometheus", "http://127.0.0.1:9090")],
          "Grafana's one data source is the bundle's Prometheus")
    providers = yaml("grafana/provisioning/dashboards/photolib.yaml")["providers"]
    check([provider["options"]["path"] for provider in providers] == ["/etc/grafana/dashboards"],
          "Grafana loads the dashboards from where the compose file mounts them")
    uid = datasources[0]["uid"]
    exprs = []
    for name in sorted(os.listdir(os.path.join(DIR, "grafana", "dashboards"))):
        dashboard = json.loads(read(os.path.join(DIR, "grafana", "dashboards", name)))
        panels = dashboard["panels"]
        check(dashboard.get("uid") and panels, f"{name} has a uid and panels")
        check(len({panel["id"] for panel in panels}) == len(panels), f"{name}: every panel has its own id")
        for panel in panels:
            targets = panel.get("targets", [])
            check(panel["datasource"]["uid"] == uid and targets and all(t["datasource"]["uid"] == uid for t in targets),
                  f"{name}: '{panel['title']}' queries the provisioned Prometheus")
            exprs += [target["expr"] for target in targets]
    # promtool parses recording rules, so every query is checked as PromQL.
    with tempfile.NamedTemporaryFile("w", suffix=".yml") as rules:
        rules.write("groups:\n  - name: dashboards\n    rules:\n")
        rules.write("".join(f"      - record: dashboard:query{i}\n        expr: {json.dumps(e)}\n"
                            for i, e in enumerate(exprs)))
        rules.flush()
        ok, out = promtool("check", "rules", rules.name)
    check(exprs and ok, "every dashboard query is valid PromQL", out)


adr = read(os.path.join(ROOT, "docs", "adr", "0046-observability.md"))
check(re.search(r"^\* \*\*Status\*\*: Accepted", adr, re.MULTILINE) and "**One port.**" in adr,
      "ADR-0046 is accepted with the owner's one port per server (photolib-design#342)")
capture = read(os.path.join(ROOT, "docs", "adr", "0053-change-capture.md"))
check(re.search(r"^\* \*\*Status\*\*: Accepted — 2026-10-16 [^*]*photolib-design#361", capture, re.MULTILINE),
      "ADR-0053 is accepted with the owner's answers (photolib-design#361)")
check("photolib-design#569" in capture and "photolib-design#569" in adr and "asked about again" not in capture,
      "ADR-0053's lag replacing ADR-0046's is confirmed by the owner (photolib-design#569)")
monitoring = read(os.path.join(ROOT, "docs", "admin", "monitoring.md"))
lag = re.search(r"^\| `photolib_sync_watermark_lag_seconds` .*", monitoring, re.MULTILINE)
check(lag and "have waited" in lag.group(0) and "have waited" in capture and "pg_read_all_stats" not in adr,
      "the exported watermark lag is how long changes have waited for the watermark, as the owner confirmed")
REFUSE = r"refuse `/metrics` and `/diagnostics`"
check(re.search(rf"^\* \*\*Status\*\*: Accepted[^*]*templates\s+{REFUSE}[^*]*photolib-design#375", adr, re.MULTILINE),
      "ADR-0046 records that the proxy templates refuse /metrics and /diagnostics (photolib-design#375)")
for doc in ("monitoring.md", "reverse-proxy.md"):
    check(re.search(rf"{REFUSE}[^.]*directly", " ".join(read(os.path.join(ROOT, "docs", "admin", doc)).split())),
          f"docs/admin/{doc}: the proxy templates refuse those, so Prometheus scrapes photolibd directly")
FILES = ("compose.yaml", "prometheus.yml", "alerts.yml", "alerts.test.yml", "grafana/dashboards/photolib.json",
         "grafana/provisioning/datasources/prometheus.yaml", "grafana/provisioning/dashboards/photolib.yaml")
present = [check(os.path.isfile(os.path.join(DIR, name)), f"deploy/observability/{name} exists") for name in FILES]
if all(present):
    check_compose()
    check_prometheus()
    check_grafana()
finish()
