//! Password login (M2-02, ADR-0052): OPAQUE with the configuration of docs/dev/crypto-v1.md#opaque, the key file that
//! keeps the OPRF seed and the server's key pair out of the database, and session tokens stored as hashes.

use std::{
    collections::HashMap,
    fs::{self, File, OpenOptions},
    io::{ErrorKind, Write},
    net::IpAddr,
    os::unix::fs::OpenOptionsExt,
    path::Path,
    time::{Duration, Instant},
};

use hmac::{Hmac, Mac};
use opaque_ke::{
    CipherSuite, CredentialFinalization, CredentialRequest, Identifiers, RegistrationRequest, Ristretto255,
    ServerLogin, ServerLoginParameters, ServerRegistration, ServerSetup, TripleDh, ksf::Identity,
};
use photolib_proto::proto::photolib::api::v1::PasswordSetup;
use rand_core::{CryptoRng, OsRng, RngCore};
use sha2::{Digest, Sha256, Sha512};
use sqlx::{Connection, PgConnection};
use uuid::Uuid;

use crate::{accounts::timestamp, config::Config};

pub struct Suite;

impl CipherSuite for Suite {
    type OprfCs = Ristretto255;
    type KeyExchange = TripleDh<Ristretto255, Sha512>;
    /// Clients stretch the password with Argon2id and the account's parameters; the server never runs the KSF, and
    /// nothing it computes depends on it.
    type Ksf = Identity;
}

pub const CONTEXT: &[u8] = b"photolib/v1/opaque";

/// Reads the server's OPAQUE key from `path` (`opaque_key_file`), or makes one while no password exists that an earlier
/// key would be needed for. It holds the OPRF seed and the server's key pair: outside the database, so that a leaked
/// database checks no password guess.
pub fn load_key(path: &Path, passwords_exist: bool) -> Result<ServerSetup<Suite>, String> {
    let shown = path.display();
    match fs::read(path) {
        Ok(bytes) => ServerSetup::deserialize(&bytes)
            .map_err(|_| format!("the OPAQUE key {shown} is damaged; restore it from a backup")),
        Err(error) if error.kind() != ErrorKind::NotFound => {
            Err(format!("the OPAQUE key {shown} cannot be read: {error}"))
        }
        Err(_) if passwords_exist => Err(format!(
            "the OPAQUE key {shown} is missing, and without it no password signs in; restore it from a backup"
        )),
        Err(_) => {
            let setup = ServerSetup::new(&mut OsRng);
            write_private(path, &setup.serialize())
                .map_err(|error| format!("cannot write the OPAQUE key {shown}: {error}"))?;
            Ok(setup)
        }
    }
}

fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let dir = path.parent().expect("the key lives in a directory");
    fs::create_dir_all(dir)?;
    let temp = path.with_extension("tmp");
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&temp)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    fs::rename(&temp, path)?;
    File::open(dir)?.sync_all()
}

fn parameters() -> ServerLoginParameters<'static, 'static> {
    ServerLoginParameters {
        context: Some(CONTEXT),
        identifiers: Identifiers::default(),
    }
}

/// The server's OPAQUE RegistrationResponse to a client's RegistrationRequest for the account `credential`.
pub fn registration_response(setup: &ServerSetup<Suite>, request: &[u8], credential: &[u8]) -> Option<Vec<u8>> {
    let request = RegistrationRequest::deserialize(request).ok()?;
    let response = ServerRegistration::start(setup, request, credential).ok()?;
    Some(response.message.serialize().to_vec())
}

/// KE2 for a client's KE1, and the state that checks its KE3. Without a record, KE2 is a fake that no KE3 opens.
pub fn login_start(
    rng: &mut (impl RngCore + CryptoRng),
    setup: &ServerSetup<Suite>,
    record: Option<&[u8]>,
    ke1: &[u8],
    credential: &[u8],
) -> Option<(Vec<u8>, ServerLogin<Suite>)> {
    let record = record.and_then(|record| ServerRegistration::deserialize(record).ok());
    let ke1 = CredentialRequest::deserialize(ke1).ok()?;
    let started = ServerLogin::start(rng, setup, record, ke1, credential, parameters()).ok()?;
    Some((started.message.serialize().to_vec(), started.state))
}

/// Whether `ke3` proves that the client knows the password.
pub fn login_finish(state: ServerLogin<Suite>, ke3: &[u8]) -> bool {
    CredentialFinalization::deserialize(ke3).is_ok_and(|ke3| state.finish(ke3, parameters()).is_ok())
}

