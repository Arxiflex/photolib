//! Local data protection (docs/dev/crypto-v1.md#local-data-protection): the lockbox, which wraps the device data key
//! under each factor that unlocks the device, and sealed journal entries, which locked work writes to the inbox key.

use crate::keys::{DDK, DEVICE_FLOOR, LABEL, check_policy, context, fixed, hkdf, key_id, open_wrap, prefix, seal_wrap};
use crate::proto::kernel::v1::{
    CallError, CallErrorCode, DatabaseKeyRequest, DatabaseKeyResponse, InboxPublicKeyRequest, InboxPublicKeyResponse,
    KeyResponse, LockboxSlot, OpenJournalEntryRequest, OpenJournalEntryResponse, OpenLockboxRequest,
    ReadLockboxRequest, ReadLockboxResponse, SealJournalEntryRequest, SealJournalEntryResponse, SealLockboxRequest,
    SealLockboxResponse,
};
use crate::share::public_key_id;
use crate::{Keyring, Randomness, error, invalid_request, reject};
use hpke::aead::{AeadTag, ChaCha20Poly1305};
use hpke::kdf::HkdfSha256;
use hpke::kem::X25519HkdfSha256;
use hpke::{Deserializable, Kem as _, OpModeR, OpModeS, Serializable};

type Kem = X25519HkdfSha256;
const SLOT: usize = 188;
const PASSCODE: u8 = 2;
const ACCOUNT: u8 = 5;
const JOURNAL_INFO: &[u8] = b"photolib/v1/journal";
const JOURNAL_HEADER: usize = 56;

struct Slot<'a> {
    factor: u8,
    binding: u8,
    user_id: &'a [u8],
    params: &'a [u8],
    wrap: &'a [u8],
}

/// The checked slots of a lockbox.
fn slots(lockbox: &[u8]) -> Result<Vec<Slot<'_>>, CallError> {
    prefix(lockbox, b'L')?;
    if lockbox.len() < 40 {
        return Err(reject("bad_length"));
    }
    let count = usize::from(lockbox[5]);
    if !(1..=8).contains(&count) || lockbox[6..8] != [0, 0] {
        return Err(reject("bad_header"));
    }
    if lockbox.len() != 40 + SLOT * count {
        return Err(reject("bad_length"));
    }
    let slots: Vec<_> = lockbox[40..]
        .chunks(SLOT)
        .map(|s| Slot {
            factor: s[0],
            binding: s[1],
            user_id: &s[2..18],
            params: &s[18..44],
            wrap: &s[44..],
        })
        .collect();
    let zero = |bytes: &[u8]| bytes.iter().all(|&b| b == 0);
    let wrap_header = [b'P', b'L', b'W', 1, 1, DDK, 0, 0];
    for (i, s) in slots.iter().enumerate() {
        if !(1..=5).contains(&s.factor)
            || s.binding > u8::from(s.factor == PASSCODE)
            || s.factor != ACCOUNT && !zero(s.user_id)
            || s.factor != PASSCODE && !zero(s.params)
            || slots[..i]
                .iter()
                .any(|o| o.factor == s.factor && (s.factor != ACCOUNT || o.user_id == s.user_id))
            || s.wrap[..8] != wrap_header
            || s.wrap[24..40] != lockbox[24..40]
        {
            return Err(reject("bad_header"));
        }
    }
    for s in slots.iter().filter(|s| s.factor == PASSCODE) {
        check_policy(s.params, DEVICE_FLOOR)?;
    }
    Ok(slots)
}

fn slot_context(slot: &Slot, device_id: &[u8]) -> Result<[u8; 52], CallError> {
    context([slot.user_id, device_id, &[]], 0)
}

pub fn seal_lockbox(keyring: &Keyring, r: SealLockboxRequest) -> Result<SealLockboxResponse, CallError> {
    let ddk = keyring.key(r.key, "key")?;
    let device_id = fixed::<16>(&r.device_id, "device_id")?;
    let count = u8::try_from(r.slots.len()).unwrap_or(0);
    let mut lockbox = vec![b'P', b'L', b'L', 1, 1, count, 0, 0];
    lockbox.extend_from_slice(&device_id);
    lockbox.extend_from_slice(&key_id(ddk));
    for s in &r.slots {
        let user_id = if s.user_id.is_empty() {
            [0; 16]
        } else {
            fixed(&s.user_id, "slots.user_id")?
        };
        let params = if s.params.is_empty() {
            [0; 26]
        } else {
            fixed(&s.params, "slots.params")?
        };
        let slot = Slot {
            factor: u8::try_from(s.factor).unwrap_or(0),
            binding: u8::from(s.hardware),
            user_id: &user_id,
            params: &params,
            wrap: &s.wrap,
        };
        lockbox.extend_from_slice(&[slot.factor, slot.binding]);
        lockbox.extend_from_slice(&user_id);
        lockbox.extend_from_slice(&params);
        if s.key == 0 {
            lockbox.extend_from_slice(&s.wrap);
        } else {
            let nonce = fixed::<24>(&s.nonce, "slots.nonce")?;
            let key = keyring.key(s.key, "slots.key")?;
            lockbox.extend(seal_wrap(key, ddk, DDK, &slot_context(&slot, &device_id)?, &nonce));
        }
    }
    if let Err(e) = slots(&lockbox) {
        let reason = e.params.get("reason").map_or("", String::as_str);
        return Err(error(
            CallErrorCode::InvalidRequest,
            &[("field", "slots"), ("reason", reason)],
        ));
    }
    Ok(SealLockboxResponse { lockbox })
}

