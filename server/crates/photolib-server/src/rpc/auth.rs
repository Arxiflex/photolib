//! The auth service: passwords set and checked with OPAQUE and the sessions of devices (M2-02, ADR-0052); passkeys,
//! TOTP, recovery codes and the instance's second factor policy (M2-05, ADR-0088).

use std::{
    collections::HashMap,
    net::IpAddr,
    sync::{Mutex, MutexGuard, PoisonError},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use async_trait::async_trait;
use axum::http::HeaderMap;
use buffa::EnumValue;
use connectrpc::{ConnectError, ErrorCode, RequestContext, ServiceRequest, ServiceResult};
use opaque_ke::{ServerLogin, ServerSetup};
use photolib_proto::{
    connect::photolib::api::v1::AuthService,
    proto::photolib::api::v1::{
        __buffa::oneof::{finish_second_factor_request::Answer, finish_step_up_request::Answer as StepUpAnswer},
        CompleteOidcRequest, CompleteOidcResponse, CreateRecoveryCodesRequest, CreateRecoveryCodesResponse,
        DeletePasskeyRequest, DeletePasskeyResponse, DeleteTotpRequest, DeleteTotpResponse, Device, FinishLoginRequest,
        FinishLoginResponse, FinishPasskeyLoginRequest, FinishPasskeyLoginResponse, FinishPasskeySetupRequest,
        FinishPasskeySetupResponse, FinishPasswordSetupRequest, FinishPasswordSetupResponse, FinishSecondFactorRequest,
        FinishSecondFactorResponse, FinishStepUpRequest, FinishStepUpResponse, FinishTotpSetupRequest,
        FinishTotpSetupResponse, ListDevicesRequest, ListDevicesResponse, ListSecondFactorsRequest,
        ListSecondFactorsResponse, Passkey, ReportBackupRequest, ReportBackupResponse, RevokeDeviceRequest,
        RevokeDeviceResponse, RotateSessionRequest, RotateSessionResponse, SecondFactor, SecondFactorChallenge,
        Session, StartLoginRequest, StartLoginResponse, StartOidcRequest, StartOidcResponse, StartPasskeyLoginRequest,
        StartPasskeyLoginResponse, StartPasskeySetupRequest, StartPasskeySetupResponse, StartPasswordSetupRequest,
        StartPasswordSetupResponse, StartStepUpRequest, StartStepUpResponse, StartTotpSetupRequest,
        StartTotpSetupResponse, UnlockPath,
    },
};
use rand_core::OsRng;
use sqlx::{PgConnection, PgExecutor, PgPool};
use uuid::Uuid;

use super::{ApiError, users::internal};
use crate::{
    account_keys,
    accounts::timestamp,
    auth::{
        Key, Suite, Throttle, audit, fake_ksf_params, fake_pick, ksf_params_valid, login_finish, login_start,
        new_credential, new_token, record_valid, registration_response, token_hash,
    },
    db::DbError,
    oidc::Oidc,
    proxy::Forwarding,
    totp,
    webauthn::{self, RelyingParty},
};

/// Who signs a request.
#[async_trait]
pub trait Sessions: Send + Sync {
    async fn caller(&self, headers: &HeaderMap) -> Result<Option<Caller>, DbError>;
}

/// The account, device and session behind a request.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Caller {
    pub user: Uuid,
    pub device: Uuid,
    pub session: Uuid,
    /// The instance requires a second factor and the account has none: it may only enrol one (ADR-0088).
    pub must_enrol: bool,
}

pub struct Auth {
    pub(super) pool: PgPool,
    key: ServerSetup<Suite>,
    logins: Mutex<Logins>,
    pub(super) oidc: Option<Oidc>,
    /// Where passkeys are bound, from `public_url`; none without one.
    rp: Option<RelyingParty>,
}

/// What waits for a client's next step, until it expires, and the lockout. Both live in this process: with several API
/// processes, a client's steps must reach the same one (ADR-0052).
#[derive(Default)]
struct Logins {
    pending: HashMap<Uuid, (Instant, Pending)>,
    throttle: Throttle,
}

/// A step a client takes next, named by a random id that only it knows, which works once.
enum Pending {
    /// A password sign-in between StartLogin and FinishLogin, counted against `key`.
    Password {
        key: Key,
        user: Option<Uuid>,
        state: ServerLogin<Suite>,
    },
    /// A password sign-in whose password was right, waiting for a second factor that answers `challenge`.
    SecondFactor {
        key: Key,
        user: Uuid,
        device: Device,
        challenge: Vec<u8>,
        wrong: u32,
    },
    /// A passkey sign-in.
    Passkey { challenge: Vec<u8> },
    /// A passkey being added to `user`'s account.
    PasskeySetup { user: Uuid, challenge: Vec<u8> },
    /// A step-up of `session` by the account with `handle`: KE3 for `password` when the client sent KE1, or a second
    /// factor, a passkey answering `challenge`.
    StepUp {
        session: Uuid,
        handle: String,
        password: Option<ServerLogin<Suite>>,
        challenge: Vec<u8>,
    },
    /// A TOTP secret on its way to `user`'s authenticator app, which `replaces` theirs when the setup had a proof.
    TotpSetup {
        user: Uuid,
        secret: Vec<u8>,
        replaces: bool,
    },
}

impl Auth {
    pub fn new(pool: PgPool, key: ServerSetup<Suite>) -> Auth {
        Auth {
            pool,
            key,
            logins: Mutex::default(),
            oidc: None,
            rp: None,
        }
    }

    /// Signs people in with these OpenID Connect providers too.
    pub fn with_oidc(self, oidc: Oidc) -> Auth {
        Auth {
            oidc: Some(oidc),
            ..self
        }
    }

    /// The key that signs media URLs (`media`).
    pub fn media_key(&self) -> [u8; 32] {
        crate::auth::media_key(&self.key)
    }

    /// Offers passkeys bound to `rp`, photolibd's `public_url`.
    pub fn with_passkeys(self, rp: Option<RelyingParty>) -> Auth {
        Auth { rp, ..self }
    }

    pub fn passkeys(&self) -> bool {
        self.rp.is_some()
    }

    /// Whether any account has a password, which only the current key file checks.
    pub async fn passwords_exist(pool: &PgPool) -> Result<bool, DbError> {
        Ok(sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM password_records)")
            .fetch_one(pool)
            .await?)
    }
}

/// How long a client has between StartLogin and FinishLogin: enough for Argon2id at 2 GiB on a slow phone.
const LOGIN_WINDOW: Duration = Duration::from_secs(120);
/// How long a password sign-in waits for its second factor, and a passkey ceremony for its answer.
const CEREMONY_WINDOW: Duration = webauthn::TIMEOUT;
/// How long a TOTP setup waits for its first code: time to install an authenticator app.
const TOTP_WINDOW: Duration = Duration::from_secs(600);
/// The wrong answers that end a sign-in waiting for its second factor.
const MAX_WRONG: u32 = 5;
/// Bounds the memory that unfinished steps take; when it is full, new ones wait.
const MAX_PENDING: usize = 10_000;
/// An account's credential identifier, record and parameters, and the parameters of the account a fake copies.
type LoginRow = (Option<Vec<u8>>, Option<Vec<u8>>, Option<Vec<u8>>, Option<Vec<u8>>);
/// An account's handle, and its password's credential identifier, record and parameters.
type StepUpRow = (String, Option<Vec<u8>>, Option<Vec<u8>>, Option<Vec<u8>>);
const EXPIRES_AT: &str = "(extract(EPOCH FROM expires_at) * 1e6)::bigint";
const CREATED_AT: &str = "(extract(EPOCH FROM created_at) * 1e6)::bigint";
const LAST_USED_AT: &str = "(extract(EPOCH FROM last_used_at) * 1e6)::bigint";

pub(super) fn invalid(field: &'static str) -> ConnectError {
    ApiError::new(ErrorCode::InvalidArgument, "field.invalid")
        .param("field", field)
        .into()
}

fn signed_out() -> ConnectError {
    ApiError::new(ErrorCode::Unauthenticated, "session.required").into()
}

fn login_failed() -> ConnectError {
    ApiError::new(ErrorCode::PermissionDenied, "login.failed").into()
}

pub(super) fn throttled(wait: Duration) -> ConnectError {
    let seconds = wait.as_secs() + u64::from(wait.subsec_nanos() > 0);
    ApiError::new(ErrorCode::ResourceExhausted, "login.throttled")
        .param("retry_after_seconds", seconds)
        .into()
}

fn step_up_required() -> ConnectError {
    ApiError::new(ErrorCode::PermissionDenied, "step_up.required").into()
}

fn setup_expired() -> ConnectError {
    ApiError::new(ErrorCode::FailedPrecondition, "setup.expired").into()
}

fn no_passkeys() -> ConnectError {
    ApiError::new(ErrorCode::FailedPrecondition, "passkey.unavailable").into()
}

pub(super) fn db(error: impl Into<DbError>) -> ConnectError {
    internal(error.into())
}

fn printable(text: &str, max: usize) -> bool {
    !text.is_empty() && text.chars().count() <= max && !text.chars().any(char::is_control)
}

fn random(length: usize) -> Vec<u8> {
    let mut bytes = vec![0; length];
    getrandom::fill(&mut bytes).expect("the operating system provides random numbers");
    bytes
}

/// The TOTP time step of now.
fn now_step() -> u64 {
    let now = SystemTime::now().duration_since(UNIX_EPOCH);
    now.expect("the clock is past 1970").as_secs() / 30
}

/// Ten recovery codes in place of `user`'s, to show once.
async fn replace_recovery_codes(conn: &mut PgConnection, user: Uuid) -> Result<Vec<String>, ConnectError> {
    let codes = totp::recovery_codes();
    let hashes: Vec<Vec<u8>> = codes.iter().filter_map(|code| totp::recovery_hash(code)).collect();
    sqlx::query(
        "WITH old AS (DELETE FROM recovery_codes WHERE user_id = $1::uuid)
         INSERT INTO recovery_codes (user_id, code_hash) SELECT $1::uuid, unnest($2::bytea[])",
    )
    .bind(user.to_string())
    .bind(hashes)
    .execute(&mut *conn)
    .await
    .map_err(db)?;
    audit(conn, user, "recovery_codes.create", user, None)
        .await
        .map_err(db)?;
    Ok(codes)
}

/// Ten recovery codes for `user` when none are left, as when a first second factor comes; else none.
async fn first_recovery_codes(conn: &mut PgConnection, user: Uuid) -> Result<Vec<String>, ConnectError> {
    let left: bool = sqlx::query_scalar("SELECT EXISTS (SELECT FROM recovery_codes WHERE user_id = $1::uuid)")
        .bind(user.to_string())
        .fetch_one(&mut *conn)
        .await
        .map_err(db)?;
    match left {
        true => Ok(vec![]),
        false => replace_recovery_codes(conn, user).await,
    }
}

impl Auth {
    /// The steps that wait and the lockout, which a panic while they were held leaves as they were.
    fn logins(&self) -> MutexGuard<'_, Logins> {
        self.logins.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Keeps `pending` for `window` under a new id; when too much is pending, the client waits.
    fn hold(&self, pending: Pending, window: Duration) -> Result<Uuid, ConnectError> {
        let now = Instant::now();
        let mut logins = self.logins();
        logins.pending.retain(|_, (expires, _)| *expires > now);
        if logins.pending.len() >= MAX_PENDING {
            return Err(throttled(window));
        }
        let id = Uuid::now_v7();
        logins.pending.insert(id, (now + window, pending));
        Ok(id)
    }

    /// Takes the step `id` names, unless it has expired.
    fn take(&self, id: &str) -> Option<(Uuid, Instant, Pending)> {
        let id = id.parse().ok()?;
        let (expires, pending) = self.logins().pending.remove(&id)?;
        (expires > Instant::now()).then_some((id, expires, pending))
    }