/// Whether `record` is an OPAQUE registration record.
pub fn record_valid(record: &[u8]) -> bool {
    ServerRegistration::<Suite>::deserialize(record).is_ok()
}

/// A new bearer token: 256 random bits as hex.
pub fn new_token() -> String {
    let mut bytes = [0; 32];
    getrandom::fill(&mut bytes).expect("the operating system provides random numbers");
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// What the database keeps of a token.
pub fn token_hash(token: &str) -> Vec<u8> {
    Sha256::digest(token.as_bytes()).to_vec()
}

/// Makes the one-time token with which `user` sets a password, valid for seven days, in place of any earlier one; with
/// no `actor`, on the host.
pub async fn issue_password_setup(
    conn: &mut PgConnection,
    actor: impl Into<Option<Uuid>>,
    user: Uuid,
) -> sqlx::Result<PasswordSetup> {
    let token = new_token();
    let expires_at: i64 = sqlx::query_scalar(
        "INSERT INTO password_setups (user_id, token_hash, expires_at) VALUES ($1::uuid, $2, now() + interval '7 days')
         ON CONFLICT (user_id) DO UPDATE SET token_hash = EXCLUDED.token_hash, expires_at = EXCLUDED.expires_at
         RETURNING (extract(EPOCH FROM expires_at) * 1e6)::bigint",
    )
    .bind(user.to_string())
    .bind(token_hash(&token))
    .fetch_one(&mut *conn)
    .await?;
    audit(conn, actor, "password_setup.create", user, None).await?;
    Ok(PasswordSetup {
        token,
        expires_at: Some(timestamp(expires_at)).into(),
        ..Default::default()
    })
}

/// `photolibd admin password-setup <handle>`: a setup token for an active account, made on the host by no account, so
/// that an instance whose only administrator forgot the password is not lost; with `public_url`, the link that carries
/// it, as the admin console shows it.
pub async fn host_password_setup(config: &Config, handle: &str) -> Result<String, String> {
    let url = config.database.url.as_ref().ok_or("database.url is not set")?;
    let mut conn = PgConnection::connect(url.expose())
        .await
        .map_err(|error| format!("cannot connect to the database: {error}"))?;
    let handle = handle.trim().to_lowercase();
    let account: Option<(String, String)> =
        sqlx::query_as("SELECT id::text, handle FROM users WHERE (handle = $1 OR email = $1) AND status = 'active'")
            .bind(&handle)
            .fetch_optional(&mut conn)
            .await
            .map_err(|error| format!("cannot read the accounts: {error}"))?;
    let (user, handle) = account.ok_or_else(|| format!("no active account is {handle}"))?;
    let user = user.parse().map_err(|_| "an account id is not a uuid")?;
    let token = issue_password_setup(&mut conn, None, user)
        .await
        .map_err(|error| format!("cannot make the token: {error}"))?
        .token;
    let base = config.base_path.trim_end_matches('/');
    Ok(match &config.public_url {
        Some(origin) => format!(
            "A password setup link for {handle}, valid for seven days:\n{}{base}/#/password-setup?handle={handle}&token={token}",
            origin.trim_end_matches('/')
        ),
        None => {
            format!("A password setup token for {handle}, valid for seven days (set public_url for a link):\n{token}")
        }
    })
}

/// Appends an event about `user` (and their `device`) to the audit log.
pub async fn audit(
    conn: &mut PgConnection,
    actor: impl Into<Option<Uuid>>,
    action: &str,
    user: Uuid,
    device: Option<Uuid>,
) -> sqlx::Result<()> {
    sqlx::query(
        "SELECT audit_append($1::uuid, $2, jsonb_strip_nulls(jsonb_build_object('user_id', $3::uuid, 'device_id', $4::uuid)), '{}')",
    )
    .bind(actor.into().map(|actor| actor.to_string()))
    .bind(action)
    .bind(user.to_string())
    .bind(device.map(|device| device.to_string()))
    .execute(conn)
    .await?;
    Ok(())
}

/// Whether `params` is an Argon2id parameter set (docs/dev/crypto-v1.md#argon2id-parameters) within the account
/// policy: Argon2id v1.3, 128 MiB to 2 GiB, 3 to 64 passes, one lane and a 16-byte salt.
pub fn ksf_params_valid(params: &[u8]) -> bool {
    let word = |at: usize| u32::from_be_bytes(params[at..at + 4].try_into().unwrap());
    params.len() == 26
        && params[0] == 1
        && (128 * 1024..=2048 * 1024).contains(&word(1))
        && (3..=64).contains(&word(5))
        && params[9] == 1
}

/// A hash of `parts` keyed by the server key: stable, and unpredictable without the key.
fn keyed(setup: &ServerSetup<Suite>, parts: &[&[u8]]) -> [u8; 32] {
    let mut hash = Hmac::<Sha256>::new_from_slice(&setup.serialize()).expect("HMAC takes any key");
    parts.iter().for_each(|part| hash.update(part));
    hash.finalize().into_bytes().into()
}

/// The key that signs media URLs: every `api` process with this key file has it, and no handle can collide with its
/// label, which starts with NUL.
pub fn media_key(setup: &ServerSetup<Suite>) -> [u8; 32] {
    keyed(setup, &[b"\0photolib media urls"])
}

/// Which account a handle without a password copies its cost from, as an offset into the accounts.
pub fn fake_pick(setup: &ServerSetup<Suite>, handle: &str) -> i64 {
    let hash = keyed(setup, &[handle.as_bytes()]);
    i64::from_be_bytes(hash[..8].try_into().unwrap()) & i64::MAX
}

/// The parameters StartLogin shows for a handle without a password: the cost (algorithm, memory, passes, lanes) of
/// `real`, the parameters of the account `fake_pick` chose, else what enrolment tries first; and a salt keyed by that
/// cost and the handle. A fake stays the same per handle and changes its salt with its cost, as a real password does.
pub fn fake_ksf_params(setup: &ServerSetup<Suite>, handle: &str, real: Option<&[u8]>) -> Vec<u8> {
    let cost = real.map_or(&[1, 0, 4, 0, 0, 0, 0, 0, 3, 1][..], |real| &real[..10]);
    [cost, &keyed(setup, &[cost, handle.as_bytes()])[..16]].concat()
}

/// The credential identifier of a new password of `user`: the account id and 16 random bytes, so that setting a
/// password never evaluates the OPRF key of the one that signs in.
pub fn new_credential(user: Uuid) -> Vec<u8> {
    let mut nonce = [0; 16];
    getrandom::fill(&mut nonce).expect("the operating system provides random numbers");
    [user.as_bytes(), &nonce[..]].concat()
}

/// What a sign-in attempt counts against (ADR-0052): its handle and the address it comes from, or else the device that
/// proved it signed in before, apart from everyone else.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Key {
    /// A handle or an email, as typed.
    Handle(String),
    /// A device that proved the secret of its last sign-in.
    Device(Uuid),
    /// Where the attempt came from.
    Address(IpAddr),
}

