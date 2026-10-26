//! Public-key wraps (docs/dev/crypto-v1.md#plh-public-key-wrap): the public keys of seeds in the keyring, and PLH,
//! HPKE base mode with X-Wing, which a recipient opens only when a verified log entry names its SHA-256.

use crate::keys::{fixed, key_id, opened, wrap_context, wrap_header, wrapped_type};
use crate::proto::kernel::v1::{
    AcceptKeyRequest, CallError, KeyPair, KeyResponse, PublicKeyRequest, PublicKeyResponse, ShareKeyRequest,
    ShareKeyResponse,
};
use crate::{Keyring, Randomness, Secret, invalid_request, reject};
use ed25519_dalek::SigningKey;
use hpke::aead::{AeadTag, ChaCha20Poly1305};
use hpke::kdf::HkdfSha256;
use hpke::kem::XWing;
use hpke::{Deserializable, Kem, OpModeR, OpModeS, Serializable};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

const PLH: usize = 1224;
const HEADER: usize = 56;
const INFO: &[u8] = b"photolib/v1/plh";

/// `pk_id(pk) = SHA-256(pk)[0..16)`.
pub fn public_key_id(public_key: &[u8]) -> [u8; 16] {
    fixed(&Sha256::digest(public_key)[..16], "public_key").expect("16 of SHA-256's 32 bytes")
}

/// The X-Wing key pair of a 32-byte decapsulation key seed.
fn x_wing(seed: &[u8; 32]) -> (<XWing as Kem>::PrivateKey, <XWing as Kem>::PublicKey) {
    let private = <XWing as Kem>::PrivateKey::from_bytes(seed).expect("32 bytes");
    let public = XWing::sk_to_pk(&private);
    (private, public)
}

pub fn public_key(keyring: &Keyring, r: PublicKeyRequest) -> Result<PublicKeyResponse, CallError> {
    let seed = keyring.key(r.key, "key")?;
    let public_key = match r.key_pair() {
        KeyPair::Ed25519 => SigningKey::from_bytes(seed).verifying_key().to_bytes().to_vec(),
        KeyPair::XWing => x_wing(seed).1.to_bytes().to_vec(),
        KeyPair::Unspecified => return Err(invalid_request("key_pair")),
    };
    Ok(PublicKeyResponse {
        key_id: public_key_id(&public_key).to_vec(),
        public_key,
    })
}

pub fn share(keyring: &Keyring, mut r: ShareKeyRequest) -> Result<ShareKeyResponse, CallError> {
    let wrapped_type = wrapped_type(r.wrapped_type)?;
    let info = [INFO, &wrap_context(r.context)?].concat();
    let key = keyring.key(r.key, "key")?;
    let recipient = <XWing as Kem>::PublicKey::from_bytes(&r.public_key).map_err(|_| invalid_request("public_key"))?;
    let sender = match r.sender_key_id.len() {
        0 => [0; 16],
        _ => fixed(&r.sender_key_id, "sender_key_id")?,
    };
    let mut randomness = Randomness::take(&mut r.randomness, 64, 0)?;
    let mut wrap = Vec::with_capacity(PLH);
    wrap.extend_from_slice(&[b'P', b'L', b'H', 1, 1, wrapped_type, 0, 0]);
    for part in [&public_key_id(&r.public_key), &sender, &key_id(key)] {
        wrap.extend_from_slice(part);
    }
    let mut sealed: Secret = Box::new(Zeroizing::new(*key));
    let (enc, tag) = hpke::single_shot_seal_inout_detached_with_rng::<ChaCha20Poly1305, HkdfSha256, XWing>(
        &OpModeS::Base,
        &recipient,
        &info,
        (&mut sealed[..]).into(),
        &wrap,
        &mut randomness,
    )
    .expect("one message is within the HPKE context's limit");
    wrap.extend_from_slice(&enc.to_bytes());
    wrap.extend_from_slice(&sealed[..]);
    wrap.extend_from_slice(&tag.to_bytes());
    Ok(ShareKeyResponse { wrap })
}

pub fn accept(keyring: &mut Keyring, r: AcceptKeyRequest) -> Result<KeyResponse, CallError> {
    let wrap = &r.wrap;
    if Sha256::digest(wrap)[..] != r.signed_sha256[..] {
        return Err(reject("unsigned_wrap"));
    }
    let info = [INFO, &wrap_context(r.context)?].concat();
    wrap_header(wrap, b'H', PLH)?;
    let (private, public) = x_wing(keyring.key(r.key, "key")?);
    if public_key_id(&public.to_bytes()) != wrap[8..24] {
        return Err(reject("wrong_recipient"));
    }
    let failed = |_| reject("auth_failed");
    let enc = <XWing as Kem>::EncappedKey::from_bytes(&wrap[HEADER..PLH - 48]).map_err(failed)?;
    let tag = AeadTag::<ChaCha20Poly1305>::from_bytes(&wrap[PLH - 16..]).map_err(failed)?;
    let mut key = Secret::default();
    key.copy_from_slice(&wrap[PLH - 48..PLH - 16]);
    hpke::single_shot_open_inout_detached::<ChaCha20Poly1305, HkdfSha256, XWing>(
        &OpModeR::Base,
        &private,
        &enc,
        &info,
        (&mut key[..]).into(),
        &wrap[..HEADER],
        &tag,
    )
    .map_err(failed)?;
    opened(&key, wrap, 40, r.wrapped_type)?;
    Ok(keyring.insert(key))
}