    fn put_back(&self, id: Uuid, expires: Instant, pending: Pending) {
        let mut logins = self.logins();
        logins.pending.insert(id, (expires, pending));
    }

    fn rp(&self) -> Result<&RelyingParty, ConnectError> {
        self.rp.as_ref().ok_or_else(no_passkeys)
    }

    /// Whether `user` has TOTP, the credential ids of their passkeys, and whether they have recovery codes left.
    async fn factors(&self, user: Uuid) -> Result<(bool, Vec<Vec<u8>>, bool), ConnectError> {
        sqlx::query_as(
            "SELECT EXISTS (SELECT FROM totp_secrets WHERE user_id = $1::uuid),
                coalesce((SELECT array_agg(credential_id ORDER BY created_at, id) FROM passkeys
                          WHERE user_id = $1::uuid), '{}'),
                EXISTS (SELECT FROM recovery_codes WHERE user_id = $1::uuid)",
        )
        .bind(user.to_string())
        .fetch_one(&self.pool)
        .await
        .map_err(db)
    }

    /// The second factors an account with `factors` can answer `challenge` with, and the passkey request options,
    /// which ask for user verification when `verify`.
    fn offer(
        &self,
        (totp, passkeys, codes): (bool, Vec<Vec<u8>>, bool),
        challenge: &[u8],
        verify: bool,
    ) -> (Vec<EnumValue<SecondFactor>>, String) {
        let mut factors = vec![];
        if totp {
            factors.push(SecondFactor::SECOND_FACTOR_TOTP.into());
        }
        let passkey_options_json = match (&self.rp, passkeys.is_empty()) {
            (Some(rp), false) => {
                factors.push(SecondFactor::SECOND_FACTOR_PASSKEY.into());
                webauthn::request_options(rp, challenge, &passkeys, verify)
            }
            _ => String::new(),
        };
        if codes {
            factors.push(SecondFactor::SECOND_FACTOR_RECOVERY_CODE.into());
        }
        (factors, passkey_options_json)
    }

    /// Whether `code` is `user`'s TOTP code now, and has not counted before; it counts no more.
    async fn totp_counts(&self, user: Uuid, code: &str) -> Result<bool, ConnectError> {
        let row: Option<(Vec<u8>, i64)> =
            sqlx::query_as("SELECT secret, last_step FROM totp_secrets WHERE user_id = $1::uuid")
                .bind(user.to_string())
                .fetch_optional(&self.pool)
                .await
                .map_err(db)?;
        let Some(step) = row.and_then(|(secret, last)| {
            totp::matching_step(&secret, code, now_step()).filter(|&step| step as i64 > last)
        }) else {
            return Ok(false);
        };
        let counted = sqlx::query("UPDATE totp_secrets SET last_step = $2 WHERE user_id = $1::uuid AND last_step < $2")
            .bind(user.to_string())
            .bind(step as i64)
            .execute(&self.pool)
            .await
            .map_err(db)?;
        Ok(counted.rows_affected() == 1)
    }

    /// Whether `code` is one of `user`'s recovery codes, which it uses up.
    async fn recovery_code_counts(&self, user: Uuid, code: &str) -> Result<bool, ConnectError> {
        let Some(hash) = totp::recovery_hash(code) else {
            return Ok(false);
        };
        let mut tx = self.pool.begin().await.map_err(db)?;
        let used = sqlx::query("DELETE FROM recovery_codes WHERE user_id = $1::uuid AND code_hash = $2")
            .bind(user.to_string())
            .bind(hash)
            .execute(&mut *tx)
            .await
            .map_err(db)?;
        if used.rows_affected() == 0 {
            return Ok(false);
        }
        audit(&mut tx, user, "recovery_code.use", user, None)
            .await
            .map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(true)
    }

    /// The account of the passkey that signed `challenge` in `credential`, with its user verified when
    /// `user_verified`; the passkey's counter and last use move on.
    async fn passkey_signer(
        &self,
        challenge: &[u8],
        credential: &str,
        user_verified: bool,
    ) -> Result<Option<Uuid>, ConnectError> {
        let (Some(rp), Ok(assertion)) = (&self.rp, webauthn::assertion(credential)) else {
            return Ok(None);
        };
        let row: Option<(String, String, Vec<u8>, i64)> = sqlx::query_as(
            "SELECT p.id::text, p.user_id::text, p.public_key, p.sign_count FROM passkeys p JOIN users u ON u.id = p.user_id
             WHERE p.credential_id = $1 AND u.status = 'active'",
        )
        .bind(&assertion.credential_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(db)?;
        let Some((id, user, key, count)) = row else {
            return Ok(None);
        };
        let user: Uuid = user.parse().map_err(|_| db("a user id is not a uuid"))?;
        let handle = assertion.user_handle.as_deref();
        let count = u32::try_from(count).unwrap_or(u32::MAX);
        let verified = assertion.verify(rp, challenge, &key, count, user_verified);
        let (true, Ok(count)) = (handle.is_none_or(|handle| handle == user.as_bytes()), verified) else {
            return Ok(None);
        };
        sqlx::query("UPDATE passkeys SET sign_count = $2, last_used_at = now() WHERE id = $1::uuid")
            .bind(id)
            .bind(i64::from(count))
            .execute(&self.pool)
            .await
            .map_err(db)?;
        Ok(Some(user))
    }

    pub(super) async fn signed_in(&self, ctx: &RequestContext) -> Result<Caller, ConnectError> {
        self.caller(ctx.headers()).await.map_err(db)?.ok_or_else(signed_out)
    }

    /// Refuses `caller` unless its session proved its person within the last five minutes (M2-43, ADR-0242), or, when
    /// it is `adding` a way in, its account has nothing to prove it with: no password, second factor or recovery code.
    async fn fresh(&self, caller: &Caller, adding: bool) -> Result<(), ConnectError> {
        let fresh: Option<bool> = sqlx::query_scalar(
            "SELECT proved_at > now() - interval '5 minutes' OR $2 AND NOT (
                EXISTS (SELECT FROM password_records WHERE user_id = $3::uuid)
                OR EXISTS (SELECT FROM totp_secrets WHERE user_id = $3::uuid)
                OR EXISTS (SELECT FROM passkeys WHERE user_id = $3::uuid)
                OR EXISTS (SELECT FROM recovery_codes WHERE user_id = $3::uuid))
             FROM sessions WHERE id = $1::uuid",
        )
        .bind(caller.session.to_string())
        .bind(adding)
        .bind(caller.user.to_string())
        .fetch_optional(&self.pool)
        .await
        .map_err(db)?
        .flatten();
        fresh.unwrap_or_default().then_some(()).ok_or_else(step_up_required)
    }

    /// The account a password setup is for: the one of the setup token, which `use_up` deletes, or else the caller's,
    /// once its session proved its person.
    async fn setter(
        &self,
        ctx: &RequestContext,
        token: &str,
        conn: impl PgExecutor<'_>,
        use_up: bool,
    ) -> Result<Uuid, ConnectError> {
        if token.is_empty() {
            let caller = self.signed_in(ctx).await?;
            self.fresh(&caller, true).await?;
            return Ok(caller.user);
        }
        let query = match use_up {
            true => "DELETE FROM password_setups WHERE token_hash = $1 AND expires_at > now() RETURNING user_id::text",
            false => "SELECT user_id::text FROM password_setups WHERE token_hash = $1 AND expires_at > now()",
        };
        let user: Option<String> = sqlx::query_scalar(query)
            .bind(token_hash(token))
            .fetch_optional(conn)
            .await
            .map_err(db)?;
        user.and_then(|user| user.parse().ok())
            .ok_or_else(|| ApiError::new(ErrorCode::PermissionDenied, "password_setup.invalid").into())
    }

    /// The device of `handle`'s account that `id` names, if `secret` is the one its last sign-in gave it.
    async fn proven(&self, id: &str, secret: &str, handle: &str) -> Result<Option<Uuid>, ConnectError> {
        let (Ok(id), false) = (id.parse::<Uuid>(), secret.is_empty()) else {
            return Ok(None);
        };
        let proven: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT FROM devices d JOIN users u ON u.id = d.user_id
                WHERE d.id = $1::uuid AND d.secret_hash = $2 AND (u.handle = $3 OR u.email = $3))",
        )
        .bind(id.to_string())
        .bind(token_hash(secret))
        .bind(handle)
        .fetch_one(&self.pool)
        .await
        .map_err(db)?;
        Ok(proven.then_some(id))
    }

    /// The password path of `user`, for a sign-in that proved the password (KeyService).
    async fn password_path(&self, user: Uuid) -> Result<Option<UnlockPath>, ConnectError> {
        let mut conn = self.pool.acquire().await.map_err(db)?;
        account_keys::password_path(&mut conn, user).await.map_err(db)
    }

    /// A session for `user` on `device`: the device it names when it is one of theirs, else a new one. Either way the
    /// device gets a new secret, which proves it at its next StartLogin. The session counts as `proved` by the sign-in
    /// that opens it when that was a password, a passkey or a second factor.
    pub(super) async fn open_session(
        &self,
        user: Uuid,
        device: &Device,
        proved: bool,
    ) -> Result<Session, ConnectError> {
        let mut tx = self.pool.begin().await.map_err(db)?;
        let (token, secret) = (new_token(), new_token());
        let (id, expires_at): (String, i64) = sqlx::query_as(&format!(
            "WITH known AS (
                UPDATE devices SET name = $3, platform = $4, app_version = nullif($5, ''), last_seen_at = now(),
                    secret_hash = $9
                WHERE id = $1::uuid AND user_id = $2::uuid RETURNING id
            ), created AS (
                INSERT INTO devices (id, user_id, name, platform, app_version, last_seen_at, secret_hash)
                SELECT $6::uuid, $2::uuid, $3, $4, nullif($5, ''), now(), $9 WHERE NOT EXISTS (SELECT FROM known)
                RETURNING id
            )
            INSERT INTO sessions (id, device_id, token_hash, expires_at, proved_at)
            SELECT $7::uuid, id, $8, now() + interval '90 days', CASE WHEN $10 THEN now() END
            FROM (TABLE known UNION ALL TABLE created) device
            RETURNING device_id::text, {EXPIRES_AT}"
        ))
        .bind(device.device_id.parse::<Uuid>().unwrap_or_default().to_string())
        .bind(user.to_string())
        .bind(&device.name)
        .bind(&device.platform)
        .bind(&device.app_version)
        .bind(Uuid::now_v7().to_string())
        .bind(Uuid::now_v7().to_string())
        .bind(token_hash(&token))
        .bind(token_hash(&secret))
        .bind(proved)
        .fetch_one(&mut *tx)
        .await
        .map_err(db)?;
        let device = id.parse().map_err(|_| db("a device id is not a uuid"))?;
        audit(&mut tx, user, "session.create", user, Some(device))
            .await
            .map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(Session {
            device_secret: secret,
            ..session(token, expires_at, device, user)
        })
    }
}

/// The address a sign-in counts against: the client's, unless it is loopback or a trusted proxy's that named no client,
/// which every client behind it would share. An untrusted peer is the client, whatever headers it sends, so that no
/// guesser leaves the count by adding one.
fn counted_address(seen: &Forwarding) -> Option<IpAddr> {
    let client = seen.client.filter(|client| !client.to_canonical().is_loopback())?;
    (!seen.trusted || seen.client != seen.peer).then_some(client)
}

/// The bearer token of a request.
fn bearer(headers: &HeaderMap) -> Option<&str> {
    headers.get("authorization")?.to_str().ok()?.strip_prefix("Bearer ")
}