impl Key {
    /// An address as one client holds it: IPv6 by its /64.
    pub fn address(addr: IpAddr) -> Self {
        Self::Address(match addr.to_canonical() {
            IpAddr::V6(v6) => IpAddr::V6((u128::from(v6) & !0 << 64).into()),
            v4 @ IpAddr::V4(_) => v4,
        })
    }

    /// An address is shared by everyone behind it, so it gets more before it pauses.
    fn free(&self) -> u32 {
        match self {
            Self::Address(_) => FREE_PER_ADDRESS,
            Self::Handle(_) | Self::Device(_) => FREE_ATTEMPTS,
        }
    }
}

/// Progressive lockout (PRIV-22). Every login start counts as an attempt, because a client learns from KE2 alone whether
/// a guess was right; five are free (thirty from an address), then each needs a pause that starts at 30 seconds and
/// doubles up to an hour. A successful login clears its handle or device and a day without attempts forgives any.
/// Unknown handles count the same, so that the lockout tells nobody which accounts exist.
#[derive(Default)]
pub struct Throttle(HashMap<Key, (u32, Instant)>);

const FREE_ATTEMPTS: u32 = 5;
const FREE_PER_ADDRESS: u32 = 30;
const FIRST_PAUSE: Duration = Duration::from_secs(30);
const LONGEST_PAUSE: Duration = Duration::from_secs(3600);
const FORGIVEN_AFTER: Duration = Duration::from_secs(24 * 3600);
/// Bounds the memory an attacker can fill with handles; when it is full, new handles wait.
const MAX_HANDLES: usize = 100_000;

impl Throttle {
    /// Counts an attempt on `key`, or says how long it must wait.
    pub fn attempt(&mut self, key: &Key, now: Instant) -> Result<(), Duration> {
        if self.0.len() >= MAX_HANDLES && !self.0.contains_key(key) {
            self.0.retain(|_, (_, last)| now - *last < FORGIVEN_AFTER);
            if self.0.len() >= MAX_HANDLES {
                return Err(FIRST_PAUSE);
            }
        }
        let (attempts, last) = self.0.entry(key.clone()).or_insert((0, now));
        if now - *last >= FORGIVEN_AFTER {
            *attempts = 0;
        }
        if let Some(extra) = attempts.checked_sub(key.free()) {
            let pause = FIRST_PAUSE.saturating_mul(1 << extra.min(16)).min(LONGEST_PAUSE);
            if now < *last + pause {
                return Err(*last + pause - now);
            }
        }
        *attempts += 1;
        *last = now;
        Ok(())
    }

