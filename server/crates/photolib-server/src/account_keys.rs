//! Private mode's keys (M6-02, ADR-0255): an account's identity, the seeds of its keys wrapped under its account master
//! key (AMK), the AMK wrapped once per unlock path, and when the recovery kit was last verified. Clients make and wrap
//! every key; this keeps what they send, checking only what the headers say, and decides when the account may upload
//! to private libraries: with two unlock paths and a verified recovery kit (design 06 §6).

use photolib_kernel::proto::kernel::v1::{Method, VerifyIdentityLogRequest, VerifyIdentityLogResponse};
use photolib_proto::proto::photolib::api::v1::{AccountKeys, CreateKeysRequest, UnlockKind, UnlockPath};
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use crate::{
    accounts::{from_db, timestamp, to_db},
    auth::{audit, ksf_params_valid},
    db::DbError,
    ingest::extract::kernel,
};

/// Why keys or a path were refused.
#[derive(Debug)]
pub enum KeyError {
    /// A field that is malformed, or names another account or AMK.
    Invalid(&'static str),
    /// The account has keys already.
    Exist,
    /// The account has no keys.
    None,
    /// A password path for an account without a password.
    NoPassword,
    /// A recovery kit other than the current one.
    KitMismatch,
    /// The database failed.
    Db(DbError),
}

impl From<sqlx::Error> for KeyError {
    fn from(error: sqlx::Error) -> Self {
        Self::Db(error.into())
    }
}

/// Wrapped types of the crypto spec's registry.
const AMK: u8 = 1;
const SIGNING_KEY: u8 = 8;
const DECRYPTION_KEY: u8 = 9;

/// Two unlock paths and a verified recovery kit, of the account keys `k`. Replacing the kit unverifies it.
const READY: &str = "(k.recovery_verified_at IS NOT NULL
    AND (SELECT count(*) FROM unlock_paths p WHERE p.user_id = k.user_id) >= 2)";

fn micros(column: &str) -> String {
    format!("(extract(EPOCH FROM {column}) * 1e6)::bigint")
}

/// Whether `user` may upload to a private library.
pub async fn ready(pool: &PgPool, user: Uuid) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar(&format!(
        "SELECT EXISTS (SELECT FROM account_keys k WHERE user_id = $1 AND {READY})"
    ))
    .bind(user)
    .fetch_one(pool)
    .await
}

/// The keys of `user`, the password path's wrap left out: only a password sign-in returns it (`password_path`).
pub async fn get(conn: &mut PgConnection, user: Uuid) -> Result<Option<AccountKeys>, DbError> {
    type Row = (Vec<u8>, Vec<u8>, Vec<u8>, Option<i64>, Option<i64>, bool);
    let row: Option<Row> = sqlx::query_as(&format!(
        "SELECT u.key_bundle, k.signing_key, k.decryption_key, {}, {}, {READY}
         FROM account_keys k JOIN user_keys u USING (user_id) WHERE k.user_id = $1",
        micros("k.recovery_verified_at"),
        micros("k.recovery_verified_at + interval '6 months'"),
    ))
    .bind(user)
    .fetch_optional(&mut *conn)
    .await?;
    let Some((identity, signing_key, decryption_key, verified, due, ready)) = row else {
        return Ok(None);
    };
    Ok(Some(AccountKeys {
        identity,
        signing_key,
        decryption_key,
        paths: paths(conn, user, false).await?,
        recovery_verified_at: verified.map(timestamp).into(),
        drill_due_at: due.map(timestamp).into(),
        ready,
        ..Default::default()
    }))
}

/// The password path of `user`, wrap and all, for a sign-in that proved the password.
pub async fn password_path(conn: &mut PgConnection, user: Uuid) -> Result<Option<UnlockPath>, DbError> {
    let password = |path: &UnlockPath| path.kind == UnlockKind::UNLOCK_KIND_PASSWORD;
    Ok(paths(conn, user, true).await?.into_iter().find(password))
}

