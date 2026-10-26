//! PLS signed statements and logs (docs/dev/crypto-v1.md#pls-signed-statements-and-logs): entries signed with an
//! Ed25519 seed in the keyring, and readers that replay identity and membership logs and check upload statements, with
//! the specification's checks in its order under strict Ed25519; and the codes users compare out of band.

use crate::keys::fixed;
use crate::proto::kernel::v1::{
    CallError, Checkpoint, CodeResponse, Device, EpochCodeRequest, Link, Member, SafetyNumberRequest, SignEntryRequest,
    SignEntryResponse, SignedWrap, Upload, VerifyIdentityLogRequest, VerifyIdentityLogResponse,
    VerifyMembershipLogRequest, VerifyMembershipLogResponse,
};
use crate::share::public_key_id;
use crate::{Keyring, invalid_request, reject};
use curve25519_dalek::edwards::CompressedEdwardsY;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use sha2::{Digest, Sha256, Sha512};
use std::collections::{BTreeMap, BTreeSet};

/// The fixed header, before the body, and the signature after it.
const HEADER: usize = 92;
const SIGNATURE: usize = 64;
const ZERO: [u8; 32] = [0; 32];
const ADMIN: u8 = 3;
const CONTRIBUTOR: u8 = 2;

struct Entry<'a> {
    bytes: &'a [u8],
    log_type: u8,
    body_type: u16,
    signer: &'a [u8],
    log_id: &'a [u8],
    seq: u64,
    prev_hash: &'a [u8],
    body: &'a [u8],
}

fn number(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0, |n, &b| n << 8 | u64::from(b))
}

fn parse(bytes: &[u8]) -> Result<Entry<'_>, CallError> {
    crate::keys::prefix(bytes, b'S')?;
    if bytes.len() < HEADER + SIGNATURE || bytes.len() as u64 != (HEADER + SIGNATURE) as u64 + number(&bytes[88..92]) {
        return Err(reject("bad_length"));
    }
    if !(1..=4).contains(&bytes[5]) {
        return Err(reject("bad_header"));
    }
    Ok(Entry {
        bytes,
        log_type: bytes[5],
        body_type: number(&bytes[6..8]) as u16,
        signer: &bytes[8..24],
        log_id: &bytes[24..40],
        seq: number(&bytes[40..48]),
        prev_hash: &bytes[48..80],
        body: &bytes[HEADER..bytes.len() - SIGNATURE],
    })
}

fn hash(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}

fn chain(e: &Entry, log_type: u8, log_id: &[u8], seq: u64, prev: &[u8]) -> Result<(), CallError> {
    if e.log_type != log_type || e.log_id != log_id || e.seq != seq || e.prev_hash != prev {
        return Err(reject("broken_chain"));
    }
    Ok(())
}

/// Strict Ed25519: a canonical public key and `R`, neither of small order, `S < L`, and the cofactorless equation.
fn verify(e: &Entry, public_key: &[u8]) -> Result<(), CallError> {
    let (message, signature) = e.bytes.split_at(e.bytes.len() - SIGNATURE);
    let signature = Signature::from_bytes(signature.try_into().expect("64 bytes"));
    let canonical =
        |key: &[u8; 32]| (CompressedEdwardsY(*key).decompress()).is_some_and(|point| point.compress().0 == *key);
    <[u8; 32]>::try_from(public_key)
        .ok()
        .filter(canonical)
        .and_then(|key| VerifyingKey::from_bytes(&key).ok())
        .filter(|key| key.verify_strict(message, &signature).is_ok())
        .map(drop)
        .ok_or_else(|| reject("bad_signature"))
}

/// The body, if the body type is defined here (`size` gives its exact length) and the body has that length.
fn body<'a>(e: &Entry<'a>, size: Option<usize>) -> Result<&'a [u8], CallError> {
    if size == Some(e.body.len()) {
        Ok(e.body)
    } else {
        Err(reject("invalid_entry"))
    }
}

/// A reader refuses a view without its checkpoint: the server cannot roll a log back or show a fork.
fn checkpoint(entries: &[Vec<u8>], checkpoint: Option<Checkpoint>) -> Result<(), CallError> {
    let seen = checkpoint.map(|c| {
        usize::try_from(c.seq)
            .ok()
            .and_then(|seq| entries.get(seq))
            .is_some_and(|e| hash(e)[..] == c.entry_hash[..])
    });
    if seen == Some(false) {
        return Err(reject("rollback"));
    }
    if entries.is_empty() {
        return Err(invalid_request("entries"));
    }
    Ok(())
}

fn head(entries: &[Vec<u8>], hash: [u8; 32]) -> Option<Checkpoint> {
    Some(Checkpoint {
        seq: entries.len() as u64 - 1,
        entry_hash: hash.to_vec(),
    })
}

