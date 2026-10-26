//! Reverse proxies (design 15 §9, R-SEC-4): forwarded headers count only from `trusted_proxies`, and passwords and
//! setup tokens never cross plain HTTP from beyond the local networks unless `allow_insecure_http` says so.

use std::{
    fmt,
    net::{IpAddr, SocketAddr},
    str::FromStr,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use axum::{
    extract::{ConnectInfo, Request, State},
    middleware::Next,
    response::{IntoResponse, Response},
};
use connectrpc::{ConnectError, ErrorCode};
use serde::{Deserialize, Deserializer, Serialize, Serializer, de::Error as _};

use crate::rpc::ApiError;

/// The services whose requests carry a password's key exchange, a setup token or a session.
const SIGN_IN: [&str; 2] = ["/photolib.api.v1.AuthService/", "/photolib.api.v1.SetupService/"];
/// How often forwarded headers from an untrusted address are logged at most.
const WARN_EVERY: Duration = Duration::from_secs(600);

/// The settings the guard applies.
pub struct Proxies {
    trusted: Vec<Network>,
    allow_insecure_http: bool,
    warned: Mutex<Option<Instant>>,
}

impl Proxies {
    pub fn new(trusted: Vec<Network>, allow_insecure_http: bool) -> Self {
        Proxies {
            trusted,
            allow_insecure_http,
            warned: Mutex::new(None),
        }
    }

    fn trusts(&self, addr: IpAddr) -> bool {
        self.trusted.iter().any(|net| net.contains(addr))
    }

    fn forwarding(&self, request: &Request) -> Forwarding {
        let header = |name| {
            let values = request.headers().get_all(name).iter();
            let values: Vec<&str> = values.filter_map(|v| v.to_str().ok()).collect();
            (!values.is_empty()).then(|| values.join(","))
        };
        let (forwarded, hops) = (header("forwarded"), header("x-forwarded-for"));
        let proto = header("x-forwarded-proto")
            .and_then(|protos| protos.rsplit(',').next().map(str::to_string))
            .or_else(|| {
                let pair = forwarded
                    .as_deref()?
                    .split([';', ','])
                    .find_map(|p| p.trim().strip_prefix("proto="));
                pair.map(str::to_string)
            })
            .map(|proto| proto.trim().trim_matches('"').to_lowercase());
        let peer = request.extensions().get::<ConnectInfo<SocketAddr>>().map(|c| c.0.ip());
        let trusted = peer.is_some_and(|peer| self.trusts(peer));
        let mut client = peer;
        if trusted {
            for hop in hops.iter().flat_map(|hops| hops.rsplit(',')).map(str::trim) {
                client = hop.parse().ok();
                if !client.is_some_and(|hop| self.trusts(hop)) {
                    break;
                }
            }
        }
        Forwarding {
            peer,
            trusted,
            forwarded_for: hops.is_some() || forwarded.is_some_and(|f| f.contains("for=")),
            proto,
            client,
        }
    }

    fn warn(&self, peer: Option<IpAddr>) {
        let mut warned = self.warned.lock().unwrap();
        if warned.is_none_or(|at| at.elapsed() >= WARN_EVERY) {
            *warned = Some(Instant::now());
            tracing::warn!(
                peer = peer.map(|peer| peer.to_string()),
                "forwarded headers from an address outside trusted_proxies are ignored"
            );
        }
    }
}

/// How a request reached photolibd.
#[derive(Clone, Debug, Default)]
pub struct Forwarding {
    pub peer: Option<IpAddr>,
    /// The peer is in `trusted_proxies`.
    pub trusted: bool,
    pub forwarded_for: bool,
    pub proto: Option<String>,
    /// The peer, or the last address before the trusted proxies; `None` when that hop is unreadable.
    pub client: Option<IpAddr>,
}

impl Forwarding {
    /// Whether the client's connection was HTTPS: photolibd serves plain HTTP, so only a trusted proxy can say so.
    pub fn https(&self) -> bool {
        self.trusted && self.proto.as_deref() == Some("https")
    }
}

/// Loopback, private and link-local addresses: the local networks, where plain HTTP may sign in.
pub fn local(addr: IpAddr) -> bool {
    match addr.to_canonical() {
        IpAddr::V4(v4) => v4.is_loopback() || v4.is_private() || v4.is_link_local(),
        IpAddr::V6(v6) => v6.is_loopback() || v6.is_unique_local() || v6.is_unicast_link_local(),
    }
}

/// Puts each request's [`Forwarding`] among its extensions and refuses sign-ins over plain HTTP from beyond the local
/// networks.
pub async fn guard(State(proxies): State<Arc<Proxies>>, mut request: Request, next: Next) -> Response {
    let seen = proxies.forwarding(&request);
    if !seen.trusted && (seen.forwarded_for || seen.proto.is_some()) {
        proxies.warn(seen.peer);
    }
    let path = request.uri().path();
    if SIGN_IN.iter().any(|service| path.starts_with(service))
        && !proxies.allow_insecure_http
        && !seen.https()
        && !seen.client.is_some_and(local)
    {
        let error = ApiError::new(ErrorCode::FailedPrecondition, "login.insecure_http");
        return ConnectError::from(error)
            .into_http_response(request.headers())
            .into_response();
    }
    request.extensions_mut().insert(seen);
    next.run(request).await
}

/// An address or a network, such as `172.16.0.0/12`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Network {
    addr: IpAddr,
    prefix: u8,
}

