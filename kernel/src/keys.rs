//! Keys in the keyring, their derivations (HKDF-SHA256, Argon2id) and PLW symmetric key wraps
//! (docs/dev/crypto-v1.md#plw-symmetric-key-wrap).

use crate::proto::kernel::v1::{
    CallError, CheckKdfParamsRequest, CheckKdfParamsResponse, DedupTokenRequest, DedupTokenResponse, DeriveKeyRequest,
    DerivePasswordKeyRequest, DropKeyRequest, DropKeyResponse, ImportKeyRequest, KdfPolicy, KeyResponse,
    LinkFragmentRequest, LinkFragmentResponse, LinkKeysRequest, LinkKeysResponse, UnwrapKeyRequest, WrapContext,
    WrapKeyRequest, WrapKeyResponse,
};
use crate::{Keyring, Secret, invalid_request, reject};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use chacha20poly1305::{AeadInOut, KeyInit, Tag, XChaCha20Poly1305, XNonce};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;
use unicode_normalization::UnicodeNormalization;
use zeroize::{Zeroize, Zeroizing};

pub const LABEL: &[u8] = b"photolib/v1/";
pub const DEVICE_FLOOR: u32 = 65_536;
const ACCOUNT_FLOOR: u32 = 131_072;
const WRAP: usize = 144;
/// The wrapped type of a DeviceDataKey.
pub const DDK: u8 = 12;
const OK: &str = "HKDF-SHA256 expands 16 and 32 bytes";

/// HKDF-SHA256 with an empty salt; `info` is concatenated.
pub fn hkdf(ikm: &[u8], info: &[&[u8]]) -> Secret {
    let mut out = Secret::default();
    Hkdf::<Sha256>::new(None, ikm)
        .expand_multi_info(info, &mut out[..])
        .expect(OK);
    out
}

pub fn key_id(key: &[u8; 32]) -> [u8; 16] {
    let mut id = [0; 16];
    Hkdf::<Sha256>::new(None, key)
        .expand(b"photolib/v1/key-id", &mut id)
        .expect(OK);
    id
}

/// Steps 1 and 2 of every reader: length, magic, type, version and suite.
pub fn prefix(object: &[u8], typ: u8) -> Result<(), CallError> {
    let reason = if object.len() < 8 {
        "bad_length"
    } else if object[..2] != *b"PL" {
        "bad_magic"
    } else if object[2] != typ {
        "wrong_type"
    } else if object[3] != 1 {
        "unsupported_version"
    } else if object[4] != 1 {
        "unsupported_suite"
    } else {
        return Ok(());
    };
    Err(reject(reason))
}

pub fn import(keyring: &mut Keyring, mut r: ImportKeyRequest) -> Result<KeyResponse, CallError> {
    let secret = fixed::<32>(&r.secret, "secret");
    r.secret.zeroize();
    Ok(keyring.insert(Box::new(Zeroizing::new(secret?))))
}

pub fn drop(keyring: &mut Keyring, r: DropKeyRequest) -> Result<DropKeyResponse, CallError> {
    keyring
        .keys
        .remove(&r.key)
        .map(|_| DropKeyResponse {})
        .ok_or_else(|| invalid_request("key"))
}

pub fn derive(keyring: &mut Keyring, r: DeriveKeyRequest) -> Result<KeyResponse, CallError> {
    let key = hkdf(keyring.key(r.key, "key")?, &[LABEL, r.label.as_bytes(), &r.context]);
    Ok(keyring.insert(key))
}

pub fn derive_password(keyring: &mut Keyring, mut r: DerivePasswordKeyRequest) -> Result<KeyResponse, CallError> {
    let password = nfc(&mut r.password);
    let hardware = Zeroizing::new(std::mem::take(&mut r.hardware));
    let stretched = argon2id(password.as_bytes(), &r.params)?;
    let key = if r.label.is_empty() {
        if !hardware.is_empty() {
            return Err(invalid_request("hardware"));
        }
        stretched
    } else {
        let ikm = Zeroizing::new([&stretched[..], &hardware].concat());
        hkdf(&ikm, &[LABEL, r.label.as_bytes()])
    };
    Ok(keyring.insert(key))
}

/// `HMAC-SHA256(DedupKey, SHA-256(original))`.
pub fn dedup_token(keyring: &Keyring, r: DedupTokenRequest) -> Result<DedupTokenResponse, CallError> {
    let digest = fixed::<32>(&r.sha256, "sha256")?;
    let mut mac = Hmac::<Sha256>::new_from_slice(keyring.key(r.key, "key")?).expect("any length");
    mac.update(&digest);
    Ok(DedupTokenResponse {
        token: mac.finalize().into_bytes().to_vec(),
    })
}