fn wrap(seq: usize, recipient_id: &[u8], sha256: &[u8]) -> SignedWrap {
    SignedWrap {
        seq: seq as u64,
        recipient_id: recipient_id.to_vec(),
        sha256: sha256.to_vec(),
    }
}

pub fn sign(keyring: &Keyring, r: SignEntryRequest) -> Result<SignEntryResponse, CallError> {
    let key = SigningKey::from_bytes(keyring.key(r.key, "key")?);
    let log_type = u8::try_from(r.log_type)
        .ok()
        .filter(|t| (1..=4).contains(t))
        .ok_or_else(|| invalid_request("log_type"))?;
    let body_type = u16::try_from(r.body_type).map_err(|_| invalid_request("body_type"))?;
    let prev_hash = match r.prev_hash.len() {
        0 => ZERO,
        _ => fixed(&r.prev_hash, "prev_hash")?,
    };
    let body_len = u32::try_from(r.body.len()).map_err(|_| invalid_request("body"))?;
    let mut entry = [
        &[b'P', b'L', b'S', 1, 1, log_type][..],
        &body_type.to_be_bytes(),
        &public_key_id(key.verifying_key().as_bytes()),
        &fixed::<16>(&r.log_id, "log_id")?,
        &r.seq.to_be_bytes(),
        &prev_hash,
        &r.time_ms.to_be_bytes(),
        &body_len.to_be_bytes(),
        &r.body,
    ]
    .concat();
    let signature = key.sign(&entry);
    entry.extend_from_slice(&signature.to_bytes());
    Ok(SignEntryResponse { entry })
}

/// The length of an identity body type: genesis only at entry 0, the others only after it.
fn identity_size(body_type: u16, first: bool) -> Option<usize> {
    match (body_type, first) {
        (1, true) => Some(32 + 1216),
        (2, false) => Some(1216),
        (3, false) => Some(33),
        (4, false) => Some(16 + 1216 + 32),
        (5, false) => Some(16),
        (6, false) => Some(4),
        _ => None,
    }
}

pub fn verify_identity(r: VerifyIdentityLogRequest) -> Result<VerifyIdentityLogResponse, CallError> {
    let user_id = fixed::<16>(&r.user_id, "user_id")?;
    checkpoint(&r.entries, r.checkpoint)?;
    let mut state = VerifyIdentityLogResponse::default();
    let mut prev = ZERO;
    for (seq, bytes) in r.entries.iter().enumerate() {
        let e = parse(bytes)?;
        chain(&e, 1, &user_id, seq as u64, &prev)?;
        if seq == 0 {
            // The first body names the key that signs it.
            let genesis = body(&e, identity_size(e.body_type, true))?;
            state.signing_keys.push(genesis[..32].to_vec());
            state.encryption_key = genesis[32..].to_vec();
        }
        let signer = state.signing_keys.last().expect("entry 0 names one");
        if public_key_id(signer) != e.signer {
            return Err(reject("unauthorized"));
        }
        verify(&e, signer)?;
        let body = body(&e, identity_size(e.body_type, seq == 0))?;
        let devices = &mut state.devices;
        let known = (body.get(..16)).and_then(|id| devices.iter().position(|d| d.device_id == id));
        match (e.body_type, known) {
            (2, _) => state.encryption_key = body.to_vec(),
            (3, _) if body[0] == 1 => state.signing_keys.push(body[1..].to_vec()),
            (4, None) => {
                devices.push(Device {
                    device_id: body[..16].to_vec(),
                    public_key: body[16..1232].to_vec(),
                });
                state.wraps.push(wrap(seq, &body[..16], &body[1232..]));
            }
            (5, Some(device)) => {
                devices.remove(device);
            }
            (6, _) if number(body) == u64::from(state.amk_generation) + 1 => state.amk_generation += 1,
            (1, _) => {}
            _ => return Err(reject("invalid_entry")),
        }
        prev = hash(bytes);
    }
    state.head = head(&r.entries, prev);
    Ok(state)
}

/// A membership log's state after an entry.
#[derive(Clone, Default)]
struct Membership<'a> {
    owner: &'a [u8],
    /// Role and pinned signing key id, by user.
    members: BTreeMap<&'a [u8], (u8, &'a [u8])>,
    epoch: u32,
    rotation_due: bool,
    /// The drop key, empty until set, by link.
    links: BTreeMap<&'a [u8], &'a [u8]>,
    head: [u8; 32],
}

/// Each user's signing keys from a verified identity log, oldest first.
type Directory<'a> = BTreeMap<&'a [u8], &'a [Vec<u8>]>;

/// Where a key id is among a user's signing keys.
fn key_index(directory: &Directory, user: &[u8], key_id: &[u8]) -> Option<usize> {
    let keys = directory.get(user)?;
    keys.iter().position(|k| public_key_id(k) == key_id)
}