    pub fn succeeded(&mut self, key: &Key) {
        self.0.remove(key);
    }
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;
    use crate::testing::Replay;

    fn hex(text: &Value) -> Vec<u8> {
        let text = text.as_str().unwrap();
        (0..text.len())
            .step_by(2)
            .map(|at| u8::from_str_radix(&text[at..at + 2], 16).unwrap())
            .collect()
    }

    fn params(m_kib: u32, t: u32, p: u8) -> Vec<u8> {
        [&[1][..], &m_kib.to_be_bytes(), &t.to_be_bytes(), &[p], &[7; 16]].concat()
    }

    #[test]
    fn only_argon2id_parameters_within_the_account_policy_are_accepted() {
        let mib = 1024;
        for valid in [
            params(256 * mib, 3, 1),
            params(128 * mib, 64, 1),
            params(2048 * mib, 3, 1),
        ] {
            assert!(ksf_params_valid(&valid), "{valid:?}");
        }
        let mut wrong_algorithm = params(256 * mib, 3, 1);
        wrong_algorithm[0] = 2;
        for invalid in [
            params(128 * mib - 1, 3, 1),
            params(2048 * mib + 1, 3, 1),
            params(256 * mib, 2, 1),
            params(256 * mib, 65, 1),
            params(256 * mib, 3, 2),
            params(256 * mib, 3, 1)[..25].to_vec(),
            [params(256 * mib, 3, 1), vec![0]].concat(),
            wrong_algorithm,
            Vec::new(),
        ] {
            assert!(!ksf_params_valid(&invalid), "{invalid:?}");
        }
    }

    #[test]
    fn an_unknown_handle_shows_valid_parameters_with_a_salt_stable_per_handle_key_and_cost() {
        let key = ServerSetup::<Suite>::new(&mut OsRng);
        let unknown = fake_ksf_params(&key, "nobody", None);
        assert!(ksf_params_valid(&unknown));
        assert_eq!(unknown[..10], params(256 * 1024, 3, 1)[..10], "no account yet");
        assert_eq!(unknown, fake_ksf_params(&key, "nobody", None));
        assert_ne!(unknown, fake_ksf_params(&key, "nobody2", None));
        let other_key = ServerSetup::new(&mut OsRng);
        assert_ne!(unknown, fake_ksf_params(&other_key, "nobody", None));
        let phone = params(128 * 1024, 6, 1);
        let copied = fake_ksf_params(&key, "nobody", Some(&phone));
        assert_eq!(copied[..10], phone[..10]);
        assert_ne!(copied[10..], unknown[10..]);
        assert_eq!(fake_pick(&key, "nobody"), fake_pick(&key, "nobody"));
        assert!(fake_pick(&key, "nobody") >= 0);
    }

    fn handle(handle: &str) -> Key {
        Key::Handle(handle.into())
    }

    #[test]
    fn five_attempts_are_free_then_each_waits_twice_as_long_up_to_an_hour() {
        let secs = Duration::from_secs;
        let start = Instant::now();
        let mut throttle = Throttle::default();
        let ann = &handle("ann");
        for _ in 0..5 {
            assert_eq!(throttle.attempt(ann, start), Ok(()));
        }
        assert_eq!(throttle.attempt(ann, start), Err(secs(30)));
        assert_eq!(throttle.attempt(ann, start + secs(29)), Err(secs(1)));
        let mut now = start;
        for (wait, next) in [
            (30, 60),
            (60, 120),
            (120, 240),
            (240, 480),
            (480, 960),
            (960, 1920),
            (1920, 3600),
            (3600, 3600),
        ] {
            now += secs(wait);
            assert_eq!(throttle.attempt(ann, now), Ok(()), "after {wait}s");
            assert_eq!(throttle.attempt(ann, now), Err(secs(next)));
        }
        assert_eq!(throttle.attempt(&handle("bob"), now), Ok(()), "handles are independent");
        assert_eq!(
            throttle.attempt(&Key::Device(Uuid::nil()), now),
            Ok(()),
            "so are devices"
        );
        throttle.succeeded(ann);
        for _ in 0..5 {
            assert_eq!(throttle.attempt(ann, now), Ok(()), "a sign-in clears the handle");
        }
        assert!(throttle.attempt(ann, now).is_err());
        let tomorrow = now + secs(24 * 3600 + 1);
        for _ in 0..5 {
            assert_eq!(throttle.attempt(ann, tomorrow), Ok(()), "a quiet day forgives");
        }
    }

