//! OpenID Connect sign-in (M2-04, ADR-0087): the provider's metadata and keys, the ID token and the claims photolibd
//! reads, each checked before it is used.

use std::{
    collections::{BTreeMap, HashMap},
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use axum::http::{Request, header};
use base64::{
    Engine,
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD as B64},
};
use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{Client, connect::HttpConnector},
    rt::TokioExecutor,
};
use photolib_proto::proto::photolib::api::v1::UserRole;
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use url::{Host, Url, form_urlencoded};
use uuid::Uuid;

use crate::{
    auth::new_token,
    config::{OidcProvider, RoleClaim},
};

/// How long a provider may take to answer one request.
const TIMEOUT: Duration = Duration::from_secs(10);
/// The most photolibd reads of an answer; an ID token with hundreds of groups stays well below.
const MAX_BODY: usize = 64 * 1024;
/// How long a person has to sign in at the provider.
const WINDOW: Duration = Duration::from_secs(600);
/// Bounds the memory unfinished sign-ins take; when it is full, new ones wait.
const MAX_PENDING: usize = 10_000;
/// How long a provider's metadata is reused.
const METADATA_TTL: Duration = Duration::from_secs(3600);

/// The providers of an API process and the sign-ins under way, which live in its memory like OPAQUE logins
/// (ADR-0052).
pub struct Oidc {
    providers: BTreeMap<String, Provider>,
    http: Client<HttpsConnector<HttpConnector>, Full<Bytes>>,
    pending: Mutex<HashMap<String, Pending>>,
}

struct Provider {
    config: OidcProvider,
    metadata: Mutex<Option<(Instant, Arc<Metadata>)>>,
}

/// The endpoints of a provider's discovery document.
struct Metadata {
    authorization: Url,
    token: Url,
    jwks: Url,
    userinfo: Option<Url>,
}

struct Pending {
    provider: String,
    redirect_uri: String,
    challenge: String,
    nonce: String,
    link: Option<Uuid>,
    expires: Instant,
}

/// A sign-in the provider vouched for.
pub struct Completed<'a> {
    pub provider: &'a OidcProvider,
    pub identity: Identity,
    /// The account that asked to link this identity.
    pub link: Option<Uuid>,
}

/// Why a sign-in with a provider failed.
#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    UnknownProvider,
    /// The provider did not answer, or not as OpenID Connect says.
    Unavailable,
    /// The flow, the code, the PKCE verifier or the ID token is not valid.
    Refused,
    /// A claim photolibd reads has the wrong type or size.
    Claim(String),
    /// Too many sign-ins are under way.
    Busy,
}

/// What photolibd reads of a person's claims, each checked.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Identity {
    pub subject: String,
    /// Only when the provider verified it, in lower case.
    pub email: Option<String>,
    pub name: Option<String>,
    pub username: Option<String>,
    /// The values of the role claim.
    pub roles: Vec<String>,
}

impl Oidc {
    pub fn new(providers: &BTreeMap<String, OidcProvider>) -> Result<Oidc, String> {
        let tls = Arc::new(rustls::crypto::ring::default_provider());
        let connector = hyper_rustls::HttpsConnectorBuilder::new()
            .with_provider_and_native_roots(tls)
            .map_err(|error| format!("cannot load the system's TLS roots: {error}"))?
            .https_or_http()
            .enable_http1()
            .build();
        let providers = providers.iter().map(|(id, config)| {
            let provider = Provider {
                config: config.clone(),
                metadata: Mutex::default(),
            };
            (id.clone(), provider)
        });
        Ok(Oidc {
            providers: providers.collect(),
            http: Client::builder(TokioExecutor::new()).build(connector),
            pending: Mutex::default(),
        })
    }

    /// The id and name of each provider.
    pub fn providers(&self) -> impl Iterator<Item = (&str, &str)> {
        self.providers
            .iter()
            .map(|(id, provider)| (id.as_str(), provider.config.name.as_str()))
    }