/// The device a client signs in on, trimmed and checked.
pub(super) fn checked(device: Option<Device>) -> Result<Device, ConnectError> {
    let mut device = device.unwrap_or_default();
    device.name = device.name.trim().into();
    if !printable(&device.name, 100) {
        return Err(invalid("device.name"));
    }
    if !printable(&device.platform, 32) {
        return Err(invalid("device.platform"));
    }
    if !device.app_version.is_empty() && !printable(&device.app_version, 32) {
        return Err(invalid("device.app_version"));
    }
    Ok(device)
}

fn session(token: String, expires_at: i64, device: Uuid, user: Uuid) -> Session {
    Session {
        token,
        expires_at: Some(timestamp(expires_at)).into(),
        device_id: device.to_string(),
        user_id: user.to_string(),
        ..Default::default()
    }
}

#[async_trait]
impl Sessions for Auth {
    /// The session whose token the request bears, if it is live and its account active. Every request asks the
    /// database, so a revoked device, a disabled account or a new policy counts from the next request on.
    async fn caller(&self, headers: &HeaderMap) -> Result<Option<Caller>, DbError> {
        let Some(token) = bearer(headers) else {
            return Ok(None);
        };
        // A rotated session's old token works until the new one is first used, or for a day (ADR-0052).
        let row: Option<(String, String, String, bool)> = sqlx::query_as(
            "WITH caller AS (
                SELECT d.user_id, s.device_id, s.id, s.token_hash = $1 AND s.previous_token_hash IS NOT NULL AS retires
                FROM sessions s JOIN devices d ON d.id = s.device_id JOIN users u ON u.id = d.user_id
                WHERE (s.token_hash = $1 OR s.previous_token_hash = $1 AND s.previous_expires_at > now())
                    AND s.expires_at > now() AND u.status = 'active'
            ), seen AS (
                UPDATE devices SET last_seen_at = now() FROM caller
                WHERE devices.id = caller.device_id AND last_seen_at < now() - interval '1 minute'
            ), retired AS (
                UPDATE sessions SET previous_token_hash = NULL, previous_expires_at = NULL FROM caller
                WHERE sessions.id = caller.id AND caller.retires
            )
            SELECT user_id::text, device_id::text, id::text,
                EXISTS (SELECT FROM instance_settings WHERE require_two_factor)
                AND NOT EXISTS (SELECT FROM totp_secrets WHERE totp_secrets.user_id = caller.user_id)
                AND NOT EXISTS (SELECT FROM passkeys WHERE passkeys.user_id = caller.user_id)
            FROM caller",
        )
        .bind(token_hash(token))
        .fetch_optional(&self.pool)
        .await?;
        let parse = |id: String| id.parse().map_err(|_| DbError::from("a session id is not a uuid"));
        row.map(|(user, device, session, must_enrol)| {
            Ok(Caller {
                user: parse(user)?,
                device: parse(device)?,
                session: parse(session)?,
                must_enrol,
            })
        })
        .transpose()
    }
}

#[allow(refining_impl_trait)]
impl AuthService for Auth {
    async fn start_password_setup(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, StartPasswordSetupRequest>,
    ) -> ServiceResult<StartPasswordSetupResponse> {
        let request = request.to_owned_message();
        let token = &request.password_setup_token;
        let user = self.setter(&ctx, token, &self.pool, false).await?;
        let credential = new_credential(user);
        let response = registration_response(&self.key, &request.registration_request, &credential)
            .ok_or_else(|| invalid("registration_request"))?;
        let private_libraries = !token.is_empty()
            && sqlx::query_scalar(
                "SELECT EXISTS (SELECT FROM libraries WHERE owner_id = $1::uuid AND privacy = 'private')
                     OR EXISTS (SELECT FROM account_keys WHERE user_id = $1::uuid)",
            )
            .bind(user.to_string())
            .fetch_one(&self.pool)
            .await
            .map_err(db)?;
        Ok(StartPasswordSetupResponse {
            registration_response: response,
            registration_id: credential,
            private_libraries,
            ..Default::default()
        }
        .into())
    }

    async fn finish_password_setup(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, FinishPasswordSetupRequest>,
    ) -> ServiceResult<FinishPasswordSetupResponse> {
        let request = request.to_owned_message();
        // A token is used up only if the setup commits.
        let mut tx = self.pool.begin().await.map_err(db)?;
        let token = &request.password_setup_token;
        let user = self.setter(&ctx, token, &mut *tx, true).await?;
        if !record_valid(&request.registration_record) {
            return Err(invalid("registration_record"));
        }
        if !ksf_params_valid(&request.ksf_params) {
            return Err(invalid("ksf_params"));
        }
        let credential = &request.registration_id;
        if credential.len() != 32 || credential[..16] != user.as_bytes()[..] {
            return Err(invalid("registration_id"));
        }
        sqlx::query(
            "INSERT INTO password_records (user_id, record, ksf_params, credential) VALUES ($1::uuid, $2, $3, $4)
             ON CONFLICT (user_id) DO UPDATE SET record = $2, ksf_params = $3, credential = $4, updated_at = now()",
        )
        .bind(user.to_string())
        .bind(&request.registration_record)
        .bind(&request.ksf_params)
        .bind(credential)
        .execute(&mut *tx)
        .await
        .map_err(db)?;
        account_keys::new_password(&mut tx, user, request.password_path.as_option()).await?;
        audit(&mut tx, user, "password.set", user, None).await.map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(FinishPasswordSetupResponse::default().into())
    }

