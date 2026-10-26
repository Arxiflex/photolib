//! Passkeys (M2-05, ADR-0088): the relying party's half of WebAuthn Level 3 ceremonies in their JSON serialisation,
//! with "none" attestation and ES256, EdDSA or RS256 keys.

use std::time::Duration;

use base64::{
    Engine,
    alphabet::URL_SAFE,
    engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig},
};
use ring::signature::{
    ECDSA_P256_SHA256_ASN1, ED25519, RSA_PKCS1_2048_8192_SHA256, RsaPublicKeyComponents, UnparsedPublicKey,
};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

/// The relying party: the host passkeys are bound to and the origin their ceremonies run on.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RelyingParty {
    pub id: String,
    pub origin: String,
}

impl RelyingParty {
    /// The relying party of photolibd's `public_url`: an https:// origin, or http://localhost for development, which
    /// browsers treat as secure too. Passkeys bind to its host name, never to an IP address.
    pub fn from_url(url: &str) -> Option<RelyingParty> {
        let lower = url.to_ascii_lowercase();
        let (scheme, authority) = lower.split_once("://")?;
        let authority = authority.strip_suffix('/').unwrap_or(authority);
        let (host, port) = match authority.split_once(':') {
            Some((host, port)) => (host, Some(port.parse::<u16>().ok()?)),
            None => (authority, None),
        };
        let named = !host.ends_with(|c: char| c.is_ascii_digit())
            && host
                .split('.')
                .all(|label| !label.is_empty() && label.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-'));
        let secure = scheme == "https" || scheme == "http" && host == "localhost";
        let default = if scheme == "https" { 443 } else { 80 };
        let origin = match port {
            Some(port) if port != default => format!("{scheme}://{host}:{port}"),
            _ => format!("{scheme}://{host}"),
        };
        (named && secure).then(|| RelyingParty {
            id: host.into(),
            origin,
        })
    }
}

/// A credential a registration created: its id, its COSE public key and its signature counter.
#[derive(Debug, PartialEq, Eq)]
pub struct NewCredential {
    pub id: Vec<u8>,
    pub public_key: Vec<u8>,
    pub sign_count: u32,
}

/// An assertion, parsed but not yet checked: the credential it names finds the key that checks it.
#[derive(Debug)]
pub struct Assertion {
    pub credential_id: Vec<u8>,
    pub user_handle: Option<Vec<u8>>,
    client_data: Vec<u8>,
    authenticator_data: Vec<u8>,
    signature: Vec<u8>,
}

type Checked<T> = Result<T, &'static str>;

pub(crate) const UP: u8 = 0x01;
pub(crate) const UV: u8 = 0x04;
const AT: u8 = 0x40;
const ED: u8 = 0x80;

/// base64url as WebAuthn's JSON writes it, with or without padding.
const B64: GeneralPurpose = GeneralPurpose::new(
    &URL_SAFE,
    GeneralPurposeConfig::new()
        .with_encode_padding(false)
        .with_decode_padding_mode(DecodePaddingMode::Indifferent),
);

fn decode(text: &str) -> Checked<Vec<u8>> {
    B64.decode(text).map_err(|_| "base64url")
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Credential {
    raw_id: String,
    #[serde(rename = "type")]
    kind: String,
    response: Response,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Response {
    #[serde(rename = "clientDataJSON")]
    client_data_json: String,
    attestation_object: Option<String>,
    authenticator_data: Option<String>,
    signature: Option<String>,
    user_handle: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClientData {
    #[serde(rename = "type")]
    kind: String,
    challenge: String,
    origin: String,
    #[serde(default)]
    cross_origin: bool,
}

fn credential(json: &str) -> Checked<(Vec<u8>, Response)> {
    let credential: Credential = serde_json::from_str(json).map_err(|_| "json")?;
    if credential.kind != "public-key" {
        return Err("type");
    }
    Ok((decode(&credential.raw_id)?, credential.response))
}

/// Checks the client data of a ceremony of `kind` (`webauthn.create` or `.get`) that answered `challenge` on the
/// relying party's own origin, and the authenticator data's relying party and flags. Returns the flags.
fn check(
    rp: &RelyingParty,
    kind: &str,
    challenge: &[u8],
    client_data: &[u8],
    auth_data: &[u8],
    user_verified: bool,
) -> Checked<u8> {
    let client: ClientData = serde_json::from_slice(client_data).map_err(|_| "json")?;
    if client.kind != kind {
        return Err("type");
    }
    if decode(&client.challenge)? != challenge {
        return Err("challenge");
    }
    if client.origin != rp.origin || client.cross_origin {
        return Err("origin");
    }
    if auth_data.len() < 37 {
        return Err("authenticator data");
    }
    if auth_data[..32] != Sha256::digest(rp.id.as_bytes())[..] {
        return Err("rp");
    }
    let flags = auth_data[32];
    if flags & UP == 0 {
        return Err("presence");
    }
    if user_verified && flags & UV == 0 {
        return Err("verification");
    }
    Ok(flags)
}

fn counter(auth_data: &[u8]) -> u32 {
    u32::from_be_bytes(auth_data[33..37].try_into().unwrap())
}

/// How long a ceremony may take, and how long photolibd waits for its answer.
pub const TIMEOUT: Duration = Duration::from_secs(300);
/// EdDSA, ES256 and RS256, which Windows Hello uses, in that order of preference.
const ALGORITHMS: [i64; 3] = [-8, -7, -257];

fn descriptors(ids: &[Vec<u8>]) -> Value {
    ids.iter()
        .map(|id| json!({ "type": "public-key", "id": B64.encode(id) }))
        .collect()
}

/// PublicKeyCredentialCreationOptionsJSON for a new passkey of the account whose user handle is `user`: discoverable,
/// verifying its user, and none of `exclude`, which the account has already.
pub fn creation_options(
    rp: &RelyingParty,
    challenge: &[u8],
    user: &[u8],
    name: &str,
    display_name: &str,
    exclude: &[Vec<u8>],
) -> String {
    json!({
        "rp": { "id": rp.id, "name": "Photolib" },
        "user": { "id": B64.encode(user), "name": name, "displayName": display_name },
        "challenge": B64.encode(challenge),
        "pubKeyCredParams": ALGORITHMS.map(|alg| json!({ "type": "public-key", "alg": alg })),
        "timeout": TIMEOUT.as_millis(),
        "excludeCredentials": descriptors(exclude),
        "authenticatorSelection": {
            "residentKey": "required", "requireResidentKey": true, "userVerification": "required"
        },
        "attestation": "none",
    })
    .to_string()
}

/// PublicKeyCredentialRequestOptionsJSON for one of `allow`, or with none any passkey of the relying party; its user
/// verified when `user_verified`, else if the authenticator can.
pub fn request_options(rp: &RelyingParty, challenge: &[u8], allow: &[Vec<u8>], user_verified: bool) -> String {
    json!({
        "challenge": B64.encode(challenge),
        "rpId": rp.id,
        "timeout": TIMEOUT.as_millis(),
        "allowCredentials": descriptors(allow),
        "userVerification": if user_verified { "required" } else { "preferred" },
    })
    .to_string()
}

/// Checks the RegistrationResponseJSON of a ceremony that answered `challenge` and verified its user.
pub fn register(rp: &RelyingParty, challenge: &[u8], response: &str) -> Checked<NewCredential> {
    let (id, response) = credential(response)?;
    let client_data = decode(&response.client_data_json)?;
    let object = decode(response.attestation_object.as_deref().ok_or("attestation")?)?;
    let (Cbor::Map(object), []) = cbor(&object, 0)? else {
        return Err("attestation");
    };
    let Some(Cbor::Bytes(auth_data)) = lookup(&object, &Cbor::Text("authData")) else {
        return Err("attestation");
    };
    let flags = check(rp, "webauthn.create", challenge, &client_data, auth_data, true)?;
    if flags & AT == 0 || auth_data.len() < 55 {
        return Err("attested credential");
    }
    let length = usize::from(u16::from_be_bytes([auth_data[53], auth_data[54]]));
    let attested = &auth_data[55..];
    if length > 1023 || attested.len() < length || attested[..length] != id {
        return Err("credential id");
    }
    let (_, extensions) = cbor(&attested[length..], 0)?;
    let public_key = &attested[length..attested.len() - extensions.len()];
    if (flags & ED == 0) != extensions.is_empty() {
        return Err("extensions");
    }
    Key::from_cose(public_key)?;
    Ok(NewCredential {
        id,
        public_key: public_key.to_vec(),
        sign_count: counter(auth_data),
    })
}

/// Parses an AuthenticationResponseJSON.
pub fn assertion(response: &str) -> Checked<Assertion> {
    let (credential_id, response) = credential(response)?;
    let field = |field: Option<&str>| decode(field.ok_or("assertion")?);
    Ok(Assertion {
        credential_id,
        user_handle: response
            .user_handle
            .as_deref()
            .filter(|handle| !handle.is_empty())
            .map(decode)
            .transpose()?,
        client_data: decode(&response.client_data_json)?,
        authenticator_data: field(response.authenticator_data.as_deref())?,
        signature: field(response.signature.as_deref())?,
    })
}

impl Assertion {
    /// Checks that the credential with `public_key` signed `challenge` on the relying party's origin, with its user
    /// verified if `user_verified`, and returns its new signature counter. A counter that does not rise from
    /// `sign_count`, where either is not zero, betrays a cloned authenticator.
    pub fn verify(
        &self,
        rp: &RelyingParty,
        challenge: &[u8],
        public_key: &[u8],
        sign_count: u32,
        user_verified: bool,
    ) -> Checked<u32> {
        let auth_data = &self.authenticator_data;
        check(
            rp,
            "webauthn.get",
            challenge,
            &self.client_data,
            auth_data,
            user_verified,
        )?;
        let message = [&auth_data[..], &Sha256::digest(&self.client_data)[..]].concat();
        if !Key::from_cose(public_key)?.verify(&message, &self.signature) {
            return Err("signature");
        }
        let count = counter(auth_data);
        if (count != 0 || sign_count != 0) && count <= sign_count {
            return Err("counter");
        }
        Ok(count)
    }
}

/// A public key of one of the algorithms photolibd offers.
enum Key<'a> {
    Es256(Vec<u8>),
    Ed25519(&'a [u8]),
    Rs256(&'a [u8], &'a [u8]),
}

impl<'a> Key<'a> {
    fn from_cose(cose: &'a [u8]) -> Checked<Key<'a>> {
        let (Cbor::Map(key), []) = cbor(cose, 0)? else {
            return Err("key");
        };
        let field = |label: i64| lookup(&key, &Cbor::Int(label));
        let bytes = |label: i64| match field(label) {
            Some(Cbor::Bytes(bytes)) => Ok(*bytes),
            _ => Err("key"),
        };
        match (field(1), field(3), field(-1)) {
            (Some(Cbor::Int(2)), Some(Cbor::Int(-7)), Some(Cbor::Int(1))) => {
                let (x, y) = (bytes(-2)?, bytes(-3)?);
                match x.len() == 32 && y.len() == 32 {
                    true => Ok(Key::Es256([&[4][..], x, y].concat())),
                    false => Err("key"),
                }
            }
            (Some(Cbor::Int(1)), Some(Cbor::Int(-8)), Some(Cbor::Int(6))) => match bytes(-2)? {
                x if x.len() == 32 => Ok(Key::Ed25519(x)),
                _ => Err("key"),
            },
            (Some(Cbor::Int(3)), Some(Cbor::Int(-257)), _) => Ok(Key::Rs256(bytes(-1)?, bytes(-2)?)),
            _ => Err("algorithm"),
        }
    }

    fn verify(&self, message: &[u8], signature: &[u8]) -> bool {
        match self {
            Key::Es256(point) => UnparsedPublicKey::new(&ECDSA_P256_SHA256_ASN1, point)
                .verify(message, signature)
                .is_ok(),
            Key::Ed25519(x) => UnparsedPublicKey::new(&ED25519, x).verify(message, signature).is_ok(),
            Key::Rs256(n, e) => RsaPublicKeyComponents { n, e }
                .verify(&RSA_PKCS1_2048_8192_SHA256, message, signature)
                .is_ok(),
        }
    }
}

/// A CBOR item (RFC 8949) of what authenticators send: definite lengths only; arrays, floats and simple values unread.
#[derive(Debug, PartialEq)]
enum Cbor<'a> {
    Int(i64),
    Bytes(&'a [u8]),
    Text(&'a str),
    Map(Vec<(Cbor<'a>, Cbor<'a>)>),
    Other,
}

fn lookup<'a, 'b>(map: &'b [(Cbor<'a>, Cbor<'a>)], key: &Cbor) -> Option<&'b Cbor<'a>> {
    map.iter().find(|(k, _)| k == key).map(|(_, value)| value)
}

/// The first item of `input` and what follows it, nested at most 16 deep.
fn cbor(input: &[u8], depth: usize) -> Checked<(Cbor<'_>, &[u8])> {
    let (&first, rest) = input.split_first().ok_or("cbor")?;
    let (major, info) = (first >> 5, first & 31);
    let size = match info {
        0..24 => 0,
        24..28 => 1 << (info - 24),
        _ => return Err("cbor"),
    };
    if rest.len() < size || depth > 16 {
        return Err("cbor");
    }
    let (argument, mut rest) = rest.split_at(size);
    let n = match size {
        0 => u64::from(info),
        _ => argument.iter().fold(0, |n, &byte| n << 8 | u64::from(byte)),
    };
    // A length, or a count of items that take at least a byte each, cannot exceed what is left.
    let length = usize::try_from(n).ok().filter(|&n| n <= rest.len()).ok_or("cbor");
    let item = match major {
        0 => Cbor::Int(i64::try_from(n).map_err(|_| "cbor")?),
        1 => Cbor::Int(-1 - i64::try_from(n).map_err(|_| "cbor")?),
        2 | 3 => {
            let (bytes, after) = rest.split_at(length?);
            rest = after;
            match major {
                2 => Cbor::Bytes(bytes),
                _ => Cbor::Text(std::str::from_utf8(bytes).map_err(|_| "cbor")?),
            }
        }
        // Arrays (attestation certificates) are skipped.
        4 => {
            for _ in 0..length? {
                rest = cbor(rest, depth + 1)?.1;
            }
            Cbor::Other
        }
        5 => {
            let mut pairs = Vec::with_capacity(length?);
            for _ in 0..n {
                let (key, after) = cbor(rest, depth + 1)?;
                let (value, after) = cbor(after, depth + 1)?;
                pairs.push((key, value));
                rest = after;
            }
            Cbor::Map(pairs)
        }
        6 => return cbor(rest, depth + 1),
        _ => Cbor::Other,
    };
    Ok((item, rest))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;
    use ring::{
        rand::{SecureRandom, SystemRandom},
        signature::{ECDSA_P256_SHA256_ASN1_SIGNING, EcdsaKeyPair, Ed25519KeyPair, KeyPair},
    };

    fn head(major: u8, n: u64) -> Vec<u8> {
        match n {
            0..24 => vec![major << 5 | n as u8],
            24..0x100 => vec![major << 5 | 24, n as u8],
            0x100..0x10000 => [&[major << 5 | 25][..], &(n as u16).to_be_bytes()].concat(),
            _ => [&[major << 5 | 26][..], &(n as u32).to_be_bytes()].concat(),
        }
    }

    fn int(value: i64) -> Vec<u8> {
        match value {
            0.. => head(0, value as u64),
            _ => head(1, (-1 - value) as u64),
        }
    }

    fn bytes(value: &[u8]) -> Vec<u8> {
        [head(2, value.len() as u64), value.to_vec()].concat()
    }

    fn text(value: &str) -> Vec<u8> {
        [head(3, value.len() as u64), value.as_bytes().to_vec()].concat()
    }

    fn map(pairs: &[(Vec<u8>, Vec<u8>)]) -> Vec<u8> {
        let items = pairs.iter().flat_map(|(key, value)| [&key[..], &value[..]].concat());
        [head(5, pairs.len() as u64), items.collect()].concat()
    }

    pub fn b64(bytes: &[u8]) -> String {
        URL_SAFE_NO_PAD.encode(bytes)
    }

    enum Signer {
        Ecdsa(EcdsaKeyPair),
        Eddsa(Ed25519KeyPair),
    }

    /// A passkey provider in software, with one credential, as a platform authenticator makes it.
    pub struct Authenticator {
        signer: Signer,
        pub id: Vec<u8>,
        pub count: u32,
        pub flags: u8,
        pub origin: String,
        pub rp_id: String,
    }

    impl Authenticator {
        /// An ES256 credential for `rp`.
        pub fn new(rp: &RelyingParty) -> Authenticator {
            let rng = SystemRandom::new();
            let alg = &ECDSA_P256_SHA256_ASN1_SIGNING;
            let pkcs8 = EcdsaKeyPair::generate_pkcs8(alg, &rng).unwrap();
            let key = EcdsaKeyPair::from_pkcs8(alg, pkcs8.as_ref(), &rng).unwrap();
            Authenticator::with(rp, Signer::Ecdsa(key))
        }

        fn ed25519(rp: &RelyingParty) -> Authenticator {
            let pkcs8 = Ed25519KeyPair::generate_pkcs8(&SystemRandom::new()).unwrap();
            let key = Ed25519KeyPair::from_pkcs8(pkcs8.as_ref()).unwrap();
            Authenticator::with(rp, Signer::Eddsa(key))
        }

        fn with(rp: &RelyingParty, signer: Signer) -> Authenticator {
            let mut id = vec![0; 16];
            SystemRandom::new().fill(&mut id).unwrap();
            Authenticator {
                signer,
                id,
                count: 0,
                flags: UP | UV,
                origin: rp.origin.clone(),
                rp_id: rp.id.clone(),
            }
        }

        pub fn cose(&self) -> Vec<u8> {
            match &self.signer {
                Signer::Ecdsa(key) => {
                    let point = key.public_key().as_ref();
                    map(&[
                        (int(1), int(2)),
                        (int(3), int(-7)),
                        (int(-1), int(1)),
                        (int(-2), bytes(&point[1..33])),
                        (int(-3), bytes(&point[33..])),
                    ])
                }
                Signer::Eddsa(key) => map(&[
                    (int(1), int(1)),
                    (int(3), int(-8)),
                    (int(-1), int(6)),
                    (int(-2), bytes(key.public_key().as_ref())),
                ]),
            }
        }

        fn client_data(&self, kind: &str, challenge: &[u8]) -> Vec<u8> {
            json!({ "type": kind, "challenge": b64(challenge), "origin": self.origin, "crossOrigin": false })
                .to_string()
                .into_bytes()
        }

        fn auth_data(&self, flags: u8, attested: &[u8]) -> Vec<u8> {
            let rp_hash = Sha256::digest(self.rp_id.as_bytes());
            [&rp_hash[..], &[flags], &self.count.to_be_bytes(), attested].concat()
        }

        fn attestation(&self, flags: u8, cose: &[u8]) -> Vec<u8> {
            let length = (self.id.len() as u16).to_be_bytes();
            let attested = [&[0; 16][..], &length, &self.id, cose].concat();
            map(&[
                (text("fmt"), text("none")),
                (text("attStmt"), map(&[])),
                (text("authData"), bytes(&self.auth_data(flags, &attested))),
            ])
        }

        /// The RegistrationResponseJSON of a `navigator.credentials.create` that answered `challenge`.
        pub fn create(&self, challenge: &[u8]) -> String {
            let client_data = self.client_data("webauthn.create", challenge);
            let object = self.attestation(self.flags | AT, &self.cose());
            self.create_with(&client_data, &object)
        }

        fn create_with(&self, client_data: &[u8], attestation_object: &[u8]) -> String {
            json!({
                "id": b64(&self.id), "rawId": b64(&self.id), "type": "public-key",
                "response": { "clientDataJSON": b64(client_data), "attestationObject": b64(attestation_object) },
                "clientExtensionResults": {}, "authenticatorAttachment": "platform",
            })
            .to_string()
        }

        /// The AuthenticationResponseJSON of a `navigator.credentials.get` that answered `challenge` for the account
        /// whose user handle is `user`, counting a signature.
        pub fn get(&mut self, challenge: &[u8], user: &[u8]) -> String {
            self.count += 1;
            let client_data = self.client_data("webauthn.get", challenge);
            self.get_with(&client_data, &self.auth_data(self.flags, &[]), user)
        }

        fn get_with(&self, client_data: &[u8], auth_data: &[u8], user: &[u8]) -> String {
            let message = [auth_data, &Sha256::digest(client_data)[..]].concat();
            let signature = match &self.signer {
                Signer::Ecdsa(key) => key.sign(&SystemRandom::new(), &message).unwrap().as_ref().to_vec(),
                Signer::Eddsa(key) => key.sign(&message).as_ref().to_vec(),
            };
            json!({
                "id": b64(&self.id), "rawId": b64(&self.id), "type": "public-key",
                "response": {
                    "clientDataJSON": b64(client_data), "authenticatorData": b64(auth_data),
                    "signature": b64(&signature), "userHandle": b64(user),
                },
                "clientExtensionResults": {},
            })
            .to_string()
        }
    }

    pub fn rp() -> RelyingParty {
        RelyingParty {
            id: "photos.example.com".into(),
            origin: "https://photos.example.com".into(),
        }
    }

    #[test]
    fn a_passkey_registers_and_then_signs_in_with_a_rising_counter() {
        let rp = rp();
        let mut passkey = Authenticator::new(&rp);
        let created = register(&rp, b"challenge one", &passkey.create(b"challenge one")).unwrap();
        assert_eq!(
            created,
            NewCredential {
                id: passkey.id.clone(),
                public_key: passkey.cose(),
                sign_count: 0
            }
        );
        let got = assertion(&passkey.get(b"challenge two", b"user")).unwrap();
        assert_eq!(
            (&got.credential_id, &got.user_handle),
            (&passkey.id, &Some(b"user".to_vec()))
        );
        assert_eq!(got.verify(&rp, b"challenge two", &created.public_key, 0, true), Ok(1));
    }

    #[test]
    fn an_ed25519_passkey_and_an_openssl_rs256_signature_verify() {
        let rp = rp();
        let mut passkey = Authenticator::ed25519(&rp);
        let created = register(&rp, b"c", &passkey.create(b"c")).unwrap();
        let got = assertion(&passkey.get(b"d", b"u")).unwrap();
        assert_eq!(got.verify(&rp, b"d", &created.public_key, 0, true), Ok(1));
        // A Windows Hello key: RS256, signed by OpenSSL (`openssl dgst -sha256 -sign`) with a 2048-bit key.
        let hex = |text: &str| {
            (0..text.len())
                .step_by(2)
                .map(|at| u8::from_str_radix(&text[at..at + 2], 16).unwrap())
                .collect::<Vec<u8>>()
        };
        let rsa_key = |n: &[u8]| {
            let e = bytes(&[1, 0, 1]);
            map(&[(int(1), int(3)), (int(3), int(-257)), (int(-1), bytes(n)), (int(-2), e)])
        };
        let cose = rsa_key(&hex(RS256_N));
        let client_data = r#"{"type":"webauthn.get","challenge":"cnMyNTYgY2hhbGxlbmdl","origin":"https://photos.example.com","crossOrigin":false}"#;
        let signed = [&Sha256::digest(b"photos.example.com")[..], &[UP | UV, 0, 0, 0, 7]].concat();
        let response = json!({ "id": "AQ", "rawId": "AQ", "type": "public-key", "response": {
            "clientDataJSON": b64(client_data.as_bytes()), "authenticatorData": b64(&signed),
            "signature": b64(&hex(RS256_SIGNATURE)) } });
        let rsa = assertion(&response.to_string()).unwrap();
        assert_eq!(rsa.user_handle, None);
        assert_eq!(rsa.verify(&rp, b"rs256 challenge", &cose, 6, true), Ok(7));
        assert_eq!(rsa.verify(&rp, b"rs256 challenge", &cose, 7, true), Err("counter"));
        let mut other = hex(RS256_N);
        other[100] ^= 1;
        let wrong_key = rsa.verify(&rp, b"rs256 challenge", &rsa_key(&other), 0, true);
        assert_eq!(wrong_key, Err("signature"));
    }

    const RS256_N: &str = "d809fba21acef339a016491ed353e4b891a800a2f28974b279123aa2e5aa5a56af994ccaeb56cff7c0c1536804cef849f0166ad198f1ae1f9edd6b31a57f491661ce177d3011a56c4c409afe7a14eff6e3333b92de37253740944fa914ce2b64722edd37df25c4e41af176aa58106856565c8352f46d78353215cc95f686a5b54e64fb082d566e5713b1a4773246745b8be739ebdcb8724912d7660c264af710f190d1b7cf1e5bb037c322fc9e1c2550762b1ba305dee6f563b069aaba5797733f672ce2a0466998df8cf2a3cfbd19fbc67e46dd0dc9361bb6a170a5c8841368e479eb741b94f5ddf5864fb851bb55223b197ce2ca7bdced8bd3cf950f2e8dfb";
    const RS256_SIGNATURE: &str = "a5aefddc6cf341efe7d2ba49c9e4701d6fce7bcbbd72ed8c8a3ead60e67127f6768a345be76db648a07434048b22a1d5c8cfdb408671b5a2384c22494e25c86421a1bde1ec8b3c99940940df177b68200b91000e642524d24c3a5da50205add581e975be64feb962cb8f379b7f80a8c27cd5db54251eaade074f0c34a62a6e46e49498f11f744fbc719b08cd1fa4fff2db49c8b1cde9777dac1f4f966ab24ee7a9e4a9fde1b9ae7656436143cbca6361b25a6169d0576f501277e3fb77a83c8a23612c8f28923708c68f61d58160f60658e1c8287787647f6a3fefc6aaffdeac2f9a47b7c5c60260890b11aa43df2f5a58a20e8188f0738e1956d465ffbadfa2";

    #[test]
    fn a_registration_is_refused_for_each_thing_it_gets_wrong() {
        let rp = rp();
        let passkey = Authenticator::new(&rp);
        let other = |change: &dyn Fn(&mut Authenticator)| {
            let mut passkey = Authenticator::new(&rp);
            change(&mut passkey);
            register(&rp, b"c", &passkey.create(b"c"))
        };
        assert_eq!(register(&rp, b"other", &passkey.create(b"c")), Err("challenge"));
        assert_eq!(other(&|p| p.origin = "https://evil.example".into()), Err("origin"));
        assert_eq!(other(&|p| p.rp_id = "example.com".into()), Err("rp"));
        assert_eq!(other(&|p| p.flags = UV), Err("presence"));
        assert_eq!(
            other(&|p| p.flags = UP),
            Err("verification"),
            "a passkey verifies its user"
        );
        let client_data = |kind: &str, origin: &Value| {
            json!({ "type": kind, "challenge": b64(b"c"), "origin": origin })
                .to_string()
                .into_bytes()
        };
        let object = passkey.attestation(UP | UV | AT, &passkey.cose());
        let created =
            |client_data: &[u8], object: &[u8]| register(&rp, b"c", &passkey.create_with(client_data, object));
        let origin = json!(rp.origin);
        let attested = |object: &[u8]| created(&client_data("webauthn.create", &origin), object);
        assert!(attested(&object).is_ok());
        assert_eq!(created(&client_data("webauthn.get", &origin), &object), Err("type"));
        let mut cross: Value = serde_json::from_slice(&client_data("webauthn.create", &origin)).unwrap();
        cross["crossOrigin"] = json!(true);
        assert_eq!(created(cross.to_string().as_bytes(), &object), Err("origin"));
        assert_eq!(
            created(&client_data("webauthn.create", &json!(null)), &object),
            Err("json")
        );
        let unattested = passkey.attestation(UP | UV, &passkey.cose());
        assert_eq!(attested(&unattested), Err("attested credential"));
        let extended = passkey.attestation(UP | UV | AT | ED, &passkey.cose());
        assert_eq!(attested(&extended), Err("extensions"));
        let trailing = passkey.attestation(UP | UV | AT, &[passkey.cose(), map(&[])].concat());
        assert_eq!(attested(&trailing), Err("extensions"));
        let es384 = map(&[(int(1), int(2)), (int(3), int(-35)), (int(-1), int(2))]);
        let unsupported = passkey.attestation(UP | UV | AT, &es384);
        assert_eq!(attested(&unsupported), Err("algorithm"));
        let mut renamed: Value = serde_json::from_str(&passkey.create(b"c")).unwrap();
        renamed["rawId"] = json!(b64(b"someone else's id"));
        assert_eq!(register(&rp, b"c", &renamed.to_string()), Err("credential id"));
        renamed["type"] = json!("password");
        assert_eq!(register(&rp, b"c", &renamed.to_string()), Err("type"));
        assert_eq!(register(&rp, b"c", "{}"), Err("json"));
    }

    #[test]
    fn an_assertion_is_refused_for_each_thing_it_gets_wrong() {
        let rp = rp();
        let mut passkey = Authenticator::new(&rp);
        let key = passkey.cose();
        let check =
            |response: &str, user_verified: bool| assertion(response)?.verify(&rp, b"c", &key, 0, user_verified);
        assert_eq!(check(&passkey.get(b"other", b"u"), false), Err("challenge"));
        passkey.flags = UP;
        assert_eq!(check(&passkey.get(b"c", b"u"), true), Err("verification"));
        assert_eq!(
            check(&passkey.get(b"c", b"u"), false),
            Ok(3),
            "a second factor needs only presence"
        );
        passkey.flags = UP | UV;
        let client_data = |kind: &str, origin: &str| {
            json!({ "type": kind, "challenge": b64(b"c"), "origin": origin })
                .to_string()
                .into_bytes()
        };
        let auth_data = passkey.auth_data(UP | UV, &[]);
        let origin = rp.origin.clone();
        assert_eq!(
            check(
                &passkey.get_with(&client_data("webauthn.create", &origin), &auth_data, b""),
                true
            ),
            Err("type")
        );
        assert_eq!(
            check(
                &passkey.get_with(&client_data("webauthn.get", "https://evil.example"), &auth_data, b""),
                true
            ),
            Err("origin")
        );
        let mut signed: Value =
            serde_json::from_str(&passkey.get_with(&client_data("webauthn.get", &origin), &auth_data, b"")).unwrap();
        assert_eq!(check(&signed.to_string(), true), Ok(3));
        signed["response"]["clientDataJSON"] = json!(b64(&client_data("webauthn.get", &format!("{origin}/"))));
        assert_eq!(check(&signed.to_string(), true), Err("origin"));
        signed["response"]["clientDataJSON"] = json!(b64(&client_data("webauthn.get", &origin)));
        signed["response"]["authenticatorData"] = json!(b64(&passkey.auth_data(UP | UV | 0x08, &[])));
        assert_eq!(
            check(&signed.to_string(), true),
            Err("signature"),
            "the signature covers the flags"
        );
        signed["response"]["authenticatorData"] = json!(b64(&auth_data[..36]));
        assert_eq!(check(&signed.to_string(), true), Err("authenticator data"));
        let verify =
            |response: &str, key: &[u8], count| assertion(response).unwrap().verify(&rp, b"c", key, count, true);
        passkey.rp_id = "example.com".into();
        assert_eq!(verify(&passkey.get(b"c", b"u"), &key, 0), Err("rp"));
        passkey.rp_id = rp.id.clone();
        let response = passkey.get(b"c", b"u");
        let other = Authenticator::new(&rp).cose();
        assert_eq!(verify(&response, &other, 0), Err("signature"));
        assert_eq!(verify(&response, &key, 6), Err("counter"));
        passkey.count = 0;
        let synced = passkey.get_with(
            &passkey.client_data("webauthn.get", b"c"),
            &passkey.auth_data(UP | UV, &[]),
            b"u",
        );
        assert_eq!(verify(&synced, &key, 0), Ok(0), "a synced passkey counts nothing");
        let unsigned = json!({ "id": "AQ", "rawId": "AQ", "type": "public-key", "response": { "clientDataJSON": "" } });
        assert_eq!(assertion(&unsigned.to_string()).err(), Some("assertion"));
        assert_eq!(
            assertion(r#"{"rawId": "*", "type": "public-key", "response": {"clientDataJSON": ""}}"#).err(),
            Some("base64url")
        );
    }

    #[test]
    fn hostile_cbor_fails_without_panicking_or_reserving_memory() {
        let rp = rp();
        let passkey = Authenticator::new(&rp);
        let object = passkey.attestation(UP | UV | AT, &passkey.cose());
        for end in 0..object.len() {
            assert!(cbor(&object[..end], 0).is_err(), "{end}");
        }
        let deep = [vec![0x81; 17], vec![0]].concat();
        assert_eq!(cbor(&deep, 0), Err("cbor"));
        assert!(cbor(&[vec![0x81; 16], vec![0]].concat(), 0).is_ok());
        for huge in [
            &[0x5b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff][..],
            &[0x9b, 0, 0, 0, 1, 0, 0, 0, 0],
            &[0xba, 0xff, 0xff, 0xff, 0xff],
        ] {
            assert_eq!(cbor(huge, 0), Err("cbor"), "{huge:?}");
        }
        assert_eq!(
            cbor(&[0x3b, 0x80, 0, 0, 0, 0, 0, 0, 0], 0),
            Err("cbor"),
            "below i64::MIN"
        );
        assert_eq!(cbor(&[0x5f], 0), Err("cbor"), "an indefinite length");
        assert_eq!(cbor(&[0x62, 0xff, 0xfe], 0), Err("cbor"), "text that is not UTF-8");
        assert_eq!(
            cbor(&[0xc0, 0x01, 0xf5], 0),
            Ok((Cbor::Int(1), &[0xf5][..])),
            "a tag is skipped"
        );
        let mut seed = 0x2545_f491_4f6c_dd1d_u64;
        for _ in 0..20_000 {
            let mut input = object.clone();
            for _ in 0..1 + seed % 4 {
                seed ^= seed << 13;
                seed ^= seed >> 7;
                seed ^= seed << 17;
                let at = (seed >> 8) as usize % input.len();
                input[at] = (seed >> 32) as u8;
            }
            let response = passkey.create_with(&passkey.client_data("webauthn.create", b"c"), &input);
            let _ = register(&rp, b"c", &response);
        }
    }

    #[test]
    fn options_ask_for_a_discoverable_credential_that_verifies_its_user() {
        let rp = rp();
        let created: Value = serde_json::from_str(&creation_options(
            &rp,
            b"challenge",
            b"user",
            "ann",
            "Ann",
            &[b"old".to_vec()],
        ))
        .unwrap();
        let key = |alg: i64| json!({ "type": "public-key", "alg": alg });
        assert_eq!(
            created,
            json!({
                "rp": { "id": "photos.example.com", "name": "Photolib" },
                "user": { "id": b64(b"user"), "name": "ann", "displayName": "Ann" },
                "challenge": b64(b"challenge"),
                "pubKeyCredParams": [key(-8), key(-7), key(-257)],
                "timeout": 300_000,
                "excludeCredentials": [{ "type": "public-key", "id": b64(b"old") }],
                "authenticatorSelection": {
                    "residentKey": "required", "requireResidentKey": true, "userVerification": "required"
                },
                "attestation": "none",
            })
        );
        let request = |allow: &[Vec<u8>], verified| {
            serde_json::from_str::<Value>(&request_options(&rp, b"c", allow, verified)).unwrap()
        };
        assert_eq!(
            request(&[], true),
            json!({
                "challenge": b64(b"c"), "rpId": "photos.example.com", "timeout": 300_000,
                "allowCredentials": [], "userVerification": "required",
            })
        );
        let second = request(&[b"a".to_vec(), b"b".to_vec()], false);
        assert_eq!(second["userVerification"], "preferred");
        assert_eq!(
            second["allowCredentials"],
            json!([{ "type": "public-key", "id": "YQ" }, { "type": "public-key", "id": "Yg" }])
        );
    }

    #[test]
    fn the_public_url_is_an_https_origin_or_localhost_whose_host_passkeys_bind_to() {
        let parsed = |url: &str| RelyingParty::from_url(url).map(|rp| (rp.id, rp.origin));
        let rp = |id: &str, origin: &str| Some((id.to_string(), origin.to_string()));
        assert_eq!(
            parsed("https://photos.example.com"),
            rp("photos.example.com", "https://photos.example.com")
        );
        assert_eq!(
            parsed("HTTPS://Photos.Example.COM:8443/"),
            rp("photos.example.com", "https://photos.example.com:8443")
        );
        assert_eq!(
            parsed("https://photos.example.com:443"),
            rp("photos.example.com", "https://photos.example.com")
        );
        assert_eq!(
            parsed("http://localhost:8080"),
            rp("localhost", "http://localhost:8080")
        );
        for refused in [
            "http://photos.example.com",
            "https://photos.example.com/photolib",
            "https://127.0.0.1",
            "HTTPS://[::1]:8080",
            "https://ann@photos.example.com",
            "https://photos..example.com",
            "https://photos.example.com:",
            "https://photos.example.com:99999",
            "https://",
            "photos.example.com",
            "ftp://photos.example.com",
        ] {
            assert_eq!(parsed(refused), None, "{refused}");
        }
    }
}