    /// The authorization URL of a new sign-in at `provider`, for the client's `redirect_uri` and PKCE `challenge`.
    pub async fn start(
        &self,
        provider: &str,
        redirect_uri: &str,
        challenge: &str,
        link: Option<Uuid>,
    ) -> Result<String, Failure> {
        let config = &self.providers.get(provider).ok_or(Failure::UnknownProvider)?.config;
        let metadata = self.metadata(provider).await?;
        let (state, nonce) = (new_token(), new_token());
        let mut url = metadata.authorization.clone();
        url.query_pairs_mut()
            .append_pair("response_type", "code")
            .append_pair("client_id", &config.client_id)
            .append_pair("redirect_uri", redirect_uri)
            .append_pair("scope", &config.scopes.join(" "))
            .append_pair("state", &state)
            .append_pair("nonce", &nonce)
            .append_pair("code_challenge", challenge)
            .append_pair("code_challenge_method", "S256");
        let now = Instant::now();
        let mut pending = self.pending.lock().unwrap();
        pending.retain(|_, flow| flow.expires > now);
        if pending.len() >= MAX_PENDING {
            return Err(Failure::Busy);
        }
        let flow = Pending {
            provider: provider.into(),
            redirect_uri: redirect_uri.into(),
            challenge: challenge.into(),
            nonce,
            link,
            expires: now + WINDOW,
        };
        pending.insert(state, flow);
        Ok(url.into())
    }

    /// Redeems the `code` of the sign-in `state` with the client's PKCE `verifier`: the ID token, checked, and the
    /// claims of it and of userinfo, checked.
    pub async fn complete(&self, state: &str, code: &str, verifier: &str) -> Result<Completed<'_>, Failure> {
        let flow = self.pending.lock().unwrap().remove(state);
        let flow = flow
            .filter(|flow| flow.expires > Instant::now() && challenge(verifier) == flow.challenge)
            .ok_or(Failure::Refused)?;
        let config = &self.providers[&flow.provider].config;
        let metadata = self.metadata(&flow.provider).await?;
        // The form serializer is not Send: it must be gone before the request is awaited.
        let request = {
            let mut form = form_urlencoded::Serializer::new(String::new());
            form.append_pair("grant_type", "authorization_code")
                .append_pair("code", code)
                .append_pair("redirect_uri", &flow.redirect_uri)
                .append_pair("code_verifier", verifier);
            let request = Request::post(metadata.token.as_str())
                .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded");
            let request = match &config.client_secret {
                // client_secret_basic (RFC 6749 §2.3.1), which every provider supports.
                Some(secret) => {
                    let encode = |text: &str| form_urlencoded::byte_serialize(text.as_bytes()).collect::<String>();
                    let basic = format!("{}:{}", encode(&config.client_id), encode(secret.expose()));
                    request.header(header::AUTHORIZATION, format!("Basic {}", STANDARD.encode(basic)))
                }
                None => {
                    form.append_pair("client_id", &config.client_id);
                    request
                }
            };
            request.body(form.finish().into())
        };
        let (ok, tokens) = self.json(request).await?;
        let text = |name: &str| tokens.get(name).and_then(Value::as_str);
        let (true, Some(id_token)) = (ok, text("id_token")) else {
            return Err(Failure::Refused);
        };
        let (_, jwks) = self
            .json(Request::get(metadata.jwks.as_str()).body(Full::default()))
            .await?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64();
        let jwks = Value::Object(jwks);
        let mut claims = verify_id_token(id_token, &jwks, &config.issuer, &config.client_id, &flow.nonce, now)?;
        if let (Some(userinfo), Some(access)) = (&metadata.userinfo, text("access_token")) {
            let request = Request::get(userinfo.as_str()).header(header::AUTHORIZATION, format!("Bearer {access}"));
            let (ok, more) = self.json(request.body(Full::default())).await?;
            if !ok {
                return Err(Failure::Unavailable);
            }
            if more.get("sub") != claims.get("sub") {
                return Err(Failure::Refused);
            }
            claims.extend(more);
        }
        let role_claim = config.roles.as_ref().map(|roles| roles.claim.as_str());
        Ok(Completed {
            provider: config,
            identity: identity(&claims, role_claim)?,
            link: flow.link,
        })
    }

    /// The provider's discovery document, fetched at most hourly.
    async fn metadata(&self, id: &str) -> Result<Arc<Metadata>, Failure> {
        let provider = &self.providers[id];
        if let Some((fetched, metadata)) = &*provider.metadata.lock().unwrap()
            && fetched.elapsed() < METADATA_TTL
        {
            return Ok(metadata.clone());
        }
        let issuer = &provider.config.issuer;
        let url = format!("{}/.well-known/openid-configuration", issuer.trim_end_matches('/'));
        let (ok, document) = self.json(Request::get(url).body(Full::default())).await?;
        let endpoint = |name: &str| {
            let url = Url::parse(document.get(name)?.as_str()?).ok()?;
            secure(&url).then_some(url)
        };
        let metadata = match (ok, document.get("issuer")) {
            (true, Some(found)) if found == issuer => Metadata {
                authorization: endpoint("authorization_endpoint").ok_or(Failure::Unavailable)?,
                token: endpoint("token_endpoint").ok_or(Failure::Unavailable)?,
                jwks: endpoint("jwks_uri").ok_or(Failure::Unavailable)?,
                userinfo: endpoint("userinfo_endpoint"),
            },
            _ => return Err(Failure::Unavailable),
        };
        let metadata = Arc::new(metadata);
        *provider.metadata.lock().unwrap() = Some((Instant::now(), metadata.clone()));
        Ok(metadata)
    }

    /// The JSON object a provider answers `request` with, and whether its status was a success; anything else, or no
    /// answer within the timeout, is `Unavailable`. Redirects are not followed.
    async fn json(
        &self,
        request: Result<Request<Full<Bytes>>, axum::http::Error>,
    ) -> Result<(bool, Map<String, Value>), Failure> {
        let request = request.map_err(|_| Failure::Unavailable)?;
        let answer = async {
            let response = self.http.request(request).await.ok()?;
            let ok = response.status().is_success();
            let body = Limited::new(response.into_body(), MAX_BODY).collect().await.ok()?;
            Some((ok, serde_json::from_slice(&body.to_bytes()).ok()?))
        };
        tokio::time::timeout(TIMEOUT, answer)
            .await
            .ok()
            .flatten()
            .ok_or(Failure::Unavailable)
    }
}