/// `LinkKey = HKDF(LinkSecret ‖ password_hash, …/link/key ‖ link_id)`, and the verifier `SHA-256(LinkAuth)`.
pub fn link_keys(keyring: &mut Keyring, r: LinkKeysRequest) -> Result<LinkKeysResponse, CallError> {
    let link_id = fixed::<16>(&r.link_id, "link_id")?;
    let secret = keyring.key(r.secret, "secret")?;
    let auth = hkdf(secret, &[LABEL, b"link/auth", &link_id]);
    let ikm = Zeroizing::new(match r.password_hash {
        0 => secret.to_vec(),
        hash => [&secret[..], keyring.key(hash, "password_hash")?].concat(),
    });
    let KeyResponse { key, key_id } = keyring.insert(hkdf(&ikm, &[LABEL, b"link/key", &link_id]));
    Ok(LinkKeysResponse {
        key,
        key_id,
        verifier: Sha256::digest(&auth[..]).to_vec(),
    })
}

pub fn link_fragment(r: LinkFragmentRequest) -> Result<LinkFragmentResponse, CallError> {
    let mut parts = vec![
        "v1".to_string(),
        URL_SAFE_NO_PAD.encode(fixed::<16>(&r.link_id, "link_id")?),
        URL_SAFE_NO_PAD.encode(fixed::<32>(&r.secret, "secret")?),
    ];
    if r.password {
        parts.push("p".into());
    }
    if !r.manifest.is_empty() {
        parts.push(URL_SAFE_NO_PAD.encode(&Sha256::digest(&r.manifest)[..8]));
    }
    Ok(LinkFragmentResponse {
        fragment: parts.join("."),
    })
}

/// The NFC of a password as UTF-8, zeroizing the original. NFC grows UTF-8 at most threefold: reserving that, no copy
/// of the password is left behind by a reallocation.
pub fn nfc(password: &mut String) -> Zeroizing<String> {
    let mut nfc = Zeroizing::new(String::with_capacity(3 * password.len()));
    nfc.extend(password.nfc());
    password.zeroize();
    nfc
}

/// The m and t of a 26-byte parameter set `alg ‖ m_kib ‖ t ‖ p ‖ salt` that the kernel runs: one lane, at most 2 GiB
/// and 64 passes.
pub fn argon2_params(params: &[u8]) -> Result<(u32, u32), CallError> {
    let (m, t) = parse_params(params)?;
    if m > 2_097_152 || t > 64 {
        return Err(reject("kdf_params_rejected"));
    }
    Ok((m, t))
}

/// Argon2id v1.3 with one lane, filling `out`.
pub fn argon2id_into(password: &[u8], salt: &[u8], (m, t): (u32, u32), out: &mut [u8]) -> Result<(), argon2::Error> {
    let params = Params::new(m, t, 1, Some(out.len()))?;
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params).hash_password_into(password, salt, out)
}

fn argon2id(password: &[u8], params: &[u8]) -> Result<Secret, CallError> {
    let cost = argon2_params(params)?;
    let mut out = Secret::default();
    argon2id_into(password, &params[10..], cost, &mut out[..]).map_err(|_| reject("kdf_params_rejected"))?;
    Ok(out)
}

fn parse_params(params: &[u8]) -> Result<(u32, u32), CallError> {
    if params.len() != 26 || params[0] != 1 || params[9] != 1 {
        return Err(reject("kdf_params_rejected"));
    }
    let word = |at: usize| u32::from_be_bytes([params[at], params[at + 1], params[at + 2], params[at + 3]]);
    Ok((word(1), word(5)))
}

/// The account and device policies: `floor ≤ m ≤ 2 GiB`, 3 to 64 passes, one lane, a 16-byte salt.
pub fn check_policy(params: &[u8], floor: u32) -> Result<(), CallError> {
    let (m, t) = parse_params(params)?;
    if (floor..=2_097_152).contains(&m) && (3..=64).contains(&t) {
        Ok(())
    } else {
        Err(reject("kdf_params_rejected"))
    }
}

pub fn check_params(r: CheckKdfParamsRequest) -> Result<CheckKdfParamsResponse, CallError> {
    let floor = match r.policy() {
        KdfPolicy::Account => ACCOUNT_FLOOR,
        KdfPolicy::Device => DEVICE_FLOOR,
        KdfPolicy::Unspecified => return Err(invalid_request("policy")),
    };
    check_policy(&r.params, floor).map(|()| CheckKdfParamsResponse {})
}

/// `user_id ‖ container_id ‖ subject_id ‖ number`; empty ids are zero.
pub fn context(ids: [&[u8]; 3], number: u32) -> Result<[u8; 52], CallError> {
    let mut out = [0; 52];
    for (at, (id, field)) in ids
        .into_iter()
        .zip(["context.user_id", "context.container_id", "context.subject_id"])
        .enumerate()
    {
        if !id.is_empty() {
            out[16 * at..16 * at + 16].copy_from_slice(&fixed::<16>(id, field)?);
        }
    }
    out[48..].copy_from_slice(&number.to_be_bytes());
    Ok(out)
}

pub fn wrap_context(c: Option<WrapContext>) -> Result<[u8; 52], CallError> {
    let c = c.unwrap_or_default();
    context([&c.user_id, &c.container_id, &c.subject_id], c.number)
}