/// The member whose pinned key signed an entry, and that key.
fn signer<'a>(state: &Membership<'a>, e: &Entry, directory: &Directory<'a>) -> Result<(&'a [u8], &'a [u8]), CallError> {
    let (user, (_, key_id)) = state
        .members
        .iter()
        .find(|(_, (_, key_id))| *key_id == e.signer)
        .ok_or_else(|| reject("unauthorized"))?;
    let key = key_index(directory, user, key_id).ok_or_else(|| reject("unauthorized"))?;
    Ok((user, &directory[user][key]))
}

fn membership_size(body_type: u16, body: &[u8]) -> Option<usize> {
    match body_type {
        2 => Some(65),
        3 | 7 => Some(16),
        4 | 6 => Some(17),
        5 if body.len() >= 38 => Some(38 + 48 * number(&body[36..38]) as usize),
        8 => Some(16 + 1216),
        9 => Some(32),
        _ => None,
    }
}

/// Applies an entry after `create`: its body, the signer's role, a due rotation, then the rules of its type.
fn apply<'a>(
    state: &mut Membership<'a>,
    e: &Entry<'a>,
    signer: &[u8],
    directory: &Directory,
    wraps: &mut Vec<SignedWrap>,
    seq: usize,
) -> Result<(), CallError> {
    let invalid = || Err(reject("invalid_entry"));
    let body = body(e, membership_size(e.body_type, e.body))?;
    let (user, kind) = (&body[..16], e.body_type);
    if state.members[signer].0 != ADMIN && !(kind == 9 && user == signer) {
        return Err(reject("unauthorized"));
    }
    if state.rotation_due && kind != 3 && kind != 5 {
        return invalid();
    }
    let member = state.members.get(user).copied();
    match kind {
        2 => {
            if member.is_some() || key_index(directory, user, &body[16..32]).is_none() || !(1..=3).contains(&body[32]) {
                return invalid();
            }
            state.members.insert(user, (body[32], &body[16..32]));
            wraps.push(wrap(seq, user, &body[33..]));
        }
        3 | 4 | 9 => {
            let Some((role, key_id)) = member.filter(|_| user != state.owner || kind == 9) else {
                return invalid();
            };
            if kind == 3 {
                state.members.remove(user);
            } else if kind == 4 && (1..=3).contains(&body[16]) {
                state.members.insert(user, (body[16], key_id));
            } else if kind == 9
                && key_index(directory, user, &body[16..])
                    .is_some_and(|new| Some(new) > key_index(directory, user, key_id))
            {
                state.members.insert(user, (role, &body[16..]));
            } else {
                return invalid();
            }
        }
        5 => {
            let users: BTreeSet<_> = body[38..].chunks(48).map(|w| &w[..16]).collect();
            let others = state.members.keys().copied().filter(|&m| m != signer);
            if number(&body[..4]) != u64::from(state.epoch) + 1
                || users.len() * 48 != body.len() - 38
                || users != others.collect::<BTreeSet<_>>()
            {
                return invalid();
            }
            wraps.push(wrap(seq, &[], &body[4..36]));
            for w in body[38..].chunks(48) {
                wraps.push(wrap(seq, &w[..16], &w[16..]));
            }
        }
        6 if !state.links.contains_key(user) && body[16] & !7 == 0 => {
            state.links.insert(user, &[]);
        }
        7 if state.links.remove(user).is_some() => {}
        8 if state.links.contains_key(user) => {
            state.links.insert(user, &body[16..]);
        }
        _ => return invalid(),
    }
    state.epoch += u32::from(kind == 5);
    state.rotation_due = (state.rotation_due || kind == 3) && kind != 5;
    Ok(())
}

/// The checks of an upload statement that need no log: its layout, chain fields and body. Gives the log position it
/// names.
fn statement<'a>(bytes: &'a [u8], log_id: &[u8]) -> Result<(Entry<'a>, u64), CallError> {
    let e = parse(bytes)?;
    chain(&e, 4, log_id, 0, &ZERO)?;
    let body = body(&e, (e.body_type == 1).then_some(92))?;
    let seq = number(&body[20..28]);
    Ok((e, seq))
}

/// The rest: the named head is the reader's, the signer was a member there and signed, the epoch was current with no
/// rotation due, and the signer may upload both there and at the reader's head.
fn upload(e: &Entry, at: Option<&Membership>, head: &Membership, directory: &Directory) -> Result<Upload, CallError> {
    let body = e.body;
    let Some(at) = at.filter(|at| at.head[..] == body[28..60]) else {
        return Err(reject("invalid_entry"));
    };
    let (signer, key) = signer(at, e, directory)?;
    verify(e, key)?;
    if number(&body[16..20]) != u64::from(at.epoch) || at.rotation_due {
        return Err(reject("invalid_entry"));
    }
    let role = |state: &Membership| state.members.get(signer).map_or(0, |m| m.0);
    if role(at) < CONTRIBUTOR || role(head) < CONTRIBUTOR {
        return Err(reject("unauthorized"));
    }
    Ok(Upload {
        file_id: body[..16].to_vec(),
        uploader: signer.to_vec(),
        objects_hash: body[60..].to_vec(),
        rejected: String::new(),
    })
}