/// Whether photolibd may send a client secret or a code to `url`: HTTPS, or HTTP on this machine.
pub fn secure(url: &Url) -> bool {
    match url.scheme() {
        "https" => true,
        "http" => match url.host() {
            Some(Host::Domain(domain)) => domain == "localhost",
            Some(Host::Ipv4(ip)) => ip.is_loopback(),
            Some(Host::Ipv6(ip)) => ip.is_loopback(),
            None => false,
        },
        _ => false,
    }
}

/// The S256 challenge of a PKCE verifier (RFC 7636 §4.2).
pub fn challenge(verifier: &str) -> String {
    B64.encode(Sha256::digest(verifier))
}

/// The claims of `token` when a key of `jwks` signed it for `client_id` at `issuer` with `nonce`, and it has not
/// expired at `now`, in seconds since 1970.
pub fn verify_id_token(
    token: &str,
    jwks: &Value,
    issuer: &str,
    client_id: &str,
    nonce: &str,
    now: f64,
) -> Result<Map<String, Value>, Failure> {
    let claims = signed(token, jwks).ok_or(Failure::Refused)?;
    let text = |name: &str| claims.get(name).and_then(Value::as_str);
    let number = |name: &str| claims.get(name).and_then(Value::as_f64);
    let audience = match &claims.get("aud") {
        Some(Value::String(audience)) => audience == client_id,
        Some(Value::Array(audiences)) => audiences.iter().any(|audience| audience == client_id),
        _ => false,
    };
    // A minute of clock skew.
    let fresh = number("exp").is_some_and(|exp| exp + 60.0 > now) && number("iat").is_some();
    let valid = text("iss") == Some(issuer)
        && audience
        && claims.get("azp").is_none_or(|azp| azp == client_id)
        && text("nonce") == Some(nonce)
        && fresh;
    valid.then_some(claims).ok_or(Failure::Refused)
}

/// The payload of a JWS in compact form, if a key of `jwks` for its algorithm and `kid` signed it.
fn signed(token: &str, jwks: &Value) -> Option<Map<String, Value>> {
    let [header, payload, signature] = token.split('.').collect::<Vec<_>>()[..] else {
        return None;
    };
    let message = &token.as_bytes()[..header.len() + 1 + payload.len()];
    let header: Map<String, Value> = serde_json::from_slice(&B64.decode(header).ok()?).ok()?;
    let signature = B64.decode(signature).ok()?;
    let alg = header.get("alg")?.as_str()?;
    if header.contains_key("crit") {
        return None;
    }
    let kid = header.get("kid");
    let verified = jwks.get("keys")?.as_array()?.iter().any(|key| {
        kid.is_none_or(|kid| key.get("kid") == Some(kid))
            && key.get("use").is_none_or(|usage| usage == "sig")
            && key.get("alg").is_none_or(|key_alg| key_alg == alg)
            && verifies(key, alg, message, &signature)
    });
    verified.then(|| serde_json::from_slice(&B64.decode(payload).ok()?).ok())?
}