    #[test]
    fn a_full_throttle_refuses_new_handles_rather_than_forget_counted_ones() {
        let now = Instant::now();
        let mut throttle = Throttle::default();
        for n in 0..MAX_HANDLES {
            throttle.attempt(&handle(&n.to_string()), now).unwrap();
        }
        assert!(throttle.attempt(&handle("new"), now).is_err());
        assert_eq!(throttle.attempt(&handle("7"), now), Ok(()));
        let tomorrow = now + Duration::from_secs(24 * 3600 + 1);
        assert_eq!(
            throttle.attempt(&handle("new"), tomorrow),
            Ok(()),
            "stale handles make room"
        );
    }

    #[test]
    fn an_address_has_thirty_free_attempts_and_ipv6_counts_by_its_64() {
        let now = Instant::now();
        let mut throttle = Throttle::default();
        let address = |text: &str| Key::address(text.parse().unwrap());
        assert_eq!(address("2001:db8::1"), address("2001:db8::ffff:1"));
        assert_ne!(address("2001:db8::1"), address("2001:db8:0:1::1"));
        assert_eq!(address("::ffff:203.0.113.7"), address("203.0.113.7"));
        for _ in 0..30 {
            assert_eq!(throttle.attempt(&address("2001:db8::1"), now), Ok(()));
        }
        assert_eq!(
            throttle.attempt(&address("2001:db8::2"), now),
            Err(Duration::from_secs(30))
        );
        assert_eq!(throttle.attempt(&address("203.0.113.7"), now), Ok(()));
    }

    #[test]
    fn the_key_is_made_once_readable_only_by_photolibd_and_never_replaced_while_passwords_need_it() {
        use std::os::unix::fs::PermissionsExt;

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config/opaque.key");
        let made = load_key(&path, false).unwrap();
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        for passwords_exist in [false, true] {
            assert_eq!(load_key(&path, passwords_exist).unwrap(), made);
        }
        std::fs::remove_file(&path).unwrap();
        let missing = load_key(&path, true).unwrap_err();
        assert!(
            missing.contains(&path.display().to_string()) && missing.contains("backup"),
            "{missing}"
        );
        assert!(!path.exists(), "no new key replaces the one the passwords need");
        std::fs::write(&path, b"short").unwrap();
        let damaged = load_key(&path, false).unwrap_err();
        assert!(damaged.contains("damaged"), "{damaged}");
    }

    #[test]
    fn the_server_side_reproduces_the_opaque_vectors_of_the_crypto_spec() {
        let vectors: Value =
            serde_json::from_str(include_str!("../../../../kernel/testvectors/crypto/opaque.json")).unwrap();
        let (input, output) = (&vectors["inputs"], &vectors["outputs"]);
        assert_eq!(hex(&input["context"]), CONTEXT);
        let setup_bytes = [
            hex(&input["oprf_seed"]),
            hex(&input["server_private_key"]),
            hex(&input["server_public_key"]),
        ]
        .concat();
        let setup = ServerSetup::<Suite>::deserialize(&setup_bytes).unwrap();
        let credential = hex(&input["credential_identifier"]);
        assert_eq!(
            registration_response(&setup, &hex(&output["registration_request"]), &credential),
            Some(hex(&output["registration_response"]))
        );
        // opaque-ke draws a dummy masking key, then the masking nonce, the key share seed and the nonce.
        let randomness = |seed: &str| {
            let draws = [&input["masking_nonce"], &input[seed], &input["server_nonce"]];
            Replay([vec![0; 64], draws.into_iter().flat_map(hex).collect()].concat())
        };
        let record = hex(&output["registration_record"]);
        let start = |seed| {
            login_start(
                &mut randomness(seed),
                &setup,
                Some(&record),
                &hex(&output["KE1"]),
                &credential,
            )
            .unwrap()
        };
        let (ke2, state) = start("server_keyshare_seed");
        assert_eq!(ke2, hex(&output["KE2"]));
        assert!(login_finish(state, &hex(&output["KE3"])));
        let mut forged = hex(&output["KE3"]);
        forged[0] ^= 1;
        assert!(!login_finish(start("server_keyshare_seed").1, &forged));
        assert!(!login_finish(start("client_keyshare_seed").1, &hex(&output["KE3"])));
    }
}