    async fn start_login(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, StartLoginRequest>,
    ) -> ServiceResult<StartLoginResponse> {
        let request = request.to_owned_message();
        // A handle or an email, which never share a name: a handle has no "@" and an email always does.
        let handle = request.handle.trim().to_lowercase();
        if handle.len() > if handle.contains('@') { 254 } else { 64 } {
            return Err(invalid("handle"));
        }
        // A known device counts apart; anyone else against the handle and, first so that a refused address does not
        // count against the handle, the address.
        let device = self.proven(&request.device_id, &request.device_secret, &handle).await?;
        let address = ctx.extensions().get::<Forwarding>().and_then(counted_address);
        let (address, key) = device.map_or_else(
            || (address.map(Key::address), Key::Handle(handle.clone())),
            |device| (None, Key::Device(device)),
        );
        let now = Instant::now();
        {
            let throttle = &mut self.logins().throttle;
            for key in address.iter().chain([&key]) {
                throttle.attempt(key, now).map_err(throttled)?;
            }
        }
        // One statement for every handle, so that one without a password takes no longer to answer: the account's
        // credential identifier, record and parameters, and the parameters of the account a fake copies.
        let (credential, record, params, real): LoginRow = sqlx::query_as(
            "SELECT p.credential, p.record, p.ksf_params, (
                SELECT ksf_params FROM password_records ORDER BY user_id
                OFFSET (SELECT $2 % greatest(count(*), 1) FROM password_records) LIMIT 1
            )
            FROM (VALUES (1)) one
            LEFT JOIN users u ON (u.handle = $1 OR u.email = $1) AND u.status = 'active'
            LEFT JOIN password_records p ON p.user_id = u.id",
        )
        .bind(&handle)
        .bind(fake_pick(&self.key, &handle))
        .fetch_one(&self.pool)
        .await
        .map_err(db)?;
        let fake = fake_ksf_params(&self.key, &handle, real.as_deref());
        // A credential identifier starts with the account id.
        let user = credential
            .as_ref()
            .and_then(|credential| Uuid::from_slice(credential.get(..16)?).ok());
        let (credential, ksf_params) = match (credential, params) {
            (Some(credential), Some(params)) => (credential, params),
            _ => (handle.clone().into_bytes(), fake),
        };
        let (ke2, state) = login_start(&mut OsRng, &self.key, record.as_deref(), &request.ke1, &credential)
            .ok_or_else(|| invalid("ke1"))?;
        let pending = Pending::Password { key, user, state };
        let id = self.hold(pending, LOGIN_WINDOW)?;
        Ok(StartLoginResponse {
            login_id: id.to_string(),
            ke2,
            ksf_params,
            ..Default::default()
        }
        .into())
    }

    async fn finish_login(
        &self,
        _ctx: RequestContext,
        request: ServiceRequest<'_, FinishLoginRequest>,
    ) -> ServiceResult<FinishLoginResponse> {
        let request = request.to_owned_message();
        let device = checked(request.device.into_option())?;
        let Some((_, _, Pending::Password { key, user, state })) = self.take(&request.login_id) else {
            return Err(login_failed());
        };
        // A fake login is checked like a real one, so that it takes as long to fail.
        let user = match (login_finish(state, &request.ke3), user) {
            (true, Some(user)) => user,
            _ => return Err(login_failed()),
        };
        let (totp, passkeys, codes) = self.factors(user).await?;
        if !totp && passkeys.is_empty() {
            self.logins().throttle.succeeded(&key);
            return Ok(FinishLoginResponse {
                session: self.open_session(user, &device, true).await?.into(),
                password_path: self.password_path(user).await?.into(),
                ..Default::default()
            }
            .into());
        }
        // The handle or device stays counted until a second factor answers, so that every guess costs a sign-in.
        let challenge = random(32);
        let (factors, passkey_options_json) = self.offer((totp, passkeys, codes), &challenge, false);
        let pending = Pending::SecondFactor {
            key,
            user,
            device,
            challenge,
            wrong: 0,
        };
        let login_id = self.hold(pending, CEREMONY_WINDOW)?.to_string();
        Ok(FinishLoginResponse {
            second_factor: SecondFactorChallenge {
                login_id,
                factors,
                passkey_options_json,
                ..Default::default()
            }
            .into(),
            ..Default::default()
        }
        .into())
    }

    async fn rotate_session(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, RotateSessionRequest>,
    ) -> ServiceResult<RotateSessionResponse> {
        let caller = self.signed_in(&ctx).await?;
        let used = bearer(ctx.headers()).map(token_hash).ok_or_else(signed_out)?;
        let token = new_token();
        // The token used keeps working for a day, unless it is already the old one, whose day has begun.
        let expires_at: i64 = sqlx::query_scalar(&format!(
            "UPDATE sessions SET token_hash = $2, expires_at = now() + interval '90 days', previous_token_hash = $3,
                previous_expires_at = CASE WHEN token_hash = $3 THEN now() + interval '24 hours'
                    ELSE previous_expires_at END
             WHERE id = $1::uuid RETURNING {EXPIRES_AT}"
        ))
        .bind(caller.session.to_string())
        .bind(token_hash(&token))
        .bind(used)
        .fetch_optional(&self.pool)
        .await
        .map_err(db)?
        .ok_or_else(signed_out)?;
        Ok(RotateSessionResponse {
            session: session(token, expires_at, caller.device, caller.user).into(),
            ..Default::default()
        }
        .into())
    }

    async fn list_devices(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, ListDevicesRequest>,
    ) -> ServiceResult<ListDevicesResponse> {
        let caller = self.signed_in(&ctx).await?;
        let rows: Vec<(String, String, String, String, i64, Option<i64>)> = sqlx::query_as(
            "SELECT id::text, name, platform, coalesce(app_version, ''), (extract(EPOCH FROM created_at) * 1e6)::bigint,
                (extract(EPOCH FROM last_seen_at) * 1e6)::bigint
             FROM devices d WHERE user_id = $1::uuid
                AND EXISTS (SELECT 1 FROM sessions s WHERE s.device_id = d.id AND s.expires_at > now())
             ORDER BY last_seen_at DESC NULLS LAST, id",
        )
        .bind(caller.user.to_string())
        .fetch_all(&self.pool)
        .await
        .map_err(db)?;
        let devices = rows
            .into_iter()
            .map(|(id, name, platform, app_version, created_at, last_seen_at)| Device {
                current: id == caller.device.to_string(),
                device_id: id,
                name,
                platform,
                app_version,
                created_at: Some(timestamp(created_at)).into(),
                last_seen_at: last_seen_at.map(timestamp).into(),
                ..Default::default()
            })
            .collect();
        Ok(ListDevicesResponse {
            devices,
            ..Default::default()
        }
        .into())
    }

    async fn report_backup(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, ReportBackupRequest>,
    ) -> ServiceResult<ReportBackupResponse> {
        let caller = self.signed_in(&ctx).await?;
        let pending = request.to_owned_message().pending_count;
        if pending < 0 {
            return Err(invalid("pending_count"));
        }
        sqlx::query(
            "INSERT INTO device_backups (device_id, pending) VALUES ($1, $2)
             ON CONFLICT (device_id) DO UPDATE SET reported_at = now(), pending = excluded.pending",
        )
        .bind(caller.device)
        .bind(pending)
        .execute(&self.pool)
        .await
        .map_err(db)?;
        Ok(ReportBackupResponse::default().into())
    }

    async fn revoke_device(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, RevokeDeviceRequest>,
    ) -> ServiceResult<RevokeDeviceResponse> {
        let caller = self.signed_in(&ctx).await?;
        let not_found = || ApiError::new(ErrorCode::NotFound, "device.not_found");
        let device: Uuid = request.to_owned_message().device_id.parse().map_err(|_| not_found())?;
        let mut tx = self.pool.begin().await.map_err(db)?;
        // Signing out keeps the device known, so that its secret still proves it at its next sign-in.
        let query = if device == caller.device {
            "DELETE FROM sessions WHERE device_id IN (SELECT id FROM devices WHERE id = $1::uuid AND user_id = $2::uuid)"
        } else {
            "DELETE FROM devices WHERE id = $1::uuid AND user_id = $2::uuid"
        };
        let deleted = sqlx::query(query)
            .bind(device.to_string())
            .bind(caller.user.to_string())
            .execute(&mut *tx)
            .await
            .map_err(db)?;
        if deleted.rows_affected() == 0 {
            return Err(not_found().into());
        }
        audit(&mut tx, caller.user, "device.revoke", caller.user, Some(device))
            .await
            .map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(RevokeDeviceResponse::default().into())
    }

    async fn start_oidc(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, StartOidcRequest>,
    ) -> ServiceResult<StartOidcResponse> {
        Ok(self.oidc_start(&ctx, request.to_owned_message()).await?.into())
    }

    async fn complete_oidc(
        &self,
        _ctx: RequestContext,
        request: ServiceRequest<'_, CompleteOidcRequest>,
    ) -> ServiceResult<CompleteOidcResponse> {
        Ok(self.oidc_complete(request.to_owned_message()).await?.into())
    }

    async fn finish_second_factor(
        &self,
        _ctx: RequestContext,
        request: ServiceRequest<'_, FinishSecondFactorRequest>,
    ) -> ServiceResult<FinishSecondFactorResponse> {
        let request = request.to_owned_message();
        let Some((
            id,
            expires,
            Pending::SecondFactor {
                key,
                user,
                device,
                challenge,
                wrong,
            },
        )) = self.take(&request.login_id)
        else {
            return Err(login_failed());
        };
        let right = match &request.answer {
            Some(Answer::TotpCode(code)) => self.totp_counts(user, code).await?,
            Some(Answer::RecoveryCode(code)) => self.recovery_code_counts(user, code).await?,
            Some(Answer::PasskeyCredentialJson(credential)) => {
                self.passkey_signer(&challenge, credential, false).await? == Some(user)
            }
            None => false,
        };
        if !right {
            if wrong + 1 < MAX_WRONG {
                let wrong = wrong + 1;
                let pending = Pending::SecondFactor {
                    key,
                    user,
                    device,
                    challenge,
                    wrong,
                };
                self.put_back(id, expires, pending);
            }
            return Err(login_failed());
        }
        self.logins().throttle.succeeded(&key);
        Ok(FinishSecondFactorResponse {
            session: self.open_session(user, &device, true).await?.into(),
            password_path: self.password_path(user).await?.into(),
            ..Default::default()
        }
        .into())
    }

    async fn start_passkey_login(
        &self,
        _ctx: RequestContext,
        _request: ServiceRequest<'_, StartPasskeyLoginRequest>,
    ) -> ServiceResult<StartPasskeyLoginResponse> {
        let challenge = random(32);
        let options_json = webauthn::request_options(self.rp()?, &challenge, &[], true);
        let login_id = self.hold(Pending::Passkey { challenge }, CEREMONY_WINDOW)?;
        Ok(StartPasskeyLoginResponse {
            login_id: login_id.to_string(),
            options_json,
            ..Default::default()
        }
        .into())
    }

    async fn finish_passkey_login(
        &self,
        _ctx: RequestContext,
        request: ServiceRequest<'_, FinishPasskeyLoginRequest>,
    ) -> ServiceResult<FinishPasskeyLoginResponse> {
        let request = request.to_owned_message();
        let device = checked(request.device.into_option())?;
        let Some((_, _, Pending::Passkey { challenge })) = self.take(&request.login_id) else {
            return Err(login_failed());
        };
        let signer = self.passkey_signer(&challenge, &request.credential_json, true);
        let user = signer.await?.ok_or_else(login_failed)?;
        Ok(FinishPasskeyLoginResponse {
            session: self.open_session(user, &device, true).await?.into(),
            ..Default::default()
        }
        .into())
    }

    async fn start_passkey_setup(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, StartPasskeySetupRequest>,
    ) -> ServiceResult<StartPasskeySetupResponse> {
        let caller = self.signed_in(&ctx).await?;
        let rp = self.rp()?;
        self.fresh(&caller, true).await?;
        let (handle, name, existing): (String, String, Vec<Vec<u8>>) = sqlx::query_as(
            "SELECT handle, display_name,
                coalesce((SELECT array_agg(credential_id) FROM passkeys WHERE user_id = u.id), '{}')
             FROM users u WHERE id = $1::uuid",
        )
        .bind(caller.user.to_string())
        .fetch_one(&self.pool)
        .await
        .map_err(db)?;
        let challenge = random(32);
        let user = caller.user.as_bytes();
        let options_json = webauthn::creation_options(rp, &challenge, user, &handle, &name, &existing);
        let pending = Pending::PasskeySetup {
            user: caller.user,
            challenge,
        };
        let setup_id = self.hold(pending, CEREMONY_WINDOW)?.to_string();
        Ok(StartPasskeySetupResponse {
            setup_id,
            options_json,
            ..Default::default()
        }
        .into())
    }

    async fn finish_passkey_setup(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, FinishPasskeySetupRequest>,
    ) -> ServiceResult<FinishPasskeySetupResponse> {
        let caller = self.signed_in(&ctx).await?;
        let request = request.to_owned_message();
        let name = request.name.trim();
        if !printable(name, 100) {
            return Err(invalid("name"));
        }
        let rp = self.rp()?;
        let Some((_, _, Pending::PasskeySetup { user, challenge })) = self.take(&request.setup_id) else {
            return Err(setup_expired());
        };
        if user != caller.user {
            return Err(setup_expired());
        }
        let credential =
            webauthn::register(rp, &challenge, &request.credential_json).map_err(|_| invalid("credential_json"))?;
        let mut tx = self.pool.begin().await.map_err(db)?;
        let id = Uuid::now_v7();
        let created_at: Option<i64> = sqlx::query_scalar(&format!(
            "INSERT INTO passkeys (id, user_id, credential_id, public_key, sign_count, name)
             VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6) ON CONFLICT (credential_id) DO NOTHING
             RETURNING {CREATED_AT}"
        ))
        .bind(id.to_string())
        .bind(user.to_string())
        .bind(&credential.id)
        .bind(&credential.public_key)
        .bind(i64::from(credential.sign_count))
        .bind(name)
        .fetch_optional(&mut *tx)
        .await
        .map_err(db)?;
        let created_at = created_at.ok_or_else(|| ApiError::new(ErrorCode::AlreadyExists, "passkey.exists"))?;
        let recovery_codes = first_recovery_codes(&mut tx, user).await?;
        audit(&mut tx, user, "passkey.create", user, None).await.map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(FinishPasskeySetupResponse {
            passkey: Passkey {
                passkey_id: id.to_string(),
                name: name.into(),
                created_at: Some(timestamp(created_at)).into(),
                ..Default::default()
            }
            .into(),
            recovery_codes,
            ..Default::default()
        }
        .into())
    }

    async fn start_totp_setup(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, StartTotpSetupRequest>,
    ) -> ServiceResult<StartTotpSetupResponse> {
        let caller = self.signed_in(&ctx).await?;
        let (handle, replaces): (String, bool) = sqlx::query_as(
            "SELECT handle, EXISTS (SELECT FROM totp_secrets WHERE user_id = u.id) FROM users u WHERE id = $1::uuid",
        )
        .bind(caller.user.to_string())
        .fetch_one(&self.pool)
        .await
        .map_err(db)?;
        if replaces {
            self.fresh(&caller, false).await?;
        }
        let account = match &self.rp {
            Some(rp) => format!("{handle}@{}", rp.id),
            None => handle,
        };
        let secret = random(20);
        let (encoded, uri) = (totp::base32(&secret), totp::uri("Photolib", &account, &secret));
        let pending = Pending::TotpSetup {
            user: caller.user,
            secret,
            replaces,
        };
        Ok(StartTotpSetupResponse {
            setup_id: self.hold(pending, TOTP_WINDOW)?.to_string(),
            secret: encoded,
            uri,
            ..Default::default()
        }
        .into())
    }

    async fn finish_totp_setup(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, FinishTotpSetupRequest>,
    ) -> ServiceResult<FinishTotpSetupResponse> {
        let caller = self.signed_in(&ctx).await?;
        let request = request.to_owned_message();
        let Some((id, expires, Pending::TotpSetup { user, secret, replaces })) = self.take(&request.setup_id) else {
            return Err(setup_expired());
        };
        if user != caller.user {
            return Err(setup_expired());
        }
        let Some(step) = totp::matching_step(&secret, &request.code, now_step()) else {
            self.put_back(id, expires, Pending::TotpSetup { user, secret, replaces });
            return Err(invalid("code"));
        };
        let mut tx = self.pool.begin().await.map_err(db)?;
        // A secret that appeared since a setup started without a proof stays.
        let set = sqlx::query(
            "INSERT INTO totp_secrets (user_id, secret, last_step) VALUES ($1::uuid, $2, $3)
             ON CONFLICT (user_id) DO UPDATE SET secret = $2, last_step = $3, created_at = now() WHERE $4",
        )
        .bind(user.to_string())
        .bind(&secret)
        .bind(step as i64)
        .bind(replaces)
        .execute(&mut *tx)
        .await
        .map_err(db)?;
        if set.rows_affected() == 0 {
            return Err(step_up_required());
        }
        let recovery_codes = first_recovery_codes(&mut tx, user).await?;
        audit(&mut tx, user, "totp.enable", user, None).await.map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(FinishTotpSetupResponse {
            recovery_codes,
            ..Default::default()
        }
        .into())
    }

    async fn list_second_factors(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, ListSecondFactorsRequest>,
    ) -> ServiceResult<ListSecondFactorsResponse> {
        let caller = self.signed_in(&ctx).await?;
        let rows: Vec<(String, String, i64, Option<i64>)> = sqlx::query_as(&format!(
            "SELECT id::text, name, {CREATED_AT}, {LAST_USED_AT} FROM passkeys WHERE user_id = $1::uuid
             ORDER BY created_at, id"
        ))
        .bind(caller.user.to_string())
        .fetch_all(&self.pool)
        .await
        .map_err(db)?;
        let (totp, left): (bool, i64) = sqlx::query_as(
            "SELECT EXISTS (SELECT FROM totp_secrets WHERE user_id = $1::uuid),
                (SELECT count(*) FROM recovery_codes WHERE user_id = $1::uuid)",
        )
        .bind(caller.user.to_string())
        .fetch_one(&self.pool)
        .await
        .map_err(db)?;
        let passkeys = rows
            .into_iter()
            .map(|(id, name, created_at, last_used_at)| Passkey {
                passkey_id: id,
                name,
                created_at: Some(timestamp(created_at)).into(),
                last_used_at: last_used_at.map(timestamp).into(),
                ..Default::default()
            })
            .collect();
        Ok(ListSecondFactorsResponse {
            passkeys,
            totp,
            recovery_codes_left: left as u32,
            ..Default::default()
        }
        .into())
    }

    async fn delete_passkey(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, DeletePasskeyRequest>,
    ) -> ServiceResult<DeletePasskeyResponse> {
        let caller = self.signed_in(&ctx).await?;
        self.fresh(&caller, false).await?;
        let not_found = || ApiError::new(ErrorCode::NotFound, "passkey.not_found");
        let id = request.to_owned_message().passkey_id;
        let id: Uuid = id.parse().map_err(|_| not_found())?;
        let mut tx = self.pool.begin().await.map_err(db)?;
        let deleted = sqlx::query("DELETE FROM passkeys WHERE id = $1::uuid AND user_id = $2::uuid")
            .bind(id.to_string())
            .bind(caller.user.to_string())
            .execute(&mut *tx)
            .await
            .map_err(db)?;
        if deleted.rows_affected() == 0 {
            return Err(not_found().into());
        }
        audit(&mut tx, caller.user, "passkey.delete", caller.user, None)
            .await
            .map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(DeletePasskeyResponse::default().into())
    }

    async fn delete_totp(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, DeleteTotpRequest>,
    ) -> ServiceResult<DeleteTotpResponse> {
        let caller = self.signed_in(&ctx).await?;
        self.fresh(&caller, false).await?;
        let mut tx = self.pool.begin().await.map_err(db)?;
        let deleted = sqlx::query("DELETE FROM totp_secrets WHERE user_id = $1::uuid")
            .bind(caller.user.to_string())
            .execute(&mut *tx)
            .await
            .map_err(db)?;
        if deleted.rows_affected() > 0 {
            audit(&mut tx, caller.user, "totp.disable", caller.user, None)
                .await
                .map_err(db)?;
        }
        tx.commit().await.map_err(db)?;
        Ok(DeleteTotpResponse::default().into())
    }

    async fn create_recovery_codes(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, CreateRecoveryCodesRequest>,
    ) -> ServiceResult<CreateRecoveryCodesResponse> {
        let caller = self.signed_in(&ctx).await?;
        self.fresh(&caller, false).await?;
        let mut tx = self.pool.begin().await.map_err(db)?;
        let recovery_codes = replace_recovery_codes(&mut tx, caller.user).await?;
        tx.commit().await.map_err(db)?;
        Ok(CreateRecoveryCodesResponse {
            recovery_codes,
            ..Default::default()
        }
        .into())
    }

    async fn start_step_up(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, StartStepUpRequest>,
    ) -> ServiceResult<StartStepUpResponse> {
        let caller = self.signed_in(&ctx).await?;
        let ke1 = request.to_owned_message().ke1;
        let (handle, credential, record, params): StepUpRow = sqlx::query_as(
            "SELECT u.handle, p.credential, p.record, p.ksf_params
             FROM users u LEFT JOIN password_records p ON p.user_id = u.id WHERE u.id = $1::uuid",
        )
        .bind(caller.user.to_string())
        .fetch_one(&self.pool)
        .await
        .map_err(db)?;
        let now = Instant::now();
        let key = Key::Handle(handle.clone());
        self.logins().throttle.attempt(&key, now).map_err(throttled)?;
        let mut response = StartStepUpResponse::default();
        let password = if ke1.is_empty() {
            None
        } else {
            // Without a password, a fake KE2 that no KE3 opens.
            let credential = credential.unwrap_or_else(|| handle.clone().into_bytes());
            let started = login_start(&mut OsRng, &self.key, record.as_deref(), &ke1, &credential);
            let (ke2, state) = started.ok_or_else(|| invalid("ke1"))?;
            response.ke2 = ke2;
            response.ksf_params = params.unwrap_or_else(|| fake_ksf_params(&self.key, &handle, None));
            Some(state)
        };
        let challenge = random(32);
        (response.factors, response.passkey_options_json) =
            self.offer(self.factors(caller.user).await?, &challenge, true);
        let pending = Pending::StepUp {
            session: caller.session,
            handle,
            password,
            challenge,
        };
        response.step_up_id = self.hold(pending, CEREMONY_WINDOW)?.to_string();
        Ok(response.into())
    }

    async fn finish_step_up(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, FinishStepUpRequest>,
    ) -> ServiceResult<FinishStepUpResponse> {
        let caller = self.signed_in(&ctx).await?;
        let request = request.to_owned_message();
        let Some((
            _,
            _,
            Pending::StepUp {
                session,
                handle,
                password,
                challenge,
            },
        )) = self.take(&request.step_up_id)
        else {
            return Err(login_failed());
        };
        let user = caller.user;
        let right = session == caller.session
            && match request.answer {
                Some(StepUpAnswer::Ke3(ke3)) => password.is_some_and(|state| login_finish(state, &ke3)),
                Some(StepUpAnswer::TotpCode(code)) => self.totp_counts(user, &code).await?,
                Some(StepUpAnswer::RecoveryCode(code)) => self.recovery_code_counts(user, &code).await?,
                Some(StepUpAnswer::PasskeyCredentialJson(credential)) => {
                    self.passkey_signer(&challenge, &credential, true).await? == Some(user)
                }
                None => false,
            };
        if !right {
            return Err(login_failed());
        }
        self.logins().throttle.succeeded(&Key::Handle(handle));
        let mut tx = self.pool.begin().await.map_err(db)?;
        sqlx::query("UPDATE sessions SET proved_at = now() WHERE id = $1::uuid")
            .bind(session.to_string())
            .execute(&mut *tx)
            .await
            .map_err(db)?;
        audit(&mut tx, user, "session.step_up", user, Some(caller.device))
            .await
            .map_err(db)?;
        tx.commit().await.map_err(db)?;
        Ok(FinishStepUpResponse::default().into())
    }
}