/// Whether the JWK `key` verifies `signature` of `message` with the JWS algorithm `alg`; HMAC and `none` never do.
fn verifies(key: &Value, alg: &str, message: &[u8], signature: &[u8]) -> bool {
    use ring::signature::*;
    let field = |name: &str| B64.decode(key.get(name)?.as_str()?).ok();
    let kty = |kty: &str, crv: Option<&str>| key["kty"] == kty && crv.is_none_or(|crv| key["crv"] == crv);
    let rsa = |params: &'static RsaParameters| match (kty("RSA", None), field("n"), field("e")) {
        (true, Some(n), Some(e)) => RsaPublicKeyComponents { n, e }
            .verify(params, message, signature)
            .is_ok(),
        _ => false,
    };
    let point =
        |crv: &str, alg: &'static dyn VerificationAlgorithm| match (kty("EC", Some(crv)), field("x"), field("y")) {
            (true, Some(x), Some(y)) => UnparsedPublicKey::new(alg, [&[4][..], &x, &y].concat())
                .verify(message, signature)
                .is_ok(),
            _ => false,
        };
    match alg {
        "RS256" => rsa(&RSA_PKCS1_2048_8192_SHA256),
        "RS384" => rsa(&RSA_PKCS1_2048_8192_SHA384),
        "RS512" => rsa(&RSA_PKCS1_2048_8192_SHA512),
        "PS256" => rsa(&RSA_PSS_2048_8192_SHA256),
        "PS384" => rsa(&RSA_PSS_2048_8192_SHA384),
        "PS512" => rsa(&RSA_PSS_2048_8192_SHA512),
        "ES256" => point("P-256", &ECDSA_P256_SHA256_FIXED),
        "ES384" => point("P-384", &ECDSA_P384_SHA384_FIXED),
        "EdDSA" => {
            kty("OKP", Some("Ed25519"))
                && field("x").is_some_and(|x| UnparsedPublicKey::new(&ED25519, x).verify(message, signature).is_ok())
        }
        _ => false,
    }
}

/// The claims photolibd reads, checked for type and size; `role_claim` names the claim of the role mapping. A
/// picture is checked, as clients may show it, but never fetched.
pub fn identity(claims: &Map<String, Value>, role_claim: Option<&str>) -> Result<Identity, Failure> {
    let invalid = |claim: &str| Failure::Claim(claim.into());
    let short = |text: &str, max: usize| text.chars().count() <= max && !text.chars().any(char::is_control);
    let text = |claim: &str, max: usize| match claims.get(claim) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(text)) if short(text, max) => Ok(Some(text.clone()).filter(|text| !text.is_empty())),
        _ => Err(invalid(claim)),
    };
    let subject = text("sub", 255)?.ok_or_else(|| invalid("sub"))?;
    let email = text("email", 254)?.map(|email| email.to_lowercase());
    let address = |email: &String| match email.split_once('@') {
        Some((local, domain)) => !local.is_empty() && !domain.is_empty() && !domain.contains('@'),
        None => false,
    };
    if email
        .as_ref()
        .is_some_and(|email| !address(email) || email.contains(char::is_whitespace))
    {
        return Err(invalid("email"));
    }
    let verified = match claims.get("email_verified") {
        None | Some(Value::Null) => false,
        Some(Value::Bool(verified)) => *verified,
        _ => return Err(invalid("email_verified")),
    };
    let picture = text("picture", 2048)?;
    if picture.is_some_and(|picture| !Url::parse(&picture).is_ok_and(|url| url.scheme() == "https")) {
        return Err(invalid("picture"));
    }
    let roles = match role_claim.map(|claim| (claim, claims.get(claim))) {
        None | Some((_, None | Some(Value::Null))) => vec![],
        Some((_, Some(Value::String(value)))) if short(value, 255) => vec![value.clone()],
        Some((claim, Some(Value::Array(values)))) if values.len() <= 1000 => values
            .iter()
            .map(|value| value.as_str().filter(|value| short(value, 255)).map(String::from))
            .collect::<Option<_>>()
            .ok_or_else(|| invalid(claim))?,
        Some((claim, _)) => return Err(invalid(claim)),
    };
    Ok(Identity {
        subject,
        email: email.filter(|_| verified),
        name: text("name", 255)?,
        username: text("preferred_username", 255)?,
        roles,
    })
}