/// An address as bits and their width, IPv4-mapped IPv6 addresses as IPv4.
fn bits(addr: IpAddr) -> (u128, u32) {
    match addr.to_canonical() {
        IpAddr::V4(v4) => (u32::from(v4).into(), 32),
        IpAddr::V6(v6) => (v6.into(), 128),
    }
}

fn masked(bits: u128, width: u32, prefix: u8) -> u128 {
    let host = width - u32::from(prefix);
    if host == 128 { 0 } else { bits >> host << host }
}

impl Network {
    pub fn contains(&self, addr: IpAddr) -> bool {
        let ((net, width), (other, other_width)) = (bits(self.addr), bits(addr));
        width == other_width && masked(other, width, self.prefix) == net
    }
}

impl FromStr for Network {
    type Err = String;

    fn from_str(text: &str) -> Result<Self, String> {
        let invalid = || format!("`{text}` is not an address or a network such as 172.16.0.0/12");
        let (addr, prefix) = text.split_once('/').unwrap_or((text, ""));
        let (bits, width) = bits(addr.parse().map_err(|_| invalid())?);
        let prefix = match prefix {
            "" => width as u8,
            prefix => prefix
                .parse()
                .ok()
                .filter(|p| u32::from(*p) <= width)
                .ok_or_else(invalid)?,
        };
        let bits = masked(bits, width, prefix);
        let addr = match width {
            32 => IpAddr::from((bits as u32).to_be_bytes()),
            _ => IpAddr::from(bits.to_be_bytes()),
        };
        Ok(Network { addr, prefix })
    }
}

impl fmt::Display for Network {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}", self.addr, self.prefix)
    }
}

