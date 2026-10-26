//! The reverse-proxy templates of `deploy/` (design 15 §9): each proxy runs its template, at the root and under
//! `/photos`, in front of a stand-in upstream and of photolibd. Over HTTP/2 it must redirect plain HTTP, forward the
//! client and HTTPS, pass paths unchanged, stream responses and server-sent events and refuse `/metrics` and
//! `/diagnostics`, and the e2e suite must pass through it: first sign-in, a resumable upload in 32 MiB pieces and the
//! doctor's proxy check. The proxies come from `tools/proxies.sh`; Nginx Proxy Manager is nginx with its proxy host
//! around `npm.conf`.

use std::{
    collections::HashMap,
    io::{BufRead, BufReader, Read},
    net::{SocketAddr, TcpListener},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use axum::{
    Json,
    body::Body,
    extract::Request,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use futures::StreamExt;
use nix::{sys::signal::kill, unistd::Pid};
use photolib_spawn::{
    Group, Port, Running, Signal, command, free_port, listen_beside, members, on_fresh_ports, output, port_taken, tool,
};
use serde_json::{Value, json};
use uuid::Uuid;

const DOMAIN: &str = "photos.example.com";
const PROXIES: [&str; 5] = ["caddy", "traefik", "nginx", "apache", "npm"];
const BASES: [&str; 2] = ["", "/photos"];
/// How long the stand-in waits between the two parts of a paced response.
const PAUSE: Duration = Duration::from_millis(1500);
const STREAM: usize = 32 << 20;
const TOKEN: &str = "test-token-test-token-test-token";
/// Set in the run of `proxies_until_killed` that `no_proxy_outlives_its_test_even_a_killed_one` starts.
const CHILD: &str = "PHOTOLIB_PROXIES_CHILD";
/// The most a tool may take, in `photolib_spawn::Running` time: curl's own `--max-time` would count time its run spent
/// stopped.
const TOOL: Duration = Duration::from_secs(120);

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

/// `tools/proxies.sh`: each proxy's binary and, for Apache, its module directory.
fn binaries() -> HashMap<String, Vec<String>> {
    // It fetches what is missing.
    let output = output(
        tool("bash").arg(repo().join("tools/proxies.sh")),
        Duration::from_secs(600),
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(output.status.success(), "the suite needs its proxies: {stderr}");
    let stdout = String::from_utf8(output.stdout).unwrap();
    let lines = stdout.lines().map(|line| line.split(' ').map(str::to_string));
    lines
        .map(|mut words| (words.next().unwrap(), words.collect()))
        .collect()
}

/// `deploy/<path>` with each `(from, to)` made; every `from` must be there.
fn template(path: &str, edits: &[(&str, &str)]) -> String {
    let mut text = std::fs::read_to_string(repo().join("deploy").join(path)).unwrap();
    for (from, to) in edits {
        assert!(text.contains(from), "{path} no longer has `{from}`");
        text = text.replace(from, to);
    }
    text
}

/// What the nginx image's envsubst does to a template.
fn envsubst(text: &str, env: &[(&str, &str)]) -> String {
    let fill = |text: String, (name, value): &(&str, &str)| text.replace(&format!("${{{name}}}"), value);
    env.iter().fold(text.to_string(), fill)
}

/// The proxy host Nginx Proxy Manager 2 generates for an upstream with "Force SSL" and "HTTP/2 Support" on, around
/// its "Advanced" tab.
fn npm_host(dir: &str, http: u16, https: u16, upstream: &str) -> String {
    let (server, port) = upstream.rsplit_once(':').unwrap();
    let advanced = template("proxy/npm.conf", &[]);
    format!(
        "server {{
  set $forward_scheme http;
  set $server \"{server}\";
  set $port {port};
  listen 127.0.0.1:{http};
  listen 127.0.0.1:{https} ssl http2;
  server_name {DOMAIN};
  ssl_certificate {dir}/fullchain.pem;
  ssl_certificate_key {dir}/privkey.pem;
  if ($scheme = \"http\") {{
    return 301 https://$host$request_uri;
  }}
{advanced}
  location / {{
    add_header X-Served-By $host;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Scheme $scheme;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_pass $forward_scheme://$server:$port$request_uri;
  }}
}}
"
    )
}

/// A proxy running its template for `photos.example.com` with a certificate of its own, on two loopback ports.
struct Proxy {
    child: Group,
    name: &'static str,
    http: u16,
    https: u16,
    base: &'static str,
    dir: tempfile::TempDir,
}

/// A response: HTTP version, status, headers (lowercase names) and body.
struct Reply {
    version: String,
    status: u16,
    headers: HashMap<String, String>,
    body: Vec<u8>,
}

impl Reply {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body)
            .unwrap_or_else(|_| panic!("not JSON: {}", String::from_utf8_lossy(&self.body)))
    }
}