/// The unlock paths of `user`, the password's wrap only `with_password`.
async fn paths(conn: &mut PgConnection, user: Uuid, with_password: bool) -> Result<Vec<UnlockPath>, DbError> {
    type Row = (String, Vec<u8>, Option<Vec<u8>>, i64);
    let paths: Vec<Row> = sqlx::query_as(&format!(
        "SELECT kind, CASE WHEN kind = 'password' AND NOT $2 THEN '' ELSE wrap END, params, {}
         FROM unlock_paths WHERE user_id = $1 ORDER BY kind",
        micros("created_at")
    ))
    .bind(user)
    .bind(with_password)
    .fetch_all(conn)
    .await?;
    let path = |(kind, wrap, params, created_at): Row| {
        Ok(UnlockPath {
            kind: from_db(&kind, "UNLOCK_KIND_")?,
            wrap,
            params: params.unwrap_or_default(),
            created_at: Some(timestamp(created_at)).into(),
            ..Default::default()
        })
    };
    paths.into_iter().map(path).collect()
}

/// Creates the keys of `user`, once.
pub async fn create(pool: &PgPool, user: Uuid, request: CreateKeysRequest) -> Result<AccountKeys, KeyError> {
    let (amk, _) = header(&request.signing_key, SIGNING_KEY, "signing_key")?;
    if header(&request.decryption_key, DECRYPTION_KEY, "decryption_key")?.0 != amk {
        return Err(KeyError::Invalid("decryption_key"));
    }
    let log = VerifyIdentityLogRequest {
        user_id: user.as_bytes().to_vec(),
        entries: vec![request.identity.clone()],
        ..Default::default()
    };
    kernel::<VerifyIdentityLogResponse>(Method::VerifyIdentityLog, &log).map_err(|_| KeyError::Invalid("identity"))?;
    let mut tx = pool.begin().await?;
    let created = sqlx::query(
        "INSERT INTO account_keys (user_id, amk_id, signing_key, decryption_key) VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id) DO NOTHING",
    )
    .bind(user)
    .bind(amk.as_slice())
    .bind(&request.signing_key)
    .bind(&request.decryption_key)
    .execute(&mut *tx)
    .await?;
    if created.rows_affected() == 0 {
        return Err(KeyError::Exist);
    }
    sqlx::query(
        "INSERT INTO user_keys (user_id, key_bundle) VALUES ($1, $2)
         ON CONFLICT (user_id) DO UPDATE SET key_bundle = $2, created_at = now()",
    )
    .bind(user)
    .bind(&request.identity)
    .execute(&mut *tx)
    .await?;
    let mut kinds = vec![];
    for path in &request.paths {
        let kind = store(&mut tx, user, path).await?;
        if kinds.contains(&kind) {
            return Err(KeyError::Invalid("paths"));
        }
        kinds.push(kind);
    }
    audit(&mut tx, user, "keys.create", user, None).await?;
    let keys = get(&mut tx, user).await.map_err(KeyError::Db)?;
    tx.commit().await?;
    keys.ok_or(KeyError::None)
}

/// Adds an unlock path of the keys of `user`, or replaces the one of its kind.
pub async fn put(pool: &PgPool, user: Uuid, path: &UnlockPath) -> Result<AccountKeys, KeyError> {
    let mut tx = pool.begin().await?;
    store(&mut tx, user, path).await?;
    audit(&mut tx, user, "keys.unlock_path", user, None).await?;
    let keys = get(&mut tx, user).await.map_err(KeyError::Db)?;
    tx.commit().await?;
    keys.ok_or(KeyError::None)
}

/// Replaces the password path of `user`, who has a new password, with `path`, or removes it.
pub async fn new_password(conn: &mut PgConnection, user: Uuid, path: Option<&UnlockPath>) -> Result<(), KeyError> {
    match path {
        Some(path) if to_db(&path.kind, "UNLOCK_KIND_").as_deref() == Some("password") => {
            store(conn, user, path).await.map(drop)
        }
        Some(_) => Err(KeyError::Invalid("password_path")),
        None => {
            sqlx::query("DELETE FROM unlock_paths WHERE user_id = $1 AND kind = 'password'")
                .bind(user)
                .execute(conn)
                .await?;
            Ok(())
        }
    }
}