/// A field that must be exactly `N` bytes.
pub fn fixed<const N: usize>(bytes: &[u8], field: &str) -> Result<[u8; N], CallError> {
    bytes.try_into().map_err(|_| invalid_request(field))
}

pub fn wrapped_type(wrapped_type: u32) -> Result<u8, CallError> {
    u8::try_from(wrapped_type)
        .ok()
        .filter(|t| (1..=12).contains(t))
        .ok_or_else(|| invalid_request("wrapped_type"))
}

pub fn wrap(keyring: &mut Keyring, r: WrapKeyRequest) -> Result<WrapKeyResponse, CallError> {
    let wrapped_type = wrapped_type(r.wrapped_type)?;
    let context = wrap_context(r.context)?;
    let nonce = fixed::<24>(&r.nonce, "nonce")?;
    Ok(WrapKeyResponse {
        wrap: seal_wrap(
            keyring.key(r.wrapping_key, "wrapping_key")?,
            keyring.key(r.key, "key")?,
            wrapped_type,
            &context,
            &nonce,
        ),
    })
}

pub fn unwrap(keyring: &mut Keyring, r: UnwrapKeyRequest) -> Result<KeyResponse, CallError> {
    let context = wrap_context(r.context)?;
    let key = open_wrap(
        keyring.key(r.wrapping_key, "wrapping_key")?,
        &r.wrap,
        r.wrapped_type,
        &context,
    )?;
    Ok(keyring.insert(key))
}

/// The encryption key and the commitment of a wrap: `PRK = HKDF-Extract(nonce, wrapping_key)`.
fn wrap_keys(wrapping_key: &[u8; 32], nonce: &[u8]) -> (XChaCha20Poly1305, [u8; 32]) {
    let hkdf = Hkdf::<Sha256>::new(Some(nonce), wrapping_key);
    let (mut key, mut commitment) = (Zeroizing::new([0; 32]), [0; 32]);
    hkdf.expand(b"photolib/v1/plw/key", &mut key[..]).expect(OK);
    hkdf.expand(b"photolib/v1/plw/commit", &mut commitment).expect(OK);
    (XChaCha20Poly1305::new(&(*key).into()), commitment)
}

pub fn seal_wrap(
    wrapping_key: &[u8; 32],
    key: &[u8; 32],
    wrapped_type: u8,
    context: &[u8; 52],
    nonce: &[u8; 24],
) -> Vec<u8> {
    let (cipher, commitment) = wrap_keys(wrapping_key, nonce);
    let mut wrap = Vec::with_capacity(WRAP);
    wrap.extend_from_slice(&[b'P', b'L', b'W', 1, 1, wrapped_type, 0, 0]);
    for part in [&key_id(wrapping_key)[..], &key_id(key), nonce, &commitment, key] {
        wrap.extend_from_slice(part);
    }
    let aad = [&wrap[..96], context].concat();
    let tag = cipher
        .encrypt_inout_detached(&XNonce::from(*nonce), &aad, (&mut wrap[96..]).into())
        .expect("a 32-byte key is within XChaCha20-Poly1305's limits");
    wrap.extend_from_slice(&tag);
    wrap
}

/// The checks of a PLW or PLH before opening it: prefix, length, wrapped type and reserved bytes.
pub fn wrap_header(wrap: &[u8], typ: u8, length: usize) -> Result<(), CallError> {
    prefix(wrap, typ)?;
    if wrap.len() != length {
        return Err(reject("bad_length"));
    }
    if !(1..=12).contains(&wrap[5]) || wrap[6..8] != [0, 0] {
        return Err(reject("bad_header"));
    }
    Ok(())
}

/// The checks after opening a wrap: the key matches the key id at `at`, and the wrapped type is the one asked for.
pub fn opened(key: &[u8; 32], wrap: &[u8], at: usize, wrapped_type: u32) -> Result<(), CallError> {
    if key_id(key) != wrap[at..at + 16] {
        return Err(reject("bad_key_id"));
    }
    if u32::from(wrap[5]) != wrapped_type {
        return Err(reject("wrong_kind"));
    }
    Ok(())
}

pub fn open_wrap(
    wrapping_key: &[u8; 32],
    wrap: &[u8],
    wrapped_type: u32,
    context: &[u8; 52],
) -> Result<Secret, CallError> {
    wrap_header(wrap, b'W', WRAP)?;
    let (cipher, commitment) = wrap_keys(wrapping_key, &wrap[40..64]);
    if !bool::from(commitment.ct_eq(&wrap[64..96])) {
        return Err(reject("commitment_mismatch"));
    }
    let mut key = Secret::default();
    key.copy_from_slice(&wrap[96..128]);
    let aad = [&wrap[..96], context].concat();
    let nonce = XNonce::from(fixed::<24>(&wrap[40..64], "wrap")?);
    let tag = Tag::from(fixed::<16>(&wrap[128..], "wrap")?);
    cipher
        .decrypt_inout_detached(&nonce, &aad, (&mut key[..]).into(), &tag)
        .map_err(|_| reject("auth_failed"))?;
    opened(&key, wrap, 24, wrapped_type)?;
    Ok(key)
}