/// The highest role one of `values` maps to.
pub fn role(mapping: &RoleClaim, values: &[String]) -> Option<UserRole> {
    [
        (&mapping.admin, UserRole::USER_ROLE_ADMIN),
        (&mapping.user, UserRole::USER_ROLE_USER),
        (&mapping.viewer, UserRole::USER_ROLE_VIEWER),
    ]
    .into_iter()
    .find(|(mapped, _)| values.iter().any(|value| mapped.contains(value)))
    .map(|(_, role)| role)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::testing::Signer;

    const ISSUER: &str = "https://sso.example/realms/home";
    const NOW: f64 = 1_800_000_000.0;
    /// 2100-01-01.
    const LATER: f64 = 4_102_444_800.0;

    fn claims(now: f64) -> Value {
        json!({
            "iss": ISSUER, "aud": "photolib", "azp": "photolib", "sub": "f:9b1d", "nonce": "n0nce",
            "iat": now, "exp": now + 300.0,
        })
    }

    fn jwks(keys: &[&Signer]) -> Value {
        json!({ "keys": keys.iter().map(|key| key.jwk()).collect::<Vec<_>>() })
    }

    fn verify(token: &str, keys: &[&Signer], now: f64) -> Result<Value, Failure> {
        let claims = verify_id_token(token, &jwks(keys), ISSUER, "photolib", "n0nce", now)?;
        Ok(claims["sub"].clone())
    }

    #[test]
    fn an_id_token_signed_by_a_key_of_the_provider_is_accepted_in_each_algorithm() {
        let other = Signer::es256();
        for signer in [
            Signer::rsa("RS256"),
            Signer::rsa("PS256"),
            Signer::es256(),
            Signer::eddsa(),
        ] {
            let token = signer.sign(&claims(NOW));
            assert_eq!(
                verify(&token, &[&other, &signer], NOW),
                Ok(json!("f:9b1d")),
                "{}",
                signer.alg
            );
            assert_eq!(
                verify(&token, &[&other], NOW),
                Err(Failure::Refused),
                "{}: another key",
                signer.alg
            );
        }
    }

    #[test]
    fn a_forged_unsigned_or_misnamed_token_is_refused() {
        let signer = Signer::rsa("RS256");
        let token = signer.sign(&claims(NOW));
        let parts: Vec<&str> = token.split('.').collect();
        let forged = B64.encode(json!({ "sub": "admin" }).to_string());
        let header = |header: Value| B64.encode(header.to_string());
        let mut renamed = signer.jwk();
        renamed["alg"] = "RS512".into();
        let mut encrypting = signer.jwk();
        encrypting["use"] = "enc".into();
        for (token, keys, why) in [
            (
                format!("{}.{forged}.{}", parts[0], parts[2]),
                jwks(&[&signer]),
                "another payload",
            ),
            (
                format!("{}.{}.", header(json!({ "alg": "none" })), parts[1]),
                jwks(&[&signer]),
                "alg none",
            ),
            (
                format!("{}.{}.{}", header(json!({ "alg": "HS256" })), parts[1], parts[2]),
                jwks(&[&signer]),
                "HS256",
            ),
            (
                token.clone(),
                json!({ "keys": [renamed] }),
                "a key for another algorithm",
            ),
            (token.clone(), json!({ "keys": [encrypting] }), "an encryption key"),
            (
                signer.sign_with(&json!({ "alg": "RS256", "kid": "other" }), &claims(NOW)),
                jwks(&[&signer]),
                "kid",
            ),
            (
                signer.sign_with(&json!({ "alg": "RS256", "crit": ["exp"] }), &claims(NOW)),
                jwks(&[&signer]),
                "crit",
            ),
            (parts[..2].join("."), jwks(&[&signer]), "two parts"),
            (format!("{token}.x"), jwks(&[&signer]), "four parts"),
            (token.replace('.', ".!"), jwks(&[&signer]), "not base64url"),
            (token.clone(), json!({ "keys": "none" }), "no key set"),
        ] {
            let result = verify_id_token(&token, &keys, ISSUER, "photolib", "n0nce", NOW);
            assert_eq!(result, Err(Failure::Refused), "{why}");
        }
        let unkeyed = signer.sign_with(&json!({ "alg": "RS256" }), &claims(NOW));
        assert_eq!(
            verify(&unkeyed, &[&signer], NOW),
            Ok(json!("f:9b1d")),
            "a token without kid tries every key"
        );
    }

    #[test]
    fn the_token_must_name_the_issuer_and_the_client_and_carry_the_nonce() {
        let signer = Signer::es256();
        for (claim, value, accepted) in [
            ("aud", json!(["account", "photolib"]), true),
            ("azp", Value::Null, true),
            ("iss", json!("https://sso.example/realms/other"), false),
            ("iss", json!("https://sso.example/realms/home/"), false),
            ("aud", json!("account"), false),
            ("aud", json!(["account"]), false),
            ("azp", json!("account"), false),
            ("nonce", json!("other"), false),
            ("nonce", Value::Null, false),
            ("exp", json!("soon"), false),
            ("iat", Value::Null, false),
        ] {
            let mut claims = claims(NOW);
            match &value {
                Value::Null => claims.as_object_mut().unwrap().remove(claim),
                value => claims.as_object_mut().unwrap().insert(claim.into(), value.clone()),
            };
            let result = verify(&signer.sign(&claims), &[&signer], NOW);
            assert_eq!(result.is_ok(), accepted, "{claim}: {value}");
        }
    }

    #[test]
    fn a_clock_in_2100_accepts_tokens_of_2100_and_refuses_older_ones() {
        let signer = Signer::eddsa();
        assert!(verify(&signer.sign(&claims(LATER)), &[&signer], LATER).is_ok());
        let expired = |age: f64| verify(&signer.sign(&claims(LATER - 300.0 - age)), &[&signer], LATER);
        assert!(expired(59.0).is_ok(), "a minute of clock skew is allowed");
        assert_eq!(expired(61.0), Err(Failure::Refused));
        assert_eq!(expired(LATER - NOW), Err(Failure::Refused), "a token of today");
    }

    fn checked(claims: Value) -> Result<Identity, Failure> {
        identity(claims.as_object().unwrap(), Some("groups"))
    }

    #[test]
    fn claims_are_read_with_their_type_and_size_and_unverified_emails_are_dropped() {
        let full = json!({
            "sub": "f:9b1d", "email": "Ann@Example.org", "email_verified": true, "name": "Ann Lee",
            "preferred_username": "ann", "groups": ["/family", "admins"], "picture": "https://cdn.example/ann.png",
            "address": { "country": "NZ" }, "updated_at": 1,
        });
        assert_eq!(
            checked(full.clone()),
            Ok(Identity {
                subject: "f:9b1d".into(),
                email: Some("ann@example.org".into()),
                name: Some("Ann Lee".into()),
                username: Some("ann".into()),
                roles: vec!["/family".into(), "admins".into()],
            })
        );
        let mut unverified = full.clone();
        unverified["email_verified"] = false.into();
        assert_eq!(checked(unverified).unwrap().email, None);
        let minimal = checked(json!({ "sub": "x", "email": "a@b", "groups": "admins", "name": null }));
        assert_eq!(
            minimal,
            Ok(Identity {
                subject: "x".into(),
                roles: vec!["admins".into()],
                ..Default::default()
            }),
            "an unverified email is no email, one value is a list of one, null is absent"
        );
        let long = |n: usize| json!("x".repeat(n));
        for (claim, value) in [
            ("sub", Value::Null),
            ("sub", json!("")),
            ("sub", long(256)),
            ("sub", json!(42)),
            ("sub", json!("a\nb")),
            ("email", json!("ann")),
            ("email", json!("ann@@example.org")),
            ("email", json!("ann lee@example.org")),
            ("email", json!(format!("{}@example.org", "x".repeat(250)))),
            ("email", json!(["ann@example.org"])),
            ("email_verified", json!("true")),
            ("name", json!({ "first": "Ann" })),
            ("name", long(256)),
            ("name", json!("Ann\u{0}")),
            ("preferred_username", json!(7)),
            ("preferred_username", long(256)),
            ("picture", json!("data:image/png;base64,iVBORw0KGgo=")),
            ("picture", json!("DATA:text/html,<script>")),
            ("picture", json!("http://cdn.example/ann.png")),
            ("picture", json!("javascript:alert(1)")),
            ("picture", json!(format!("https://cdn.example/{}", "x".repeat(2048)))),
            ("groups", json!({ "admins": true })),
            ("groups", json!([1, 2])),
            ("groups", json!(["a\u{7}"])),
            ("groups", json!(vec!["g"; 1001])),
            ("groups", json!([long(256)])),
        ] {
            let mut claims = full.clone();
            claims[claim] = value.clone();
            let shown = value.to_string();
            assert_eq!(
                checked(claims),
                Err(Failure::Claim(claim.into())),
                "{claim}: {shown:.80}"
            );
        }
    }

    #[test]
    fn roles_come_from_the_highest_role_a_value_maps_to() {
        let mapping = RoleClaim {
            claim: "groups".into(),
            admin: vec!["admins".into()],
            user: vec!["family".into(), "friends".into()],
            viewer: vec!["guests".into()],
        };
        let role = |values: &[&str]| role(&mapping, &values.iter().map(|v| v.to_string()).collect::<Vec<_>>());
        assert_eq!(role(&["guests", "friends"]), Some(UserRole::USER_ROLE_USER));
        assert_eq!(role(&["admins", "guests"]), Some(UserRole::USER_ROLE_ADMIN));
        assert_eq!(role(&["guests"]), Some(UserRole::USER_ROLE_VIEWER));
        assert_eq!(role(&["Admins", "staff"]), None, "values match exactly");
        assert_eq!(role(&[]), None);
    }

    #[test]
    fn a_pkce_verifier_answers_its_s256_challenge() {
        // RFC 7636, appendix B.
        assert_eq!(
            challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
    }

    #[test]
    fn sign_ins_recorded_at_keycloak_and_authelia_pass_every_check() {
        for (provider, username, email, group) in [
            ("keycloak", "ann", "ann@example.org", "/family"),
            ("authelia", "cy", "cy@example.org", "family"),
        ] {
            let path = format!("{}/../../../testdata/oidc/{provider}.json", env!("CARGO_MANIFEST_DIR"));
            let fixture: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
            let parts: Vec<&str> = fixture["id_token_parts"]
                .as_array()
                .unwrap()
                .iter()
                .flat_map(Value::as_str)
                .collect();
            let payload: Value = serde_json::from_slice(&B64.decode(parts[1]).unwrap()).unwrap();
            let text = |name: &str| fixture[name].as_str().unwrap();
            let verify = |token: &str, now: f64| {
                verify_id_token(
                    token,
                    &fixture["jwks"],
                    text("issuer"),
                    text("client_id"),
                    text("nonce"),
                    now,
                )
            };
            let issued = payload["iat"].as_f64().unwrap();
            let mut claims = verify(&parts.join("."), issued).unwrap();
            claims.extend(fixture["userinfo"].as_object().unwrap().clone());
            let identity = identity(&claims, Some("groups")).unwrap();
            assert_eq!(
                (
                    identity.username.as_deref(),
                    identity.email.as_deref(),
                    &identity.roles[..]
                ),
                (Some(username), Some(email), &[group.to_string()][..]),
                "{provider}"
            );
            let expired = payload["exp"].as_f64().unwrap() + 61.0;
            assert_eq!(verify(&parts.join("."), expired), Err(Failure::Refused), "{provider}");
            let forged = [parts[0], &B64.encode(json!({ "sub": "admin" }).to_string()), parts[2]].join(".");
            assert_eq!(verify(&forged, issued), Err(Failure::Refused), "{provider}");
        }
    }

    #[tokio::test(start_paused = true)]
    async fn a_provider_that_never_answers_fails_the_sign_in_after_ten_seconds() {
        let silent = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let provider = OidcProvider {
            name: "Silent".into(),
            issuer: format!("http://{}", silent.local_addr().unwrap()),
            client_id: "photolib".into(),
            client_secret: None,
            scopes: vec!["openid".into()],
            provision: false,
            link_by_email: false,
            roles: None,
        };
        let oidc = Oidc::new(&BTreeMap::from([("silent".into(), provider)])).unwrap();
        let started = tokio::time::Instant::now();
        let challenge = challenge("v");
        assert_eq!(
            oidc.start("silent", "app:/x", &challenge, None).await.err(),
            Some(Failure::Unavailable)
        );
        assert_eq!(started.elapsed(), TIMEOUT);
    }
}