impl Serialize for Network {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for Network {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        String::deserialize(deserializer)?.parse().map_err(D::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use axum::{
        Extension, Router,
        body::Body,
        http::{Request, StatusCode},
        middleware::from_fn_with_state,
        routing::post,
    };
    use tower::ServiceExt;

    use super::*;
    use crate::{
        config::{Log, LogFormat},
        testing::{Capture, connect_error},
    };

    fn proxies(trusted: &[&str], allow_insecure_http: bool) -> Arc<Proxies> {
        let trusted = trusted.iter().map(|net| net.parse().unwrap()).collect();
        Arc::new(Proxies::new(trusted, allow_insecure_http))
    }

    #[test]
    fn networks_hold_their_addresses_only() {
        let net = |text: &str| text.parse::<Network>().unwrap();
        let ip = |text: &str| text.parse::<IpAddr>().unwrap();
        assert!(net("10.0.0.0/8").contains(ip("10.255.0.1")));
        assert!(!net("10.0.0.0/8").contains(ip("11.0.0.1")));
        assert!(net("10.1.2.3").contains(ip("10.1.2.3")) && !net("10.1.2.3").contains(ip("10.1.2.4")));
        assert!(net("10.0.0.0/8").contains(ip("::ffff:10.0.0.1")), "IPv4-mapped");
        assert!(!net("10.0.0.0/8").contains(ip("::1")));
        assert!(net("0.0.0.0/0").contains(ip("203.0.113.9")) && !net("0.0.0.0/0").contains(ip("::1")));
        assert!(net("::/0").contains(ip("2001:db8::1")));
        assert!(net("fd00::/8").contains(ip("fd12::1")) && !net("fd00::/8").contains(ip("fe80::1")));
        assert_eq!(net("192.168.7.9/16").to_string(), "192.168.0.0/16");
    }

    #[test]
    fn only_loopback_private_and_link_local_addresses_are_local() {
        for local in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.20",
            "169.254.0.1",
            "::1",
            "fd00::1",
            "fe80::1",
            "::ffff:192.168.1.2",
        ] {
            assert!(super::local(local.parse().unwrap()), "{local}");
        }
        for remote in [
            "203.0.113.9",
            "172.32.0.1",
            "100.64.0.1",
            "2001:db8::1",
            "::ffff:8.8.8.8",
        ] {
            assert!(!super::local(remote.parse().unwrap()), "{remote}");
        }
    }

    /// What the guard made of a request from `peer` with these headers, or the status it refused it with.
    async fn send(
        proxies: Arc<Proxies>,
        peer: &str,
        path: &str,
        headers: &[(&str, &str)],
    ) -> Result<Forwarding, (StatusCode, serde_json::Value)> {
        let seen = Arc::new(Mutex::new(None));
        let record = seen.clone();
        let app = Router::new()
            .route(
                path,
                post(move |request: axum::extract::Request| async move {
                    *record.lock().unwrap() = request.extensions().get::<Forwarding>().cloned();
                }),
            )
            .layer(from_fn_with_state(proxies, guard))
            .layer(Extension(ConnectInfo(SocketAddr::new(peer.parse().unwrap(), 4242))));
        let mut request = Request::post(path).header("content-type", "application/json");
        for &(name, value) in headers {
            request = request.header(name, value);
        }
        let response = app.oneshot(request.body(Body::from("{}")).unwrap()).await.unwrap();
        let status = response.status();
        let body = axum::body::to_bytes(response.into_body(), 4096).await.unwrap();
        match seen.lock().unwrap().take() {
            Some(forwarding) => Ok(forwarding),
            None => Err((status, connect_error(&serde_json::from_slice(&body).unwrap()))),
        }
    }

    const LOGIN: &str = "/photolib.api.v1.AuthService/StartLogin";
    const SETUP: &str = "/photolib.api.v1.SetupService/CreateFirstAdmin";
    const INFO: &str = "/photolib.api.v1.ServerInfoService/GetServerInfo";