/// Records that the person holds the recovery kit whose KEK_rec has the key id `kit`.
pub async fn verify(pool: &PgPool, user: Uuid, kit: &[u8]) -> Result<AccountKeys, KeyError> {
    let mut tx = pool.begin().await?;
    // The kit's key id is the wrapping_key_id of its wrap, bytes 8 to 24.
    let verified = sqlx::query(
        "UPDATE account_keys SET recovery_verified_at = now() WHERE user_id = $1 AND EXISTS (
            SELECT FROM unlock_paths WHERE user_id = $1 AND kind = 'recovery' AND substring(wrap FROM 9 FOR 16) = $2
         )",
    )
    .bind(user)
    .bind(kit)
    .execute(&mut *tx)
    .await?;
    let keys = get(&mut tx, user).await.map_err(KeyError::Db)?.ok_or(KeyError::None)?;
    if verified.rows_affected() == 0 {
        return Err(KeyError::KitMismatch);
    }
    audit(&mut tx, user, "keys.recovery_verified", user, None).await?;
    tx.commit().await?;
    Ok(keys)
}

/// Stores `path` of the AMK of the keys of `user` in place of the one of its kind; returns the kind.
async fn store(conn: &mut PgConnection, user: Uuid, path: &UnlockPath) -> Result<&'static str, KeyError> {
    let kind = match to_db(&path.kind, "UNLOCK_KIND_").as_deref() {
        Some("password") if ksf_params_valid(&path.params) => "password",
        Some("recovery") if path.params.is_empty() => "recovery",
        Some("password" | "recovery") => return Err(KeyError::Invalid("path.params")),
        _ => return Err(KeyError::Invalid("path.kind")),
    };
    let (_, amk) = header(&path.wrap, AMK, "path.wrap")?;
    let (held, password): (Option<Vec<u8>>, bool) = sqlx::query_as(
        "SELECT (SELECT amk_id FROM account_keys WHERE user_id = $1 FOR UPDATE),
                EXISTS (SELECT FROM password_records WHERE user_id = $1)",
    )
    .bind(user)
    .fetch_one(&mut *conn)
    .await?;
    match held {
        None => return Err(KeyError::None),
        Some(held) if held != amk => return Err(KeyError::Invalid("path.wrap")),
        Some(_) if kind == "password" && !password => return Err(KeyError::NoPassword),
        Some(_) => {}
    }
    sqlx::query(
        "WITH unverified AS (
            UPDATE account_keys SET recovery_verified_at = NULL WHERE user_id = $1 AND $2 = 'recovery'
         )
         INSERT INTO unlock_paths (user_id, kind, wrap, params) VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, kind) DO UPDATE SET wrap = $3, params = $4, created_at = now()",
    )
    .bind(user)
    .bind(kind)
    .bind(&path.wrap)
    .bind((kind == "password").then_some(&path.params))
    .execute(conn)
    .await?;
    Ok(kind)
}

/// The wrapping and wrapped key ids of `wrap`, a PLW of `wrapped_type` by its header.
fn header(wrap: &[u8], wrapped_type: u8, field: &'static str) -> Result<([u8; 16], [u8; 16]), KeyError> {
    let id = |range| wrap.get(range).and_then(|id: &[u8]| id.try_into().ok());
    match (wrap.len(), wrap.get(..8), id(8..24), id(24..40)) {
        (144, Some(&[b'P', b'L', b'W', 1, 1, kind, 0, 0]), Some(wrapping), Some(wrapped)) if kind == wrapped_type => {
            Ok((wrapping, wrapped))
        }
        _ => Err(KeyError::Invalid(field)),
    }
}