#[cfg(test)]
mod factor_tests;

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use axum::http::StatusCode;
    use base64::{Engine, engine::general_purpose::STANDARD};
    use opaque_ke::{
        ClientLogin, ClientLoginFinishParameters, ClientRegistration, ClientRegistrationFinishParameters,
        CredentialResponse, Identifiers, RegistrationResponse,
    };
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use photolib_proto::proto::photolib::api::v1::{User, UserRole, UserStatus};
    use serde_json::{Value, json};

    use super::*;
    use crate::{
        accounts::Accounts,
        auth::CONTEXT,
        keys::ApiKeys,
        rpc::{
            Users,
            account_keys::tests::{Enrolment, PARAMS, password},
        },
        testing::{Replay, call},
    };

    /// Argon2id at 256 MiB × 3: what the client claims; the test client's KSF is the identity, which the server cannot
    /// tell apart.
    const KSF_PARAMS: [u8; 26] = [
        1, 0, 4, 0, 0, 0, 0, 0, 3, 1, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
    ];

    pub(super) struct Server {
        pub(super) app: axum::Router,
        auth: Arc<Auth>,
        accounts: Accounts,
        pub(super) pool: PgPool,
        root: Uuid,
    }

    /// A server with passkeys, the admin console and the administrator root, who has no password yet.
    pub(super) async fn server() -> Server {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let accounts = Accounts::new(db.pool.clone());
        let root = User {
            handle: "root".into(),
            display_name: "Root".into(),
            ..Default::default()
        };
        let (root, _) = accounts.create_first_admin(root).await.unwrap();
        let auth = Auth::new(db.pool.clone(), ServerSetup::new(&mut OsRng));
        let auth = Arc::new(auth.with_passkeys(Some(crate::webauthn::tests::rp())));
        let keys = ApiKeys::new(db.pool.clone());
        let users = Users::start(accounts.clone(), keys, auth.clone()).await.unwrap();
        let doctor = crate::doctor::Doctor {
            config: crate::testing::config(&[crate::role::Role::Api], std::path::Path::new("/data")),
            pool: Some(db.pool.clone()),
            seen: None,
            tail: None,
            ml: None,
        };
        let admin = super::super::Admin::new(db.pool.clone(), Arc::new(doctor));
        Server {
            app: super::super::api(
                Uuid::now_v7().to_string(),
                Some(Arc::new(users)),
                Some(auth.clone()),
                Some(admin),
            ),
            auth,
            accounts,
            pool: db.pool,
            root: root.user_id.parse().unwrap(),
        }
    }

    impl Server {
        /// Another process on the same database, with `key` and no passkeys.
        pub(super) fn with_key(&self, key: ServerSetup<Suite>) -> axum::Router {
            let auth = Arc::new(Auth::new(self.pool.clone(), key));
            super::super::api(Uuid::now_v7().to_string(), None, Some(auth), None)
        }

        pub(super) async fn person(&self, handle: &str) -> (Uuid, String) {
            let user = User {
                handle: handle.into(),
                display_name: handle.into(),
                role: UserRole::USER_ROLE_USER.into(),
                ..Default::default()
            };
            let user = self.accounts.create(self.root, user).await.unwrap();
            let user: Uuid = user.user_id.parse().unwrap();
            let mut conn = self.pool.acquire().await.unwrap();
            let setup = crate::auth::issue_password_setup(&mut conn, self.root, user);
            (user, setup.await.unwrap().token)
        }

        /// A session of the administrator root, whose password becomes "pw".
        pub(super) async fn admin(&self) -> Value {
            let mut conn = self.pool.acquire().await.unwrap();
            let setup = crate::auth::issue_password_setup(&mut conn, self.root, self.root);
            let token = setup.await.unwrap().token;
            assert_eq!(set_password(&self.app, "pw", &token, None).await.0, StatusCode::OK);
            login(&self.app, "root", "pw", phone()).await.unwrap()
        }
    }

    fn bytes(value: &Value) -> Vec<u8> {
        STANDARD.decode(value.as_str().unwrap_or_default()).unwrap()
    }

    /// Sets `password` with a setup token, or with the session `bearer` when the token is empty.
    pub(super) async fn set_password(
        app: &axum::Router,
        password: &str,
        token: &str,
        bearer: Option<&str>,
    ) -> (StatusCode, Value) {
        set_password_with(app, password, token, bearer, json!({})).await
    }

    /// As `set_password`, with the fields of `finish` in FinishPasswordSetup's request.
    async fn set_password_with(
        app: &axum::Router,
        password: &str,
        token: &str,
        bearer: Option<&str>,
        fields: Value,
    ) -> (StatusCode, Value) {
        let start = ClientRegistration::<Suite>::start(&mut OsRng, password.as_bytes()).unwrap();
        let request = STANDARD.encode(start.message.serialize());
        let body = json!({ "registrationRequest": request, "passwordSetupToken": token });
        let (status, started) = call(app, "AuthService/StartPasswordSetup", bearer, body).await;
        if !status.is_success() {
            return (status, started);
        }
        let response = RegistrationResponse::deserialize(&bytes(&started["registrationResponse"]));
        let finish = start
            .state
            .finish(
                &mut OsRng,
                password.as_bytes(),
                response.unwrap(),
                ClientRegistrationFinishParameters::default(),
            )
            .unwrap();
        let mut body = json!({
            "registrationRecord": STANDARD.encode(finish.message.serialize()),
            "ksfParams": STANDARD.encode(KSF_PARAMS),
            "passwordSetupToken": token,
            "registrationId": started["registrationId"],
        });
        body.as_object_mut()
            .unwrap()
            .extend(fields.as_object().unwrap().clone());
        call(app, "AuthService/FinishPasswordSetup", bearer, body).await
    }

    /// Signs in as `handle` on `device`: the session, or the error, or "wrong password" when KE2 already shows it.
    async fn login(app: &axum::Router, handle: &str, password: &str, device: Value) -> Result<Value, Value> {
        let finished = attempt(app, handle, password, device).await?;
        Ok(finished["session"].clone())
    }

    /// Signs in with a password as `login` does, but returns FinishLogin's answer.
    pub(super) async fn attempt(
        app: &axum::Router,
        handle: &str,
        password: &str,
        device: Value,
    ) -> Result<Value, Value> {
        let start = ClientLogin::<Suite>::start(&mut OsRng, password.as_bytes()).unwrap();
        let mut device = device;
        let secret = device.as_object_mut().unwrap().remove("deviceSecret");
        let body = json!({
            "handle": handle,
            "ke1": STANDARD.encode(start.message.serialize()),
            "deviceId": device["deviceId"],
            "deviceSecret": secret,
        });
        let (status, started) = call(app, "AuthService/StartLogin", None, body).await;
        if !status.is_success() {
            return Err(started);
        }
        assert_eq!(bytes(&started["ksfParams"]).len(), 26, "{started}");
        let ke2 = CredentialResponse::deserialize(&bytes(&started["ke2"])).unwrap();
        let parameters = ClientLoginFinishParameters::new(Some(CONTEXT), Identifiers::default(), None);
        let Ok(finish) = start.state.finish(&mut OsRng, password.as_bytes(), ke2, parameters) else {
            return Err(json!("wrong password"));
        };
        let body = json!({
            "loginId": started["loginId"],
            "ke3": STANDARD.encode(finish.message.serialize()),
            "device": device,
        });
        let (status, finished) = call(app, "AuthService/FinishLogin", None, body).await;
        status.is_success().then_some(finished.clone()).ok_or(finished)
    }

    pub(super) fn phone() -> Value {
        json!({ "name": "Ann's Pixel", "platform": "android", "appVersion": "0.4.0" })
    }

    pub(super) fn token(session: &Value) -> Option<&str> {
        session["token"].as_str()
    }

    #[tokio::test]
    async fn a_person_sets_their_password_with_a_setup_token_and_signs_in_on_a_device() {
        let server = server().await;
        let (ann, setup) = server.person("ann").await;
        assert_eq!(
            set_password(&server.app, "correct horse", &setup, None).await,
            (StatusCode::OK, json!({}))
        );
        let session = login(&server.app, "Ann ", "correct horse", phone()).await.unwrap();
        assert_eq!(session["userId"], ann.to_string());
        let token = token(&session).unwrap();
        assert!(
            token.len() == 64 && token.bytes().all(|b| b.is_ascii_hexdigit()),
            "{token}"
        );
        let (status, devices) = devices(&server.app, &session).await;
        assert_eq!(status, StatusCode::OK, "{devices}");
        let device = &devices["devices"][0];
        assert_eq!(
            (
                &device["deviceId"],
                &device["name"],
                &device["platform"],
                &device["appVersion"],
                &device["current"]
            ),
            (
                &session["deviceId"],
                &json!("Ann's Pixel"),
                &json!("android"),
                &json!("0.4.0"),
                &json!(true)
            )
        );
        assert_eq!(
            login(&server.app, "ann", "correct horsf", phone()).await,
            Err(json!("wrong password"))
        );
        assert_eq!(
            set_password(&server.app, "another", &setup, None).await,
            (
                StatusCode::FORBIDDEN,
                json!({ "code": "permission_denied", "reason": "password_setup.invalid" })
            ),
            "a setup token works once"
        );
    }

    #[tokio::test]
    async fn a_person_signs_in_with_their_email_as_with_their_handle() {
        let server = server().await;
        let user = User {
            handle: "ann".into(),
            display_name: "Ann".into(),
            email: "ann@example.org".into(),
            role: UserRole::USER_ROLE_USER.into(),
            ..Default::default()
        };
        let ann = server.accounts.create(server.root, user).await.unwrap();
        let mut conn = server.pool.acquire().await.unwrap();
        let ann: Uuid = ann.user_id.parse().unwrap();
        let setup = crate::auth::issue_password_setup(&mut conn, server.root, ann);
        let setup = setup.await.unwrap().token;
        set_password(&server.app, "pw", &setup, None).await;
        let session = login(&server.app, " Ann@Example.org", "pw", phone()).await;
        assert_eq!(session.unwrap()["userId"], ann.to_string());
        for (who, password) in [("ann@example.org", "pv"), ("bob@example.org", "pw")] {
            assert_eq!(
                login(&server.app, who, password, phone()).await,
                Err(json!("wrong password")),
                "{who}"
            );
        }
        let long = format!("{}@example.org", "a".repeat(243));
        assert_eq!(
            login(&server.app, &long, "pw", phone()).await,
            Err(json!({ "code": "invalid_argument", "reason": "field.invalid", "field": "handle" })),
            "no email is that long"
        );
    }

    /// A person whose password is "pw", with a session on each of `devices`.
    pub(super) async fn signed_in(server: &Server, handle: &str, devices: &[&str]) -> (Uuid, Vec<Value>) {
        let (user, setup) = server.person(handle).await;
        assert_eq!(set_password(&server.app, "pw", &setup, None).await.0, StatusCode::OK);
        let mut sessions = Vec::new();
        for name in devices {
            let device = json!({ "name": name, "platform": "linux" });
            sessions.push(login(&server.app, handle, "pw", device).await.unwrap());
        }
        (user, sessions)
    }

    async fn devices(app: &axum::Router, session: &Value) -> (StatusCode, Value) {
        call(app, "AuthService/ListDevices", token(session), json!({})).await
    }

    fn names(devices: &Value) -> Vec<&str> {
        let devices = devices["devices"].as_array().unwrap();
        devices.iter().map(|device| device["name"].as_str().unwrap()).collect()
    }

    #[tokio::test]
    async fn a_device_reports_its_own_backup() {
        let server = server().await;
        let (_, sessions) = signed_in(&server, "ann", &["phone", "laptop"]).await;
        let report = async |session: Option<&Value>, pending: i64| {
            let body = json!({ "pendingCount": pending });
            call(&server.app, "AuthService/ReportBackup", session.and_then(token), body).await
        };
        let backups = async || {
            sqlx::query_as::<_, (String, i64)>(
                "SELECT d.name, b.pending FROM device_backups b JOIN devices d ON d.id = b.device_id ORDER BY 1",
            )
            .fetch_all(&server.pool)
            .await
            .unwrap()
        };
        assert_eq!(report(Some(&sessions[0]), 12).await, (StatusCode::OK, json!({})));
        assert_eq!(report(Some(&sessions[0]), 3).await.0, StatusCode::OK);
        assert_eq!(backups().await, [("phone".into(), 3)]);
        let invalid = json!({ "code": "invalid_argument", "reason": "field.invalid", "field": "pending_count" });
        assert_eq!(report(Some(&sessions[1]), -1).await, (StatusCode::BAD_REQUEST, invalid));
        let signed_out = json!({ "code": "unauthenticated", "reason": "session.required" });
        assert_eq!(report(None, 1).await, (StatusCode::UNAUTHORIZED, signed_out));
        assert_eq!(backups().await, [("phone".into(), 3)]);
    }

    #[tokio::test]
    async fn revoking_a_device_from_another_ends_its_sessions_at_its_next_request() {
        let server = server().await;
        let (ann, sessions) = signed_in(&server, "ann", &["phone", "laptop", "tablet"]).await;
        let [phone, laptop, tablet] = &sessions[..] else {
            unreachable!()
        };
        let (_, bob) = signed_in(&server, "bob", &["bob's phone"]).await;
        let signed_out = (
            StatusCode::UNAUTHORIZED,
            json!({ "code": "unauthenticated", "reason": "session.required" }),
        );
        let (status, listed) = devices(&server.app, laptop).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(names(&listed).len(), 3, "{listed}");
        let revoke = |device: &Value| json!({ "deviceId": device["deviceId"] });
        let revoked = call(&server.app, "AuthService/RevokeDevice", token(laptop), revoke(phone)).await;
        assert_eq!(revoked, (StatusCode::OK, json!({})));
        assert_eq!(devices(&server.app, phone).await, signed_out);
        let rotate = call(&server.app, "AuthService/RotateSession", token(phone), json!({})).await;
        assert_eq!(rotate, signed_out);
        let (_, listed) = devices(&server.app, laptop).await;
        assert_eq!(names(&listed).iter().filter(|name| **name == "phone").count(), 0);
        let not_found = (
            StatusCode::NOT_FOUND,
            json!({ "code": "not_found", "reason": "device.not_found" }),
        );
        for (device, by) in [(phone, laptop), (&bob[0], laptop), (laptop, &bob[0])] {
            let result = call(&server.app, "AuthService/RevokeDevice", token(by), revoke(device)).await;
            assert_eq!(result, not_found, "{device} by {by}");
        }
        let signed_out_self = call(&server.app, "AuthService/RevokeDevice", token(tablet), revoke(tablet)).await;
        assert_eq!(signed_out_self.0, StatusCode::OK);
        assert_eq!(devices(&server.app, tablet).await, signed_out);
        assert_eq!(names(&devices(&server.app, laptop).await.1), ["laptop"]);
        let disable = User {
            user_id: ann.to_string(),
            status: UserStatus::USER_STATUS_DISABLED.into(),
            ..Default::default()
        };
        server
            .accounts
            .update(server.root, disable, &["status".into()])
            .await
            .unwrap();
        assert_eq!(devices(&server.app, laptop).await, signed_out, "a disabled account");
        assert_eq!(devices(&server.app, &bob[0]).await.0, StatusCode::OK);
        let revokes: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM audit_events WHERE action = 'device.revoke' AND actor_user_id = $1::uuid",
        )
        .bind(ann.to_string())
        .fetch_one(&server.pool)
        .await
        .unwrap();
        assert_eq!(revokes, 2);
    }

    #[tokio::test]
    async fn a_rotated_session_keeps_its_old_token_until_the_new_one_is_used_or_a_day_passes() {
        let server = server().await;
        let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
        let old = &sessions[0];
        sqlx::query("UPDATE sessions SET expires_at = now() + interval '1 day'")
            .execute(&server.pool)
            .await
            .unwrap();
        let app = &server.app;
        let rotate = |session: &Value| {
            let token = token(session).map(str::to_string);
            async move {
                let (status, rotated) = call(app, "AuthService/RotateSession", token.as_deref(), json!({})).await;
                assert_eq!(status, StatusCode::OK, "{rotated}");
                rotated["session"].clone()
            }
        };
        let lost = rotate(old).await;
        let new = rotate(old).await;
        assert_ne!(token(&new), token(old));
        assert_eq!((&new["deviceId"], &new["userId"]), (&old["deviceId"], &old["userId"]));
        assert_eq!(new["deviceSecret"], Value::Null, "only a sign-in gives a device secret");
        let left: (f64, f64) = sqlx::query_as(
            "SELECT extract(EPOCH FROM expires_at - now())::float8, extract(EPOCH FROM previous_expires_at - now())::float8
             FROM sessions",
        )
        .fetch_one(&server.pool)
        .await
        .unwrap();
        assert!((89.9 * 86400.0..=90.0 * 86400.0).contains(&left.0), "{left:?}");
        assert!((23.9 * 3600.0..=24.0 * 3600.0).contains(&left.1), "{left:?}");
        assert_eq!(
            devices(&server.app, &lost).await.0,
            StatusCode::UNAUTHORIZED,
            "a retried rotation replaces it"
        );
        assert_eq!(
            devices(&server.app, old).await.0,
            StatusCode::OK,
            "a lost answer signs no device out"
        );
        assert_eq!(devices(&server.app, &new).await.0, StatusCode::OK);
        assert_eq!(
            devices(&server.app, old).await.0,
            StatusCode::UNAUTHORIZED,
            "the new token was used"
        );

        let newer = rotate(&new).await;
        sqlx::query("UPDATE sessions SET previous_expires_at = now()")
            .execute(&server.pool)
            .await
            .unwrap();
        assert_eq!(
            devices(&server.app, &new).await.0,
            StatusCode::UNAUTHORIZED,
            "a day later"
        );
        assert_eq!(devices(&server.app, &newer).await.0, StatusCode::OK);
        sqlx::query("UPDATE sessions SET expires_at = now()")
            .execute(&server.pool)
            .await
            .unwrap();
        assert_eq!(
            devices(&server.app, &newer).await.0,
            StatusCode::UNAUTHORIZED,
            "expired"
        );
    }

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    /// Every row of every table, as text.
    async fn dump(pool: &PgPool) -> String {
        let tables: Vec<String> = sqlx::query_scalar(
            "SELECT quote_ident(table_name) FROM information_schema.tables WHERE table_schema = 'public'",
        )
        .fetch_all(pool)
        .await
        .unwrap();
        let mut dump = String::new();
        for table in tables {
            let rows: String = sqlx::query_scalar(&format!(
                "SELECT coalesce(string_agg(t::text, E'\\n'), '') FROM {table} t"
            ))
            .fetch_one(pool)
            .await
            .unwrap();
            dump += &rows;
        }
        dump
    }

    #[tokio::test]
    async fn the_database_keeps_nothing_that_checks_a_password_or_opens_a_session() {
        let server = server().await;
        let password = "correct horse battery staple";
        let (_, setup) = server.person("ann").await;
        assert_eq!(
            set_password(&server.app, password, &setup, None).await.0,
            StatusCode::OK
        );
        let session = login(&server.app, "ann", password, phone()).await.unwrap();
        let dump = dump(&server.pool).await;
        assert!(
            dump.contains("password.set") && dump.contains("Ann's Pixel"),
            "the dump has the rows"
        );
        let key = server.auth.key.serialize();
        let secrets = [password, &setup, token(&session).unwrap()];
        let oprf_seed_and_private_key = [hex(&key[..64]), hex(&key[64..96])];
        for secret in secrets
            .map(|text| [text.into(), hex(text.as_bytes())])
            .iter()
            .flatten()
            .chain(&oprf_seed_and_private_key)
        {
            assert!(!dump.contains(secret.as_str()), "{secret} is in the database");
        }
        let elsewhere = server.with_key(ServerSetup::new(&mut OsRng));
        assert_eq!(
            login(&elsewhere, "ann", password, phone()).await,
            Err(json!("wrong password")),
            "without the key file, the database checks no guess, not even the right one"
        );
    }

    /// `device` as it signs in again: its id and the secret of its last sign-in.
    fn known(session: &Value) -> Value {
        json!({ "deviceId": session["deviceId"], "deviceSecret": session["deviceSecret"], "name": "phone", "platform": "ios" })
    }

    /// Whether a sign-in was refused for too many attempts, however long it must wait.
    fn locked(result: Result<Value, Value>) -> bool {
        result.is_err_and(|error| error["reason"] == "login.throttled")
    }

    #[tokio::test]
    async fn a_device_that_signed_in_before_counts_its_attempts_apart_so_guessing_locks_out_only_the_guesser() {
        let server = server().await;
        let (_, ann) = signed_in(&server, "ann", &["phone", "laptop"]).await;
        signed_in(&server, "bob", &[]).await;
        let secret = ann[0]["deviceSecret"].as_str().unwrap();
        assert!(
            secret.len() == 64 && secret.bytes().all(|b| b.is_ascii_hexdigit()),
            "{secret}"
        );
        for _ in 0..5 {
            assert!(login(&server.app, "ann", "guess", phone()).await.is_err());
        }
        assert!(
            locked(login(&server.app, "ann", "pw", phone()).await),
            "the guesser is locked out"
        );
        let again = login(&server.app, "ann", "pw", known(&ann[0])).await.unwrap();
        assert_eq!(again["deviceId"], ann[0]["deviceId"], "the phone is not");
        assert_ne!(
            again["deviceSecret"], ann[0]["deviceSecret"],
            "each sign-in gives a new secret"
        );
        assert!(
            locked(login(&server.app, "ann", "pw", known(&ann[0])).await),
            "the old one is spent"
        );
        for _ in 0..5 {
            assert!(login(&server.app, "bob", "guess", phone()).await.is_err());
        }
        assert!(
            locked(login(&server.app, "bob", "pw", known(&again)).await),
            "a device proves itself for its own account only"
        );

        let app = &server.app;
        let revoke = |by: &Value, of: &Value| {
            let (by, of) = (token(by).map(str::to_string), json!({ "deviceId": of["deviceId"] }));
            async move { call(app, "AuthService/RevokeDevice", by.as_deref(), of).await.0 }
        };
        assert_eq!(revoke(&again, &again).await, StatusCode::OK, "the phone signs out");
        let back = login(&server.app, "ann", "pw", known(&again)).await.unwrap();
        assert_eq!(back["deviceId"], ann[0]["deviceId"], "and stays known");
        assert_eq!(
            revoke(&ann[1], &back).await,
            StatusCode::OK,
            "the laptop revokes the phone"
        );
        assert!(locked(login(&server.app, "ann", "pw", known(&back)).await));

        let laptop = known(&ann[1]);
        for _ in 0..5 {
            assert_eq!(
                login(&server.app, "ann", "guess", laptop.clone()).await,
                Err(json!("wrong password"))
            );
        }
        assert!(
            locked(login(&server.app, "ann", "pw", laptop).await),
            "a known device is locked out like anyone"
        );
    }

    #[tokio::test]
    async fn attempts_without_a_known_device_also_count_per_address() {
        let server = server().await;
        let (_, ann) = signed_in(&server, "ann", &["phone"]).await;
        let from = |client: &str| {
            let client = Forwarding {
                client: Some(client.parse().unwrap()),
                ..Default::default()
            };
            server.app.clone().layer(axum::Extension(client))
        };
        let guesser = from("2001:db8:1:2::7");
        for n in 0..30 {
            let handle = format!("h{}", n / 5);
            assert_eq!(
                login(&guesser, &handle, "guess", phone()).await,
                Err(json!("wrong password"))
            );
        }
        let neighbour = from("2001:db8:1:2:ffff::1");
        assert!(
            locked(login(&neighbour, "ann", "pw", phone()).await),
            "one /64 is one client"
        );
        assert!(
            login(&neighbour, "ann", "pw", known(&ann[0])).await.is_ok(),
            "a known device counts apart"
        );
        assert!(login(&from("203.0.113.7"), "ann", "pw", phone()).await.is_ok());
        let local = from("127.0.0.1");
        for n in 0..31 {
            assert!(login(&local, &format!("l{}", n / 5), "guess", phone()).await.is_err());
        }
        assert!(
            login(&local, "ann", "pw", phone()).await.is_ok(),
            "loopback is the host, or a proxy that named no client"
        );
        let proxy: IpAddr = "10.0.0.2".parse().unwrap();
        let unnamed = Forwarding {
            peer: Some(proxy),
            trusted: true,
            client: Some(proxy),
            ..Default::default()
        };
        let behind_trusted = server.app.clone().layer(axum::Extension(unnamed));
        for n in 0..31 {
            assert!(
                login(&behind_trusted, &format!("p{}", n / 5), "guess", phone())
                    .await
                    .is_err()
            );
        }
        assert!(
            login(&behind_trusted, "ann", "pw", phone()).await.is_ok(),
            "a trusted proxy that names no client is every client behind it"
        );
        let peer: IpAddr = "198.51.100.1".parse().unwrap();
        let claimed = Forwarding {
            peer: Some(peer),
            forwarded_for: true,
            client: Some(peer),
            ..Default::default()
        };
        let untrusted = server.app.clone().layer(axum::Extension(claimed));
        for n in 0..30 {
            assert!(
                login(&untrusted, &format!("u{}", n / 5), "guess", phone())
                    .await
                    .is_err()
            );
        }
        assert!(
            locked(login(&untrusted, "ann", "pw", phone()).await),
            "forwarded headers from an untrusted peer count for nothing: the peer is the client"
        );
    }

    #[tokio::test]
    async fn guessing_is_throttled_alike_for_known_and_unknown_handles() {
        let server = server().await;
        signed_in(&server, "ann", &[]).await;
        signed_in(&server, "bob", &[]).await;
        let throttled = |wait: u32| json!({ "code": "resource_exhausted", "reason": "login.throttled", "retry_after_seconds": wait.to_string() });
        for handle in ["ann", "nobody"] {
            for _ in 0..4 {
                assert_eq!(
                    login(&server.app, handle, "guess", phone()).await,
                    Err(json!("wrong password"))
                );
            }
            let variant = format!(" {} ", handle.to_uppercase());
            assert_eq!(
                login(&server.app, &variant, "guess", phone()).await,
                Err(json!("wrong password"))
            );
            assert_eq!(
                login(&server.app, handle, "pw", phone()).await,
                Err(throttled(30)),
                "{handle}"
            );
        }
        assert!(
            login(&server.app, "bob", "pw", phone()).await.is_ok(),
            "other handles are unaffected"
        );
        for _ in 0..4 {
            assert!(login(&server.app, "bob", "guess", phone()).await.is_err());
        }
        assert!(login(&server.app, "bob", "pw", phone()).await.is_ok());
        for _ in 0..4 {
            assert!(login(&server.app, "bob", "guess", phone()).await.is_err());
        }
        assert!(
            login(&server.app, "bob", "pw", phone()).await.is_ok(),
            "a sign-in clears the count"
        );
    }

    #[tokio::test]
    async fn an_unknown_handle_answers_like_an_account_and_logins_are_single_use() {
        let server = server().await;
        signed_in(&server, "ann", &[]).await;
        let start = |handle: &str| {
            let ke1 = ClientLogin::<Suite>::start(&mut OsRng, b"pw")
                .unwrap()
                .message
                .serialize();
            call(
                &server.app,
                "AuthService/StartLogin",
                None,
                json!({ "handle": handle, "ke1": STANDARD.encode(ke1) }),
            )
        };
        let (_, known) = start("ann").await;
        let (status, unknown) = start("nobody").await;
        assert_eq!(status, StatusCode::OK);
        for field in ["ke2", "ksfParams"] {
            assert_eq!(bytes(&known[field]).len(), bytes(&unknown[field]).len(), "{field}");
        }
        assert!(ksf_params_valid(&bytes(&unknown["ksfParams"])));
        assert_eq!(start("nobody").await.1["ksfParams"], unknown["ksfParams"]);
        let failed = (
            StatusCode::FORBIDDEN,
            json!({ "code": "permission_denied", "reason": "login.failed" }),
        );
        let finish = |login: &Value, ke3: Vec<u8>, device: Value| {
            let body = json!({ "loginId": login["loginId"], "ke3": STANDARD.encode(ke3), "device": device });
            call(&server.app, "AuthService/FinishLogin", None, body)
        };
        assert_eq!(finish(&unknown, vec![0; 64], phone()).await, failed);
        assert_eq!(
            finish(&unknown, vec![0; 64], phone()).await,
            failed,
            "a login id works once"
        );
        assert_eq!(finish(&json!({ "loginId": "x" }), vec![0; 64], phone()).await, failed);
        let invalid = |field: &str| {
            (
                StatusCode::BAD_REQUEST,
                json!({ "code": "invalid_argument", "reason": "field.invalid", "field": field }),
            )
        };
        for (device, field) in [
            (json!({ "name": " ", "platform": "web" }), "device.name"),
            (json!({ "name": "x".repeat(101), "platform": "web" }), "device.name"),
            (json!({ "name": "Pixel", "platform": "" }), "device.platform"),
            (
                json!({ "name": "Pixel", "platform": "web", "appVersion": "1\n" }),
                "device.app_version",
            ),
        ] {
            assert_eq!(finish(&known, vec![0; 64], device).await, invalid(field));
        }
        let body = json!({ "handle": "ann", "ke1": STANDARD.encode(b"short") });
        assert_eq!(
            call(&server.app, "AuthService/StartLogin", None, body).await,
            invalid("ke1")
        );
        let body = json!({ "handle": "a".repeat(65), "ke1": known["ke2"] });
        assert_eq!(
            call(&server.app, "AuthService/StartLogin", None, body).await,
            invalid("handle"),
            "no handle is that long, and the lockout keeps no such key"
        );
    }

    #[tokio::test]
    async fn signing_in_again_on_a_device_keeps_it_and_another_account_cannot_take_it() {
        let server = server().await;
        let (_, ann) = signed_in(&server, "ann", &["phone"]).await;
        let (_, bob) = signed_in(&server, "bob", &["laptop"]).await;
        let again = json!({ "deviceId": ann[0]["deviceId"], "name": "new phone", "platform": "ios" });
        let session = login(&server.app, "ann", "pw", again.clone()).await.unwrap();
        assert_eq!(session["deviceId"], ann[0]["deviceId"]);
        let (_, listed) = devices(&server.app, &session).await;
        assert_eq!(names(&listed), ["new phone"]);
        assert_eq!(listed["devices"][0]["platform"], "ios");
        let taken = login(&server.app, "bob", "pw", again).await.unwrap();
        assert_ne!(taken["deviceId"], ann[0]["deviceId"]);
        assert_eq!(names(&devices(&server.app, &bob[0]).await.1).len(), 2);
        assert_eq!(names(&devices(&server.app, &session).await.1), ["new phone"]);
    }

    #[tokio::test]
    async fn a_reset_with_a_setup_token_says_when_private_libraries_need_more_than_the_new_password() {
        let server = server().await;
        let (ann, sessions) = signed_in(&server, "ann", &["phone"]).await;
        let app = &server.app;
        let start = |token: String, bearer: Option<String>| async move {
            let request = ClientRegistration::<Suite>::start(&mut OsRng, b"new")
                .unwrap()
                .message
                .serialize();
            let body = json!({ "registrationRequest": STANDARD.encode(request), "passwordSetupToken": token });
            let (status, started) = call(app, "AuthService/StartPasswordSetup", bearer.as_deref(), body).await;
            assert_eq!(status, StatusCode::OK, "{started}");
            started["privateLibraries"].as_bool().unwrap_or_default()
        };
        let setup = || async {
            let mut conn = server.pool.acquire().await.unwrap();
            crate::auth::issue_password_setup(&mut conn, server.root, ann)
                .await
                .unwrap()
                .token
        };
        assert!(!start(setup().await, None).await, "no private library yet");
        sqlx::query(
            "INSERT INTO libraries (id, owner_id, name, kind, privacy, root_uri)
             VALUES (gen_random_uuid(), $1::uuid, 'Diary', 'managed', 'private', 'managed:diary')",
        )
        .bind(ann.to_string())
        .execute(&server.pool)
        .await
        .unwrap();
        assert!(start(setup().await, None).await, "a reset");
        let own = token(&sessions[0]).map(str::to_string);
        assert!(
            !start(String::new(), own).await,
            "a change, which knows the old password"
        );
    }

    /// Only a password sign-in returns the password path, the AMK wrapped under that password, with which a new device
    /// unlocks (design 06 §4). A new password replaces the path with the wrap its client sends or removes it, as the old
    /// password opens it no more; a reset with a setup token says so first.
    #[tokio::test]
    async fn a_password_sign_in_returns_the_password_path_that_a_new_password_replaces_or_removes() {
        let server = server().await;
        let app = &server.app;
        let (ann, sessions) = signed_in(&server, "ann", &["phone"]).await;
        let bearer = token(&sessions[0]);
        let finished = attempt(app, "ann", "pw", phone()).await.unwrap();
        assert_eq!(finished.get("passwordPath"), None, "no keys yet");
        let mut keys = Enrolment::new(ann);
        assert_eq!(
            call(app, "KeyService/CreateKeys", bearer, keys.request()).await.0,
            StatusCode::OK
        );
        let finished = attempt(app, "ann", "pw", phone()).await.unwrap();
        let path = &finished["passwordPath"];
        assert_eq!(
            (bytes(&path["wrap"]), bytes(&path["params"])),
            (keys.password.clone(), PARAMS.to_vec())
        );
        let (_, got) = call(app, "KeyService/GetKeys", bearer, json!({})).await;
        assert_eq!(
            got["keys"]["paths"][0].get("wrap"),
            None,
            "a session alone gets no password wrap"
        );
        let rewrapped = keys.path();
        let changed = json!({ "passwordPath": password(&rewrapped) });
        assert_eq!(
            set_password_with(app, "pw2", "", bearer, changed).await.0,
            StatusCode::OK
        );
        let finished = attempt(app, "ann", "pw2", phone()).await.unwrap();
        assert_eq!(bytes(&finished["passwordPath"]["wrap"]), rewrapped);
        let mut conn = server.pool.acquire().await.unwrap();
        let setup = crate::auth::issue_password_setup(&mut conn, server.root, ann);
        let setup = setup.await.unwrap().token;
        let request = ClientRegistration::<Suite>::start(&mut OsRng, b"pw3").unwrap();
        let body = json!({
            "registrationRequest": STANDARD.encode(request.message.serialize()), "passwordSetupToken": setup,
        });
        let (_, started) = call(app, "AuthService/StartPasswordSetup", None, body).await;
        assert_eq!(
            started["privateLibraries"], true,
            "a reset says the keys need more than the new password"
        );
        assert_eq!(set_password(app, "pw3", &setup, None).await.0, StatusCode::OK);
        let finished = attempt(app, "ann", "pw3", phone()).await.unwrap();
        assert_eq!(finished.get("passwordPath"), None);
        let (_, got) = call(app, "KeyService/GetKeys", token(&finished["session"]), json!({})).await;
        assert_eq!(
            got["keys"]["paths"].as_array().unwrap().len(),
            1,
            "the recovery kit is left: {got}"
        );
    }

    #[tokio::test]
    async fn a_session_changes_its_own_password_and_an_expired_setup_token_sets_none() {
        let server = server().await;
        let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
        let changed = set_password(&server.app, "new", "", token(&sessions[0])).await;
        assert_eq!(changed, (StatusCode::OK, json!({})));
        assert_eq!(
            login(&server.app, "ann", "pw", phone()).await,
            Err(json!("wrong password"))
        );
        assert!(login(&server.app, "ann", "new", phone()).await.is_ok());
        assert_eq!(
            set_password(&server.app, "x", "", None).await,
            (
                StatusCode::UNAUTHORIZED,
                json!({ "code": "unauthenticated", "reason": "session.required" })
            )
        );
        let (_, setup) = server.person("bob").await;
        sqlx::query("UPDATE password_setups SET expires_at = now()")
            .execute(&server.pool)
            .await
            .unwrap();
        assert_eq!(
            set_password(&server.app, "pw", &setup, None).await,
            (
                StatusCode::FORBIDDEN,
                json!({ "code": "permission_denied", "reason": "password_setup.invalid" })
            )
        );
        let record = json!({ "registrationRecord": "", "ksfParams": STANDARD.encode(KSF_PARAMS) });
        let call = call(
            &server.app,
            "AuthService/FinishPasswordSetup",
            token(&sessions[0]),
            record,
        )
        .await;
        assert_eq!(call.1["field"], "registration_record");
    }

    #[tokio::test]
    async fn setting_a_password_never_evaluates_the_key_of_the_one_that_signs_in() {
        let server = server().await;
        let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
        // A registration and a login that blind a guess alike: equal evaluations would let whoever holds a session or
        // a setup token test guesses offline against one KE2, past the lockout.
        let blind = || Replay(vec![7; 1024]);
        let registration = ClientRegistration::<Suite>::start(&mut blind(), b"guess").unwrap();
        let login = ClientLogin::<Suite>::start(&mut blind(), b"guess").unwrap();
        let (registration, login) = (registration.message.serialize(), login.message.serialize());
        assert_eq!(registration[..32], login[..32], "the same blinded element");
        let request = json!({ "registrationRequest": STANDARD.encode(registration) });
        let start = || {
            call(
                &server.app,
                "AuthService/StartPasswordSetup",
                token(&sessions[0]),
                request.clone(),
            )
        };
        let (first, second) = (start().await.1, start().await.1);
        let body = json!({ "handle": "ann", "ke1": STANDARD.encode(login) });
        let (_, started) = call(&server.app, "AuthService/StartLogin", None, body).await;
        let evaluation = |field: &Value| bytes(field)[..32].to_vec();
        let registered = evaluation(&first["registrationResponse"]);
        assert_ne!(registered, evaluation(&started["ke2"]));
        assert_ne!(registered, evaluation(&second["registrationResponse"]));
        let (_, bob) = signed_in(&server, "bob", &["laptop"]).await;
        let start = ClientRegistration::<Suite>::start(&mut OsRng, b"pw").unwrap();
        let request = json!({ "registrationRequest": STANDARD.encode(start.message.serialize()) });
        let (_, started) = call(&server.app, "AuthService/StartPasswordSetup", token(&bob[0]), request).await;
        let response = RegistrationResponse::deserialize(&bytes(&started["registrationResponse"])).unwrap();
        let finish = start
            .state
            .finish(&mut OsRng, b"pw", response, Default::default())
            .unwrap();
        let finish = |id: &Value| {
            let body = json!({
                "registrationRecord": STANDARD.encode(finish.message.serialize()),
                "ksfParams": STANDARD.encode(KSF_PARAMS),
                "registrationId": id,
            });
            call(
                &server.app,
                "AuthService/FinishPasswordSetup",
                token(&sessions[0]),
                body,
            )
        };
        let invalid = json!({ "code": "invalid_argument", "reason": "field.invalid", "field": "registration_id" });
        assert_eq!(
            finish(&started["registrationId"]).await.1,
            invalid,
            "bob's registration is not ann's"
        );
        assert_eq!(finish(&json!("")).await.1, invalid);
    }

    #[tokio::test]
    async fn an_unknown_handle_shows_the_cost_of_a_real_account_and_a_new_salt_with_a_new_cost() {
        let server = server().await;
        signed_in(&server, "ann", &[]).await;
        let params = |handle: &str| {
            let ke1 = ClientLogin::<Suite>::start(&mut OsRng, b"pw")
                .unwrap()
                .message
                .serialize();
            let body = json!({ "handle": handle, "ke1": STANDARD.encode(ke1) });
            let started = call(&server.app, "AuthService/StartLogin", None, body);
            async { bytes(&started.await.1["ksfParams"]) }
        };
        let before = params("nobody").await;
        for cost in [[1, 0, 2, 0, 0, 0, 0, 0, 6, 1], [1, 0, 8, 0, 0, 0, 0, 0, 3, 1]] {
            sqlx::query("UPDATE password_records SET ksf_params = $1 || substring(ksf_params FROM 11)")
                .bind(&cost[..])
                .execute(&server.pool)
                .await
                .unwrap();
            for handle in ["ann", "nobody else"] {
                assert_eq!(params(handle).await[..10], cost, "{handle}");
            }
            // Five probes of nobody in all, within the free attempts.
            let after = params("nobody").await;
            assert_eq!(after[..10], cost);
            assert_ne!(
                after[10..],
                before[10..],
                "a new cost comes with a new salt, as on a password change"
            );
            assert_eq!(params("nobody").await, after);
        }
    }
}