    #[tokio::test]
    async fn behind_a_trusted_proxy_the_client_is_the_last_untrusted_hop() {
        let proxies = proxies(&["127.0.0.0/8", "10.0.0.0/8"], false);
        let seen = send(
            proxies.clone(),
            "127.0.0.1",
            INFO,
            &[
                ("x-forwarded-for", "198.51.100.1, 203.0.113.9, 10.0.0.2"),
                ("x-forwarded-proto", "https"),
            ],
        )
        .await
        .unwrap();
        assert_eq!(seen.client, Some("203.0.113.9".parse().unwrap()));
        assert!(seen.trusted && seen.https() && seen.forwarded_for);
        let only_proxies = send(proxies.clone(), "10.0.0.3", INFO, &[("x-forwarded-for", "10.0.0.2")])
            .await
            .unwrap();
        assert_eq!(only_proxies.client, Some("10.0.0.2".parse().unwrap()));
        assert!(!only_proxies.https(), "no X-Forwarded-Proto: plain HTTP");
        let unreadable = send(
            proxies.clone(),
            "127.0.0.1",
            INFO,
            &[("x-forwarded-for", "203.0.113.9, unknown")],
        )
        .await
        .unwrap();
        assert_eq!(unreadable.client, None);
        let direct = send(proxies.clone(), "127.0.0.1", INFO, &[]).await.unwrap();
        assert_eq!(direct.client, Some("127.0.0.1".parse().unwrap()));
        let two = send(
            proxies.clone(),
            "127.0.0.1",
            INFO,
            &[("x-forwarded-proto", "http"), ("x-forwarded-proto", "https")],
        )
        .await
        .unwrap();
        assert!(two.https(), "the nearest proxy's value counts");
        let standard = send(
            proxies,
            "127.0.0.1",
            INFO,
            &[("forwarded", r#"for=203.0.113.9;proto="HTTPS""#)],
        )
        .await
        .unwrap();
        assert!(standard.forwarded_for && standard.https(), "{standard:?}");
    }

    #[tokio::test]
    async fn forwarded_headers_from_an_untrusted_address_are_ignored_and_logged_once() {
        let capture = Capture::default();
        let _guards = capture.set_default(&Log {
            format: LogFormat::Json,
            filter: "info".into(),
        });
        let proxies = proxies(&["127.0.0.0/8"], false);
        let spoofed = [("x-forwarded-for", "127.0.0.1"), ("x-forwarded-proto", "https")];
        for _ in 0..2 {
            let seen = send(proxies.clone(), "192.168.1.20", INFO, &spoofed).await.unwrap();
            assert_eq!(seen.client, Some("192.168.1.20".parse().unwrap()));
            assert!(!seen.trusted && !seen.https() && seen.forwarded_for);
        }
        let log = capture.text();
        assert_eq!(log.matches("outside trusted_proxies").count(), 1, "{log}");
        assert!(log.contains("192.168.1.20"), "{log}");
    }

    #[tokio::test]
    async fn sign_ins_over_plain_http_from_beyond_the_local_networks_are_refused() {
        let strict = proxies(&["127.0.0.0/8"], false);
        for path in [LOGIN, SETUP] {
            let refused = send(strict.clone(), "203.0.113.9", path, &[]).await.unwrap_err();
            let reason = serde_json::json!({ "code": "failed_precondition", "reason": "login.insecure_http" });
            assert_eq!(refused, (StatusCode::BAD_REQUEST, reason));
        }
        let forwarded_http = [("x-forwarded-for", "203.0.113.9"), ("x-forwarded-proto", "http")];
        assert!(send(strict.clone(), "127.0.0.1", LOGIN, &forwarded_http).await.is_err());
        let spoofed = [("x-forwarded-for", "127.0.0.1"), ("x-forwarded-proto", "https")];
        assert!(
            send(strict.clone(), "203.0.113.9", LOGIN, &spoofed).await.is_err(),
            "spoofed headers count for nothing"
        );
        let https = [("x-forwarded-for", "203.0.113.9"), ("x-forwarded-proto", "https")];
        assert!(send(strict.clone(), "127.0.0.1", LOGIN, &https).await.is_ok());
        for local in ["127.0.0.1", "192.168.1.20", "fd00::5"] {
            assert!(send(strict.clone(), local, LOGIN, &[]).await.is_ok(), "{local}");
        }
        assert!(
            send(strict, "203.0.113.9", INFO, &[]).await.is_ok(),
            "only sign-ins are refused"
        );
        assert!(
            send(proxies(&[], true), "203.0.113.9", LOGIN, &[]).await.is_ok(),
            "allow_insecure_http"
        );
    }
}