impl Proxy {
    /// On two ports from `port`, fresh ones while another process takes one before the proxy binds it.
    fn start(
        name: &'static str,
        base: &'static str,
        upstream: SocketAddr,
        bins: &HashMap<String, Vec<String>>,
        mut port: impl FnMut() -> Port,
    ) -> Self {
        on_fresh_ports(|| Self::try_start(name, base, upstream, bins, &port(), &port()))
    }

    fn try_start(
        name: &'static str,
        base: &'static str,
        upstream: SocketAddr,
        bins: &HashMap<String, Vec<String>>,
        http: &Port,
        https: &Port,
    ) -> Result<Self, String> {
        let (http, https) = (http.number, https.number);
        let dir = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
        let d = dir.path().to_str().unwrap().to_string();
        let upstream = upstream.to_string();
        let env = [
            ("PHOTOLIB_DOMAIN", DOMAIN),
            ("PHOTOLIB_BASE_PATH", base),
            ("PHOTOLIB_UPSTREAM", &upstream),
        ];
        let subject = format!("/CN={DOMAIN}");
        let san = format!("subjectAltName=DNS:{DOMAIN}");
        let made = output(
            tool("openssl")
                .args([
                    "req",
                    "-x509",
                    "-newkey",
                    "ec",
                    "-pkeyopt",
                    "ec_paramgen_curve:prime256v1",
                ])
                .args(["-nodes", "-days", "1", "-subj", &subject, "-addext", &san])
                .args(["-keyout", "privkey.pem", "-out", "fullchain.pem"])
                .current_dir(&d),
            TOOL,
        );
        assert!(made.status.success(), "openssl made no certificate");
        let write = |file: &str, text: String| {
            let path = format!("{d}/{file}");
            std::fs::write(&path, text).unwrap();
            path
        };
        let certbot = "/etc/letsencrypt/live/${PHOTOLIB_DOMAIN}/";
        let certs = format!("{d}/");
        let (http_port, https_port) = (http.to_string(), https.to_string());
        // nginx's workers finish their requests on SIGQUIT; SIGTERM would drop them.
        let stop = match name {
            "nginx" | "npm" => Signal::SIGQUIT,
            _ => Signal::SIGTERM,
        };
        let mut command = match name {
            "caddy" => {
                let global = format!(
                    "{{\n\thttp_port {http}\n\thttps_port {https}\n\tdefault_bind 127.0.0.1\n\tlocal_certs\n\
                     \tskip_install_trust\n\tadmin off\n\tstorage file_system {d}/caddy\n}}\n"
                );
                let file = write("Caddyfile", global + &template("compose/Caddyfile", &[]));
                let mut command = command(&bins["caddy"][0], stop);
                command
                    .args(["run", "--adapter", "caddyfile", "--config", &file])
                    .env("HOME", &d);
                command
            }
            "traefik" => {
                std::fs::create_dir(format!("{d}/dynamic")).unwrap();
                write(
                    "dynamic/tls.yml",
                    format!(
                        "tls:\n  stores:\n    default:\n      defaultCertificate:\n        certFile: {d}/fullchain.pem\n        keyFile: {d}/privkey.pem\n"
                    ),
                );
                let route = template(
                    "proxy/traefik/photolib.yml",
                    &[("certResolver: letsencrypt", "options: default")],
                );
                write("dynamic/photolib.yml", route);
                let config = template(
                    "proxy/traefik/traefik.yml",
                    &[
                        ("\":80\"", &format!("\"127.0.0.1:{http_port}\"")),
                        ("\":443\"", &format!("\"127.0.0.1:{https_port}\"")),
                        ("/etc/traefik/dynamic", &format!("{d}/dynamic")),
                    ],
                );
                let (config, _acme) = config.split_once("certificatesResolvers:").unwrap();
                let file = write("traefik.yml", config.into());
                let mut command = command(&bins["traefik"][0], stop);
                command.arg(format!("--configFile={file}"));
                command
            }
            "nginx" | "npm" => {
                let site = match name {
                    "nginx" => envsubst(
                        &template(
                            "proxy/nginx.conf",
                            &[
                                ("listen 80;", &format!("listen 127.0.0.1:{http};")),
                                ("listen 443 ssl", &format!("listen 127.0.0.1:{https} ssl")),
                                (certbot, &certs),
                            ],
                        ),
                        &env,
                    ),
                    _ => npm_host(&d, http, https, &upstream),
                };
                write("site.conf", site);
                let temp: String = ["client_body", "proxy", "fastcgi", "uwsgi", "scgi"]
                    .map(|kind| format!("  {kind}_temp_path {d}/{kind};\n"))
                    .concat();
                let file = write(
                    "nginx.conf",
                    format!(
                        "daemon off;\npid {d}/nginx.pid;\nevents {{}}\nhttp {{\n  access_log off;\n{temp}  include {d}/site.conf;\n}}\n"
                    ),
                );
                let mut command = command(&bins["nginx"][0], stop);
                command.args(["-e", "stderr", "-p", &d, "-c", &file]);
                command
            }
            "apache" => {
                let (httpd, modules) = (&bins["apache"][0], &bins["apache"][1]);
                let compiled = output(tool(httpd).arg("-l"), TOOL).stdout;
                let compiled = String::from_utf8(compiled).unwrap();
                let mut config = format!(
                    "ServerRoot {d}\nServerName localhost\nListen 127.0.0.1:{http}\nListen 127.0.0.1:{https}\n\
                     PidFile {d}/httpd.pid\nDefaultRuntimeDir {d}\nErrorLog /dev/stderr\nStartServers 1\n\
                     ServerLimit 1\nThreadLimit 16\nThreadsPerChild 16\nMaxRequestWorkers 16\n"
                );
                for module in [
                    "mpm_event",
                    "unixd",
                    "authz_core",
                    "alias",
                    "headers",
                    "ssl",
                    "http2",
                    "proxy",
                    "proxy_http",
                ] {
                    if !compiled.contains(&format!("mod_{module}.c")) {
                        config += &format!("LoadModule {module}_module {modules}/mod_{module}.so\n");
                    }
                }
                let site = template(
                    "proxy/apache.conf",
                    &[
                        ("*:80>", &format!("*:{http}>")),
                        ("*:443>", &format!("*:{https}>")),
                        (certbot, &certs),
                    ],
                );
                config += &format!("Include {}\n", write("site.conf", site));
                let file = write("httpd.conf", config);
                let mut command = command(httpd, stop);
                command.args(["-f", &file, "-DFOREGROUND"]);
                command
            }
            _ => unreachable!(),
        };
        let log = std::fs::File::create(format!("{d}/log")).unwrap();
        command.envs(env).stdout(log.try_clone().unwrap()).stderr(log);
        let child = Group::start(command, stop);
        let mut proxy = Self {
            child,
            name,
            http,
            https,
            base,
            dir,
        };
        let started = Running::start();
        // Up once it alone listens on both ports and the TLS handshake succeeds, which Caddy needs its certificate for.
        let up = |proxy: &Self| {
            let probe = || output(&mut proxy.command(&["-o", "/dev/null", &proxy.url("/")]), TOOL);
            Ok::<_, String>(proxy.child.listens(http)? && proxy.child.listens(https)? && probe().status.success())
        };
        while !up(&proxy)? {
            let exited = proxy.child.try_wait().unwrap();
            if exited.is_some() || port_taken(&proxy.log()) || started.elapsed() > Duration::from_secs(20) {
                return Err(format!("{name} did not start ({exited:?}): {}", proxy.log()));
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        Ok(proxy)
    }

    fn at(&self) -> String {
        format!("{} at {}/", self.name, self.base)
    }

    fn log(&self) -> String {
        std::fs::read_to_string(self.dir.path().join("log")).unwrap_or_default()
    }

    fn url(&self, path: &str) -> String {
        format!("https://{DOMAIN}:{}{}{path}", self.https, self.base)
    }

    /// curl to the proxy over HTTP/2 when it can, trusting its certificate.
    fn command(&self, args: &[&str]) -> Command {
        let mut command = curl();
        for port in [self.http, self.https] {
            command.args(["--resolve", &format!("{DOMAIN}:{port}:127.0.0.1")]);
        }
        command.args(args);
        command
    }

    fn curl(&self, args: &[&str]) -> Reply {
        let headers = self.dir.path().join("headers");
        let output = output(
            self.command(args)
                .args(["-D", headers.to_str().unwrap(), "-w", "\n%{http_version} %{http_code}"]),
            TOOL,
        );
        assert!(
            output.status.success(),
            "{}: curl {args:?}: {}",
            self.at(),
            String::from_utf8_lossy(&output.stderr)
        );
        let split = output.stdout.iter().rposition(|&b| b == b'\n').unwrap();
        let meta = String::from_utf8(output.stdout[split + 1..].to_vec()).unwrap();
        let (version, status) = meta.split_once(' ').unwrap();
        let headers = std::fs::read_to_string(headers).unwrap();
        let headers = headers.lines().filter_map(|line| line.split_once(": "));
        Reply {
            version: version.into(),
            status: status.parse().unwrap(),
            headers: headers
                .map(|(name, value)| (name.to_lowercase(), value.into()))
                .collect(),
            body: output.stdout[..split].to_vec(),
        }
    }

    /// A GET's body and how long after its first bytes its last ones came.
    fn paced(&self, path: &str) -> (Vec<u8>, Duration) {
        streamed(
            start(self.command(&["-N", &self.url(path)])),
            &format!("{}: {path}", self.at()),
        )
    }

    /// A Connect call in JSON through the proxy that must succeed.
    fn rpc(&self, method: &str, bearer: Option<&str>, body: Value) -> Value {
        let auth = bearer.map(|token| format!("authorization: Bearer {token}"));
        let url = self.url(&format!("/photolib.api.v1.{method}"));
        let mut args = vec!["-H", "content-type: application/json", "--data-binary"];
        let body = body.to_string();
        args.extend([body.as_str(), url.as_str()]);
        if let Some(auth) = &auth {
            args.extend(["-H", auth]);
        }
        let reply = self.curl(&args);
        assert_eq!(
            (reply.version.as_str(), reply.status),
            ("2", 200),
            "{}: {method}: {}",
            self.at(),
            reply.json()
        );
        reply.json()
    }
}

fn pattern(range: std::ops::Range<usize>) -> Vec<u8> {
    range.map(|i| (i % 251) as u8).collect()
}

/// curl with the flags the suite runs it with: silent but for errors, over HTTP/2 when it can, trusting any certificate.
fn curl() -> Command {
    let mut curl = tool("curl");
    curl.args(["-sSk", "--http2"]);
    curl
}

/// `curl` started with its output piped, killed after `TOOL`.
fn start(mut curl: Command) -> Group {
    curl.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = Group::start(curl, Signal::SIGKILL);
    child.deadline(TOOL);
    child
}

/// What a `start`ed curl prints and how long after its first bytes its last ones came; `what` names it if it fails.
fn streamed(mut child: Group, what: &str) -> (Vec<u8>, Duration) {
    let started = Instant::now();
    let (mut stdout, mut stderr) = (child.stdout.take().unwrap(), child.stderr.take().unwrap());
    let (mut body, mut first, mut last, mut buffer) = (vec![], None, Instant::now(), vec![0; 1 << 16]);
    while let n @ 1.. = stdout.read(&mut buffer).unwrap() {
        body.extend_from_slice(&buffer[..n]);
        last = Instant::now();
        first.get_or_insert(last);
    }
    // curl's few words of failure fit the pipe.
    let mut said = String::new();
    stderr.read_to_string(&mut said).unwrap();
    let status = child.wait().unwrap();
    assert!(
        status.success(),
        "{what}: curl {status}: {} ({} bytes in {:?})",
        said.trim(),
        body.len(),
        started.elapsed()
    );
    (body, last - first.unwrap_or(last))
}

/// A paced GET that fails says how, as curl does: under load one failed with nothing but its assertion.
#[test]
#[should_panic(expected = "curl exit status: 7: curl: (7) Failed to connect")]
fn a_streamed_get_that_fails_says_how() {
    let mut curl = curl();
    let closed = free_port();
    curl.arg(format!("http://127.0.0.1:{}/stream", closed.number));
    streamed(start(curl), "a closed port");
}

/// The merge train stops every process of other runs (SIGSTOP) for up to 25 minutes while it measures time: a paced
/// GET whose curl was stopped mid-stream for longer than a minute gets the whole stream once continued.
#[tokio::test(flavor = "multi_thread")]
async fn a_streamed_get_goes_on_after_its_curl_was_stopped() {
    let upstream = stub(Arc::default()).await;
    let mut curl = curl();
    curl.args(["-N", &format!("http://{upstream}/stream")]);
    let child = start(curl);
    let pid = Pid::from_raw(child.id().cast_signed());
    std::thread::spawn(move || {
        std::thread::sleep(PAUSE / 3);
        kill(pid, Signal::SIGSTOP).unwrap();
        std::thread::sleep(Duration::from_secs(62));
        kill(pid, Signal::SIGCONT).unwrap();
    });
    let (body, _) = streamed(child, "a stopped curl");
    assert!(body == pattern(0..STREAM), "{} bytes of the stream", body.len());
}

/// A body whose second part follows `PAUSE` after the first.
fn paced(kind: &'static str, first: Vec<u8>, second: Vec<u8>) -> Response {
    let parts = futures::stream::iter([first, second])
        .enumerate()
        .then(|(i, part)| async move {
            if i == 1 {
                tokio::time::sleep(PAUSE).await;
            }
            Ok::<_, std::io::Error>(part)
        });
    ([("content-type", kind)], Body::from_stream(parts)).into_response()
}

/// The stand-in upstream: what the proxy sent (`echo`), streams with `Range` (`stream`) and server-sent events
/// (`events`), at any path ending so. It records every path it serves in `seen`.
async fn stub(seen: Arc<Mutex<Vec<String>>>) -> SocketAddr {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let app = axum::Router::new().fallback(move |request: Request| {
        seen.lock().unwrap().push(request.uri().path().into());
        answer(request)
    });
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    addr
}

async fn answer(request: Request) -> Response {
    let header = |name| request.headers().get(name).map(|v| v.to_str().unwrap().to_string());
    let path = request.uri().path().to_string();
    match path.rsplit('/').next().unwrap() {
        "echo" => Json(json!({
            "path": path,
            "host": header("host"),
            "for": header("x-forwarded-for"),
            "proto": header("x-forwarded-proto"),
        }))
        .into_response(),
        "events" => paced("text/event-stream", b"data: one\n\n".into(), b"data: two\n\n".into()),
        "stream" => match header("range").and_then(|r| r.strip_prefix("bytes=").map(str::to_string)) {
            Some(range) => {
                let (from, to) = range.split_once('-').unwrap();
                let (from, to): (usize, usize) = (from.parse().unwrap(), to.parse().unwrap());
                let content_range = format!("bytes {from}-{to}/{STREAM}");
                let headers = [("content-range", content_range)];
                (StatusCode::PARTIAL_CONTENT, headers, pattern(from..to + 1)).into_response()
            }
            None => paced(
                "application/octet-stream",
                pattern(0..16 << 10),
                pattern(16 << 10..STREAM),
            ),
        },
        _ => StatusCode::NOT_FOUND.into_response(),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn every_template_carries_streams_and_events_over_http2() {
    let seen = Arc::new(Mutex::new(vec![]));
    let upstream = stub(seen.clone()).await;
    let bins = binaries();
    for name in PROXIES {
        for base in BASES {
            let proxy = Proxy::start(name, base, upstream, &bins, free_port);
            let at = proxy.at();
            // On loopback only: elsewhere on the machine its ports are free.
            for port in [proxy.http, proxy.https] {
                assert!(
                    TcpListener::bind(("127.0.0.2", port)).is_ok(),
                    "{at} listens beyond 127.0.0.1:{port}"
                );
            }
            let echo = proxy.curl(&[&proxy.url("/echo")]);
            assert_eq!(
                (echo.version.as_str(), echo.status),
                ("2", 200),
                "{at}: {}",
                proxy.log()
            );
            let echo = echo.json();
            assert_eq!(echo["path"], format!("{base}/echo"), "{at} passes paths unchanged");
            assert!(echo["host"].as_str().unwrap().starts_with(DOMAIN), "{at}: {echo}");
            assert_eq!(echo["proto"], "https", "{at}: {echo}");
            assert!(echo["for"].as_str().unwrap().ends_with("127.0.0.1"), "{at}: {echo}");

            let plain = proxy.curl(&[&format!("http://{DOMAIN}:{}{base}/echo", proxy.http)]);
            assert!(
                [301, 308].contains(&plain.status),
                "{at} redirects plain HTTP: {}",
                plain.status
            );
            assert!(
                plain.headers["location"].starts_with(&format!("https://{DOMAIN}")),
                "{at}"
            );

            let range = proxy.curl(&["-H", "range: bytes=1000-1999", &proxy.url("/stream")]);
            assert_eq!(
                (range.status, range.body),
                (206, pattern(1000..2000)),
                "{at} passes ranges"
            );

            let (body, spread) = proxy.paced("/stream");
            assert!(body == pattern(0..STREAM), "{at}: {} bytes of the stream", body.len());
            assert!(
                spread >= PAUSE / 2,
                "{at} held the stream back: its parts came {spread:?} apart"
            );
            let (events, spread) = proxy.paced("/events");
            assert_eq!(events, b"data: one\n\ndata: two\n\n", "{at}");
            assert!(
                spread >= PAUSE / 2,
                "{at} held an event back: they came {spread:?} apart"
            );

            // Prometheus and the doctor reach photolibd directly; from outside a leaked token is of no use (ADR-0046).
            for path in ["/metrics", "/diagnostics", "/metrics?format=text"] {
                assert_eq!(proxy.curl(&[&proxy.url(path)]).status, 403, "{at} refuses {path}");
            }
            // An escaped name may pass, but never as a path that photolibd serves.
            for path in ["/%6detrics", "/diagnostic%73"] {
                proxy.curl(&[&proxy.url(path)]);
            }
            let private = [format!("{base}/metrics"), format!("{base}/diagnostics")];
            assert!(
                !seen.lock().unwrap().iter().any(|path| private.contains(path)),
                "{at} forwards {private:?}"
            );

            // Nginx Proxy Manager's proxy host hands the whole host to photolibd, which serves only beneath its base.
            if !base.is_empty() && name != "npm" {
                proxy.curl(&[&format!("https://{DOMAIN}:{}/elsewhere/echo", proxy.https)]);
                assert!(
                    !seen.lock().unwrap().iter().any(|path| path.starts_with("/elsewhere")),
                    "{at}"
                );
            }
            stop(proxy);
        }
    }
}

/// A port another process listens on before the proxy binds it costs the proxy a fresh pair, also when it lets the
/// proxy listen beside it, as another Caddy does (photolib-design#501).
#[test]
fn a_proxy_whose_port_was_taken_starts_on_others() {
    let (bins, upstream) = (binaries(), SocketAddr::from(([127, 0, 0, 1], free_port().number)));
    for name in PROXIES {
        let mut taken = None;
        let proxy = Proxy::start(name, "", upstream, &bins, || {
            let port = free_port();
            taken.get_or_insert_with(|| listen_beside(port.number));
            port
        });
        let taken = taken.unwrap().local_addr().unwrap().port();
        assert!(
            ![proxy.http, proxy.https].contains(&taken),
            "{name} on {taken}, which the test holds"
        );
        stop(proxy);
    }
}

/// Stops `proxy`, which must leave no process of its group behind.
fn stop(proxy: Proxy) {
    let (at, group) = (proxy.at(), proxy.child.id());
    drop(proxy);
    assert_eq!(members(group), Vec::<u32>::new(), "{at} left processes behind");
}

/// Run only by `no_proxy_outlives_its_test_even_a_killed_one`, as a child: starts every proxy, prints their process
/// groups and waits to be killed.
#[test]
fn proxies_until_killed() {
    if std::env::var_os(CHILD).is_none() {
        return;
    }
    let (bins, upstream) = (binaries(), SocketAddr::from(([127, 0, 0, 1], free_port().number)));
    let proxies = PROXIES.map(|name| Proxy::start(name, "", upstream, &bins, free_port));
    let groups = proxies.each_ref().map(|proxy| proxy.child.id().to_string());
    println!("groups {}", groups.join(" "));
    std::thread::sleep(Duration::from_secs(600));
}

/// When a test that runs every proxy is killed with SIGKILL, no process of their groups is left.
#[test]
fn no_proxy_outlives_its_test_even_a_killed_one() {
    let mut test = tool(std::env::current_exe().unwrap());
    test.args(["--exact", "proxies_until_killed", "--nocapture", "--test-threads=1"])
        .env(CHILD, "1")
        .stdout(Stdio::piped());
    let mut test = Group::start(test, Signal::SIGKILL);
    test.deadline(Duration::from_secs(120));
    let lines = BufReader::new(test.stdout.take().unwrap()).lines();
    let groups: Vec<u32> = (lines.map_while(Result::ok))
        .find_map(|line| {
            Some(
                line.split_once("groups ")?
                    .1
                    .split(' ')
                    .map(|g| g.parse().unwrap())
                    .collect(),
            )
        })
        .expect("the child test started the proxies");
    let left = || groups.iter().flat_map(|&group| members(group)).collect::<Vec<_>>();
    assert!(
        groups.iter().all(|&group| !members(group).is_empty()),
        "every proxy runs in a process group of its own: {groups:?}"
    );
    test.signal(Signal::SIGKILL);
    let killed = Running::start();
    while !left().is_empty() && killed.elapsed() < Duration::from_secs(15) {
        std::thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(left(), Vec::<u32>::new(), "the proxies of a killed test outlived it");
}

/// photolibd on a fresh instance beneath `base`, with its address, setup token and configuration file.
struct Photolibd {
    _child: Group,
    addr: SocketAddr,
    setup_token: String,
    config: PathBuf,
}

impl Photolibd {
    fn start(dir: &Path, url: &str, base: &str) -> Self {
        let data = dir.join("data");
        std::fs::create_dir(&data).unwrap();
        let config = dir.join("photolib.yaml");
        let base = if base.is_empty() { "/" } else { base };
        let yaml = format!(
            "config_version: 1\nroles: [api]\nlisten: 127.0.0.1:0\nbase_path: {base}\nmetrics: {{token: {TOKEN}}}\n\
             data_dir: {}\ndatabase:\n  url: \"{url}\"\n",
            data.display()
        );
        std::fs::write(&config, &yaml).unwrap();
        let mut photolibd = command(env!("CARGO_BIN_EXE_photolibd"), Signal::SIGTERM);
        photolibd
            .arg("--config")
            .arg(&config)
            .env_clear()
            .stderr(Stdio::piped());
        let mut child = Group::start(photolibd, Signal::SIGTERM);
        let (mut setup_token, mut log) = (String::new(), String::new());
        let mut lines = BufReader::new(child.stderr.take().unwrap()).lines();
        for line in lines.by_ref() {
            let line = line.unwrap();
            log += &line;
            let line: Value = serde_json::from_str(&line).unwrap_or_default();
            if let Some(token) = line["fields"]["setup_token"].as_str() {
                setup_token = token.into();
            }
            if line["fields"]["message"] == "listening" {
                let addr: SocketAddr = line["fields"]["addr"].as_str().unwrap().parse().unwrap();
                // For `photolibd doctor`, which asks the running photolibd on `listen`.
                std::fs::write(&config, yaml.replace("127.0.0.1:0", &addr.to_string())).unwrap();
                // Drained, so that photolibd never blocks on a full pipe.
                std::thread::spawn(move || lines.for_each(drop));
                return Self {
                    _child: child,
                    addr,
                    setup_token,
                    config,
                };
            }
        }
        let status = child.wait().unwrap();
        panic!("photolibd exited ({status}) before it listened: {log}");
    }
}

/// The first administrator, `root` with the password `pw`, as the app creates it through `proxy`.
fn create_admin(proxy: &Proxy, setup_token: &str) {
    use base64::{Engine, engine::general_purpose::STANDARD};
    use opaque_ke::{ClientRegistration, RegistrationResponse};
    use photolib_server::auth::Suite;

    let admin = json!({ "setupToken": setup_token, "user": { "handle": "root", "displayName": "Root" } });
    let created = proxy.rpc("SetupService/CreateFirstAdmin", None, admin);
    let setup = created["passwordSetup"]["token"].as_str().unwrap();
    let start = ClientRegistration::<Suite>::start(&mut rand_core::OsRng, b"pw").unwrap();
    let request = json!({
        "registrationRequest": STANDARD.encode(start.message.serialize()),
        "passwordSetupToken": setup,
    });
    let started = proxy.rpc("AuthService/StartPasswordSetup", None, request);
    let response = STANDARD
        .decode(started["registrationResponse"].as_str().unwrap())
        .unwrap();
    let response = RegistrationResponse::deserialize(&response).unwrap();
    let finish = start
        .state
        .finish(&mut rand_core::OsRng, b"pw", response, Default::default())
        .unwrap();
    let record = json!({
        "registrationRecord": STANDARD.encode(finish.message.serialize()),
        "ksfParams": STANDARD.encode([&[1, 0, 4, 0, 0, 0, 0, 0, 3, 1][..], &[5; 16]].concat()),
        "passwordSetupToken": setup,
        "registrationId": started["registrationId"],
    });
    proxy.rpc("AuthService/FinishPasswordSetup", None, record);
}

/// Signs in as `root` through `proxy`; returns the session token.
fn sign_in(proxy: &Proxy) -> String {
    use base64::{Engine, engine::general_purpose::STANDARD};
    use opaque_ke::{ClientLogin, ClientLoginFinishParameters, CredentialResponse, Identifiers};
    use photolib_server::auth::{CONTEXT, Suite};

    let start = ClientLogin::<Suite>::start(&mut rand_core::OsRng, b"pw").unwrap();
    let ke1 = STANDARD.encode(start.message.serialize());
    let started = proxy.rpc("AuthService/StartLogin", None, json!({ "handle": "root", "ke1": ke1 }));
    let ke2 = STANDARD.decode(started["ke2"].as_str().unwrap()).unwrap();
    let parameters = ClientLoginFinishParameters::new(Some(CONTEXT), Identifiers::default(), None);
    let ke2 = CredentialResponse::deserialize(&ke2).unwrap();
    let finish = start
        .state
        .finish(&mut rand_core::OsRng, b"pw", ke2, parameters)
        .unwrap();
    let body = json!({
        "loginId": started["loginId"],
        "ke3": STANDARD.encode(finish.message.serialize()),
        "device": { "name": "CLI", "platform": "linux" },
    });
    let finished = proxy.rpc("AuthService/FinishLogin", None, body);
    finished["session"]["token"].as_str().unwrap().into()
}

/// Uploads `bytes` into `library` as the apps do, in two pieces, through `proxy`; returns the acknowledgement.
fn upload(proxy: &Proxy, session: &str, library: Uuid, bytes: &[u8]) -> Value {
    let auth = format!("authorization: Bearer {session}");
    let (length, hash) = (bytes.len().to_string(), photolib_storage::Hash::of(bytes).to_string());
    let url = proxy.url("/upload");
    let created = proxy.curl(&[
        "-X",
        "POST",
        "-H",
        &auth,
        "-H",
        "upload-complete: ?0",
        "-H",
        &format!("upload-length: {length}"),
        "-H",
        &format!("photolib-library: {library}"),
        "-H",
        &format!("photolib-hash: {hash}"),
        &url,
    ]);
    assert_eq!(
        created.status,
        201,
        "{}: {}",
        proxy.at(),
        String::from_utf8_lossy(&created.body)
    );
    let location = format!("{}/{}", url.rsplit_once('/').unwrap().0, created.headers["location"]);
    let half = 32 << 20;
    let mut acknowledged = Value::Null;
    for (offset, piece, complete) in [(0, &bytes[..half], "?0"), (half, &bytes[half..], "?1")] {
        let file = proxy.dir.path().join("piece");
        std::fs::write(&file, piece).unwrap();
        let reply = proxy.curl(&[
            "-X",
            "PATCH",
            "-H",
            &auth,
            "-H",
            "content-type: application/partial-upload",
            "-H",
            &format!("upload-offset: {offset}"),
            "-H",
            &format!("upload-complete: {complete}"),
            "--data-binary",
            &format!("@{}", file.display()),
            &location,
        ]);
        assert!(
            [200, 204].contains(&reply.status),
            "{}: {}",
            proxy.at(),
            String::from_utf8_lossy(&reply.body)
        );
        if complete == "?1" {
            acknowledged = reply.json();
        }
    }
    acknowledged
}

#[tokio::test(flavor = "multi_thread")]
async fn the_e2e_suite_passes_behind_every_template_at_the_root_and_under_photos() {
    use base64::{Engine, engine::general_purpose::STANDARD_NO_PAD};
    use buffa::Message;

    let bins = binaries();
    let bytes = pattern(3..(40 << 20) + 3);
    for base in BASES {
        let db = photolib_db::testpg::database().await;
        let dir = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
        let server = Photolibd::start(dir.path(), &db.url, base);

        let login = format!("http://{}{base}/photolib.api.v1.AuthService/StartLogin", server.addr);
        let refused = output(
            tool("curl")
                .args([
                    "-s",
                    "-H",
                    "content-type: application/json",
                    "-H",
                    "x-forwarded-for: 203.0.113.9",
                ])
                .args(["--data-binary", "{}", &login]),
            TOOL,
        );
        let refused: Value = serde_json::from_slice(&refused.stdout).unwrap();
        let detail = STANDARD_NO_PAD
            .decode(refused["details"][0]["value"].as_str().unwrap())
            .unwrap();
        let detail = photolib_proto::proto::photolib::api::v1::ErrorDetail::decode_from_slice(&detail).unwrap();
        assert_eq!(
            (refused["code"].as_str(), detail.code.as_str()),
            (Some("failed_precondition"), "login.insecure_http"),
            "a sign-in over plain HTTP from beyond the local networks"
        );

        let library = Uuid::now_v7();
        for (index, name) in PROXIES.into_iter().enumerate() {
            let proxy = Proxy::start(name, base, server.addr, &bins, free_port);
            let at = proxy.at();
            let ready = proxy.curl(&[&proxy.url("/readyz")]);
            assert_eq!(
                (ready.version.as_str(), ready.status),
                ("2", 200),
                "{at}: {}",
                proxy.log()
            );
            if index == 0 {
                create_admin(&proxy, &server.setup_token);
                sqlx::query(
                    "INSERT INTO libraries (id, owner_id, name, kind, root_uri, store) \
                     SELECT $1, id, 'Photos', 'managed', 'photos', 'local' FROM users WHERE handle = 'root'",
                )
                .bind(library)
                .execute(&db.pool)
                .await
                .unwrap();
            }
            let session = sign_in(&proxy);
            let users = proxy.rpc("UserService/ListUsers", Some(&session), json!({}));
            assert_eq!(users["users"][0]["handle"], "root", "{at}");
            let acknowledged = upload(&proxy, &session, library, &bytes);
            let hash = photolib_storage::Hash::of(&bytes).to_string();
            assert_eq!(
                (&acknowledged["length"], &acknowledged["blake3"]),
                (&json!(bytes.len()), &json!(hash)),
                "{at}"
            );

            proxy.rpc("ServerInfoService/GetServerInfo", None, json!({}));
            let auth = format!("authorization: Bearer {TOKEN}");
            let outside = proxy.curl(&["-H", &auth, &proxy.url("/diagnostics")]);
            assert_eq!(outside.status, 403, "{at} refuses /diagnostics, token or not");
            let url = format!("http://{}{base}/diagnostics", server.addr);
            let diagnostics = output(tool("curl").args(["-s", "-H", &auth, &url]), TOOL);
            let diagnostics: Value = serde_json::from_slice(&diagnostics.stdout).unwrap();
            let checks = diagnostics["checks"].clone();
            let check = checks
                .as_array()
                .unwrap()
                .iter()
                .find(|c| c["name"] == "proxy")
                .unwrap()
                .clone();
            assert_eq!(check["status"], "ok", "{at}: {check}");
            stop(proxy);
        }
        let doctor = output(
            tool(env!("CARGO_BIN_EXE_photolibd"))
                .arg("--config")
                .arg(&server.config)
                .arg("doctor")
                .env_clear(),
            TOOL,
        );
        let out = String::from_utf8_lossy(&doctor.stdout);
        assert!(
            out.contains("ok   proxy: requests arrive through a reverse proxy over HTTPS"),
            "{base}/: {out}"
        );
    }
}

/// Cloudflare's edge terminates TLS, so the tunnel recipe can only be checked offline: cloudflared accepts it and routes
/// the recipe's hostname to photolibd but for `/metrics` and `/diagnostics`, and nothing else anywhere.
#[test]
fn the_cloudflare_tunnel_recipe_routes_its_hostname_to_photolibd() {
    let cloudflared = &binaries()["cloudflared"][0];
    let recipe = repo().join("deploy/proxy/cloudflared.yml");
    let ingress = |args: &[&str]| {
        let output = output(
            tool(cloudflared)
                .args(["tunnel", "--config"])
                .arg(&recipe)
                .arg("ingress")
                .args(args),
            TOOL,
        );
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        String::from_utf8(output.stdout).unwrap()
    };
    assert!(ingress(&["validate"]).contains("OK"));
    for path in ["/", "/photos/upload"] {
        let rule = ingress(&["rule", &format!("https://{DOMAIN}{path}")]);
        assert!(rule.contains("service: http://photolibd:8080"), "{path}: {rule}");
    }
    for path in ["/metrics", "/photos/diagnostics"] {
        let rule = ingress(&["rule", &format!("https://{DOMAIN}{path}")]);
        assert!(rule.contains("http_status:403"), "{path}: {rule}");
    }
    assert!(ingress(&["rule", "https://elsewhere.example.com/"]).contains("http_status:404"));
}