fn rejected(error: CallError) -> Upload {
    Upload {
        rejected: error.params.get("reason").cloned().unwrap_or_default(),
        ..Upload::default()
    }
}

pub fn verify_membership(r: VerifyMembershipLogRequest) -> Result<VerifyMembershipLogResponse, CallError> {
    let log_type = u8::try_from(r.log_type)
        .ok()
        .filter(|t| (2..=3).contains(t))
        .ok_or_else(|| invalid_request("log_type"))?;
    let log_id = fixed::<16>(&r.log_id, "log_id")?;
    checkpoint(&r.entries, r.checkpoint)?;
    let directory: Directory = r
        .identities
        .iter()
        .map(|i| (&i.user_id[..], &i.signing_keys[..]))
        .collect();
    let statements: Vec<_> = r.statements.iter().map(|s| statement(s, &log_id)).collect();
    let needed: BTreeSet<_> = statements.iter().flatten().map(|(_, seq)| *seq).collect();
    let (mut state, mut snapshots, mut wraps) = (Membership::default(), BTreeMap::new(), vec![]);
    for (seq, bytes) in r.entries.iter().enumerate() {
        let e = parse(bytes)?;
        chain(&e, log_type, &log_id, seq as u64, &state.head)?;
        if seq == 0 {
            // The first body names the key that signs it.
            let create = body(&e, (e.body_type == 1).then_some(32))?;
            let (owner, key_id) = create.split_at(16);
            if key_index(&directory, owner, key_id).is_none() {
                return Err(reject("invalid_entry"));
            }
            state.owner = owner;
            state.members.insert(owner, (ADMIN, key_id));
        }
        let (signer, key) = signer(&state, &e, &directory)?;
        verify(&e, key)?;
        if seq > 0 {
            apply(&mut state, &e, signer, &directory, &mut wraps, seq)?;
        }
        state.head = hash(bytes);
        if needed.contains(&(seq as u64)) {
            snapshots.insert(seq as u64, state.clone());
        }
    }
    let uploads = statements
        .into_iter()
        .map(|s| s.and_then(|(e, seq)| upload(&e, snapshots.get(&seq), &state, &directory)))
        .map(|u| u.unwrap_or_else(rejected))
        .collect();
    Ok(VerifyMembershipLogResponse {
        owner: state.owner.to_vec(),
        members: (state.members.iter())
            .map(|(user, (role, key_id))| Member {
                user_id: user.to_vec(),
                role: (*role).into(),
                signing_key_id: key_id.to_vec(),
            })
            .collect(),
        epoch: state.epoch,
        rotation_due: state.rotation_due,
        links: (state.links.iter())
            .map(|(link, drop_key)| Link {
                link_id: link.to_vec(),
                drop_key: drop_key.to_vec(),
            })
            .collect(),
        head: head(&r.entries, state.head),
        wraps,
        uploads,
    })
}

/// Groups of five digits: each 5-byte group of `data`, big-endian, mod 100000.
fn digits(data: &[u8], groups: usize) -> String {
    let group = |g: &[u8]| format!("{:05}", number(g) % 100_000);
    let groups: Vec<_> = data.chunks(5).take(groups).map(group).collect();
    groups.join(" ")
}

pub fn safety_number(r: SafetyNumberRequest) -> Result<CodeResponse, CallError> {
    let mut users = [
        (fixed::<16>(&r.user_a, "user_a")?, &r.signing_key_a),
        (fixed::<16>(&r.user_b, "user_b")?, &r.signing_key_b),
    ];
    users.sort();
    let half = |(user, key): &([u8; 16], &Vec<u8>)| {
        let hash = Sha512::new()
            .chain_update(b"photolib/v1/verification")
            .chain_update(user)
            .chain_update(key)
            .finalize();
        digits(&hash, 6)
    };
    Ok(CodeResponse {
        code: format!("{} {}", half(&users[0]), half(&users[1])),
    })
}

pub fn epoch_code(r: EpochCodeRequest) -> Result<CodeResponse, CallError> {
    let hash = Sha256::new()
        .chain_update(b"photolib/v1/epoch-code")
        .chain_update(fixed::<16>(&r.log_id, "log_id")?)
        .chain_update(fixed::<32>(&r.head, "head")?)
        .finalize();
    Ok(CodeResponse { code: digits(&hash, 4) })
}