pub fn read_lockbox(r: ReadLockboxRequest) -> Result<ReadLockboxResponse, CallError> {
    let slots = slots(&r.lockbox)?
        .iter()
        .map(|s| LockboxSlot {
            factor: s.factor.into(),
            hardware: s.binding == 1,
            user_id: if s.factor == ACCOUNT {
                s.user_id.to_vec()
            } else {
                Vec::new()
            },
            params: if s.factor == PASSCODE {
                s.params.to_vec()
            } else {
                Vec::new()
            },
            wrap: s.wrap.to_vec(),
            ..LockboxSlot::default()
        })
        .collect();
    Ok(ReadLockboxResponse {
        device_id: r.lockbox[8..24].to_vec(),
        key_id: r.lockbox[24..40].to_vec(),
        slots,
    })
}

pub fn open_lockbox(keyring: &mut Keyring, r: OpenLockboxRequest) -> Result<KeyResponse, CallError> {
    let slots = slots(&r.lockbox)?;
    let slot = usize::try_from(r.slot)
        .ok()
        .and_then(|i| slots.get(i))
        .ok_or_else(|| invalid_request("slot"))?;
    let context = slot_context(slot, &r.lockbox[8..24])?;
    let ddk = open_wrap(keyring.key(r.key, "key")?, slot.wrap, DDK.into(), &context)?;
    Ok(keyring.insert(ddk))
}

/// The page key of a database file, `HKDF(DDK, …/local/db ‖ file_id)`: the one key that leaves the kernel, since
/// SQLite3MultipleCiphers must hold it (ADR-0057).
pub fn database_key(keyring: &Keyring, r: DatabaseKeyRequest) -> Result<DatabaseKeyResponse, CallError> {
    let file_id = fixed::<16>(&r.file_id, "file_id")?;
    let key = hkdf(keyring.key(r.key, "key")?, &[LABEL, b"local/db", &file_id]);
    Ok(DatabaseKeyResponse { page_key: key.to_vec() })
}

pub fn inbox_public_key(keyring: &Keyring, r: InboxPublicKeyRequest) -> Result<InboxPublicKeyResponse, CallError> {
    Ok(InboxPublicKeyResponse {
        public_key: Kem::derive_keypair(keyring.key(r.key, "key")?).1.to_bytes().to_vec(),
    })
}

pub fn seal_entry(mut r: SealJournalEntryRequest) -> Result<SealJournalEntryResponse, CallError> {
    let public_key =
        <Kem as hpke::Kem>::PublicKey::from_bytes(&r.public_key).map_err(|_| invalid_request("public_key"))?;
    let mut randomness = Randomness::take(&mut r.randomness, 32, 0)?;
    let (enc, mut sender) = hpke::setup_sender_with_rng::<ChaCha20Poly1305, HkdfSha256, Kem>(
        &OpModeS::Base,
        &public_key,
        JOURNAL_INFO,
        &mut randomness,
    )
    .map_err(|_| invalid_request("public_key"))?;
    let mut entry = vec![b'P', b'L', b'J', 1, 1, 0, 0, 0];
    entry.extend_from_slice(&public_key_id(&r.public_key));
    entry.extend_from_slice(&enc.to_bytes());
    entry.extend_from_slice(&r.plaintext);
    let (header, body) = entry.split_at_mut(JOURNAL_HEADER);
    let tag = sender
        .seal_inout_detached(body.into(), header)
        .expect("one message is within the HPKE context's limit");
    entry.extend_from_slice(&tag.to_bytes());
    Ok(SealJournalEntryResponse { entry })
}

pub fn open_entry(keyring: &Keyring, r: OpenJournalEntryRequest) -> Result<OpenJournalEntryResponse, CallError> {
    let entry = &r.entry;
    prefix(entry, b'J')?;
    if entry.len() < JOURNAL_HEADER + 16 {
        return Err(reject("bad_length"));
    }
    if entry[5..8] != [0, 0, 0] {
        return Err(reject("bad_header"));
    }
    let (private_key, public_key) = Kem::derive_keypair(keyring.key(r.key, "key")?);
    if public_key_id(&public_key.to_bytes()) != entry[8..24] {
        return Err(reject("wrong_recipient"));
    }
    let failed = |_| reject("auth_failed");
    let enc = <Kem as hpke::Kem>::EncappedKey::from_bytes(&entry[24..JOURNAL_HEADER]).map_err(failed)?;
    let (sealed, tag) = entry[JOURNAL_HEADER..].split_at(entry.len() - JOURNAL_HEADER - 16);
    let tag = AeadTag::<ChaCha20Poly1305>::from_bytes(tag).map_err(failed)?;
    let mut plaintext = sealed.to_vec();
    hpke::single_shot_open_inout_detached::<ChaCha20Poly1305, HkdfSha256, Kem>(
        &OpModeR::Base,
        &private_key,
        &enc,
        JOURNAL_INFO,
        plaintext.as_mut_slice().into(),
        &entry[..JOURNAL_HEADER],
        &tag,
    )
    .map_err(failed)?;
    Ok(OpenJournalEntryResponse { plaintext })
}
