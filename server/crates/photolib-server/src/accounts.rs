//! Accounts (M2-01, ADR-0035): users and their roles in PostgreSQL. The `users_audit` trigger records every change in
//! the audit log; this module names the acting user and keeps the rules a trigger cannot. A new account's managed
//! library comes from the job its creation, or a change of its role, queues.

use std::time::{Duration, UNIX_EPOCH};

use buffa::{EnumValue, Enumeration};
use buffa_types::google::protobuf::Timestamp;
use photolib_proto::proto::photolib::api::v1::{PasswordSetup, User, UserRole, UserStatus};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::{auth, db::DbError, library};

/// Serialises account changes ("photousr"), so that one first administrator is created and the last one stays.
const ACCOUNTS_LOCK: i64 = 0x7068_6f74_6f75_7372;

const COLUMNS: &str =
    "id::text, handle, display_name, coalesce(email, ''), role, status, quota_bytes, coalesce(locale, ''),
    (extract(EPOCH FROM created_at) * 1e6)::bigint, (extract(EPOCH FROM purge_at) * 1e6)::bigint";
type Row = (
    String,
    String,
    String,
    String,
    String,
    String,
    Option<i64>,
    String,
    i64,
    Option<i64>,
);

#[derive(Debug)]
pub enum AccountError {
    /// The named field has a value the account cannot take.
    Invalid(&'static str),
    /// Another account has this handle or email.
    Taken(&'static str),
    NotFound,
    /// The change would leave the server without an active administrator.
    LastAdmin,
    /// An administrator exists, so the setup token no longer creates one.
    SetupDone,
    Db(DbError),
}

impl From<DbError> for AccountError {
    fn from(error: DbError) -> Self {
        AccountError::Db(error)
    }
}

impl From<sqlx::Error> for AccountError {
    fn from(error: sqlx::Error) -> Self {
        match error.as_database_error().and_then(|error| error.constraint()) {
            Some("users_handle_key") => AccountError::Taken("handle"),
            Some("users_email_key") => AccountError::Taken("email"),
            Some("password_setups_user_id_fkey") => AccountError::NotFound,
            _ => AccountError::Db(error.into()),
        }
    }
}

/// The accounts of an instance.
#[derive(Clone)]
pub struct Accounts {
    pool: PgPool,
}

impl Accounts {
    pub fn new(pool: PgPool) -> Self {
        Accounts { pool }
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    /// Whether an administrator exists, in any status; until one does, the setup token creates the first.
    pub async fn has_admin(&self) -> Result<bool, DbError> {
        Ok(has_admin(&mut *self.pool.acquire().await?).await?)
    }

    /// Creates the first administrator from the handle, display name, email and locale of `user`, with the token that
    /// sets their password; they are the actor of their own creation.
    pub async fn create_first_admin(&self, user: User) -> Result<(User, PasswordSetup), AccountError> {
        let id = Uuid::now_v7();
        let mut tx = self.begin(id).await?;
        if has_admin(&mut tx).await? {
            return Err(AccountError::SetupDone);
        }
        let user = User {
            handle: user.handle,
            display_name: user.display_name,
            email: user.email,
            locale: user.locale,
            role: UserRole::USER_ROLE_ADMIN.into(),
            ..Default::default()
        };
        let created = insert(&mut tx, id, user).await?;
        let setup = auth::issue_password_setup(&mut tx, id, id).await?;
        tx.commit().await?;
        Ok((created, setup))
    }

    /// Creates an active account.
    pub async fn create(&self, actor: Uuid, user: User) -> Result<User, AccountError> {
        let mut tx = self.begin(actor).await?;
        let created = insert(&mut tx, Uuid::now_v7(), user).await?;
        tx.commit().await?;
        Ok(created)
    }

    /// Gives the account `user.user_id` the values that `user` has in the fields `mask` names. A deleted account is
    /// purged after a delay, until another status restores it.
    pub async fn update(&self, actor: Uuid, mut user: User, mask: &[String]) -> Result<User, AccountError> {
        let id: Uuid = user.user_id.parse().map_err(|_| AccountError::Invalid("user_id"))?;
        if mask.is_empty() {
            return Err(AccountError::Invalid("update_mask"));
        }
        let mut tx = self.begin(actor).await?;
        let row: Option<Row> = sqlx::query_as(&format!("SELECT {COLUMNS} FROM users WHERE id = $1::uuid"))
            .bind(id.to_string())
            .fetch_optional(&mut *tx)
            .await?;
        let mut next = from_row(row.ok_or(AccountError::NotFound)?)?;
        let was_admin = is_active_admin(&next);
        let was = next.role;
        for field in mask {
            match check(&mut user, field)? {
                "display_name" => next.display_name = std::mem::take(&mut user.display_name),
                "email" => next.email = std::mem::take(&mut user.email),
                "role" => next.role = user.role,
                "status" => next.status = user.status,
                "quota_bytes" => next.quota_bytes = user.quota_bytes,
                "locale" => next.locale = std::mem::take(&mut user.locale),
                _ => return Err(AccountError::Invalid("update_mask")),
            }
        }
        let role = to_db(&next.role, "USER_ROLE_").ok_or(AccountError::Invalid("role"))?;
        let status = to_db(&next.status, "USER_STATUS_").ok_or(AccountError::Invalid("status"))?;
        if was_admin && !is_active_admin(&next) {
            let others: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM users WHERE role = 'admin' AND status = 'active' AND id <> $1::uuid)",
            )
            .bind(id.to_string())
            .fetch_one(&mut *tx)
            .await?;
            if !others {
                return Err(AccountError::LastAdmin);
            }
        }
        let row: Row = sqlx::query_as(&format!(
            "UPDATE users SET display_name = $2, email = nullif($3, ''), role = $4, status = $5, quota_bytes = $6,
                locale = nullif($7, ''),
                purge_at = CASE WHEN $5 = 'deleted' THEN coalesce(purge_at, now() + interval '7 days') END
             WHERE id = $1::uuid RETURNING {COLUMNS}"
        ))
        .bind(id.to_string())
        .bind(&next.display_name)
        .bind(&next.email)
        .bind(role)
        .bind(status)
        .bind(next.quota_bytes)
        .bind(&next.locale)
        .fetch_one(&mut *tx)
        .await?;
        let updated = from_row(row)?;
        if updated.role != was {
            // A viewer may now upload, which needs a library.
            photolib_jobs::enqueue(&mut tx, &photolib_jobs::NewJob::new(library::CREATE, b"")).await?;
        }
        tx.commit().await?;
        Ok(updated)
    }

    /// Makes the token with which the account `user` sets a new password, in place of any earlier one.
    pub async fn password_setup(&self, actor: Uuid, user: &str) -> Result<PasswordSetup, AccountError> {
        let user = user.parse().map_err(|_| AccountError::NotFound)?;
        let mut tx = self.pool.begin().await?;
        let setup = auth::issue_password_setup(&mut tx, actor, user).await?;
        tx.commit().await?;
        Ok(setup)
    }

    /// Creates an active account for a person an OpenID Connect provider vouches for, linked to their identity; they
    /// are the actor of their own creation. A taken handle gets a random suffix and a taken email is left out. Returns
    /// the account, or the one the identity was linked to meanwhile.
    pub async fn provision(&self, mut user: User, issuer: &str, subject: &str) -> Result<Uuid, AccountError> {
        let id = Uuid::now_v7();
        let mut tx = self.begin(id).await?;
        let linked: Option<String> =
            sqlx::query_scalar("SELECT user_id::text FROM oidc_identities WHERE issuer = $1 AND subject = $2")
                .bind(issuer)
                .bind(subject)
                .fetch_optional(&mut *tx)
                .await?;
        if let Some(linked) = linked {
            return linked.parse().map_err(|_| AccountError::NotFound);
        }
        let (handle_taken, email_taken): (bool, bool) = sqlx::query_as(
            "SELECT EXISTS (SELECT FROM users WHERE handle = $1), EXISTS (SELECT FROM users WHERE email = $2)",
        )
        .bind(&user.handle)
        .bind(&user.email)
        .fetch_one(&mut *tx)
        .await?;
        if handle_taken {
            user.handle = format!("{}-{}", user.handle, &auth::new_token()[..6]);
        }
        if email_taken {
            user.email.clear();
        }
        insert(&mut tx, id, user).await?;
        sqlx::query("INSERT INTO oidc_identities (issuer, subject, user_id) VALUES ($1, $2, $3::uuid)")
            .bind(issuer)
            .bind(subject)
            .bind(id.to_string())
            .execute(&mut *tx)
            .await?;
        auth::audit(&mut tx, id, "oidc.link", id, None).await?;
        tx.commit().await?;
        Ok(id)
    }

    /// Removes `user`'s passkeys, TOTP and recovery codes.
    pub async fn reset_second_factors(&self, actor: Uuid, user: &str) -> Result<(), AccountError> {
        let user: Uuid = user.parse().map_err(|_| AccountError::NotFound)?;
        let mut tx = self.pool.begin().await?;
        let exists: bool = sqlx::query_scalar(
            "WITH passkeys AS (DELETE FROM passkeys WHERE user_id = $1::uuid),
                totp AS (DELETE FROM totp_secrets WHERE user_id = $1::uuid),
                codes AS (DELETE FROM recovery_codes WHERE user_id = $1::uuid)
            SELECT EXISTS (SELECT FROM users WHERE id = $1::uuid)",
        )
        .bind(user.to_string())
        .fetch_one(&mut *tx)
        .await?;
        if !exists {
            return Err(AccountError::NotFound);
        }
        auth::audit(&mut tx, actor, "second_factors.reset", user, None).await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn get(&self, id: Uuid) -> Result<Option<User>, DbError> {
        let row: Option<Row> = sqlx::query_as(&format!("SELECT {COLUMNS} FROM users WHERE id = $1::uuid"))
            .bind(id.to_string())
            .fetch_optional(&self.pool)
            .await?;
        row.map(from_row).transpose()
    }

    /// Every account, by handle.
    pub async fn list(&self) -> Result<Vec<User>, DbError> {
        let rows: Vec<Row> = sqlx::query_as(&format!("SELECT {COLUMNS} FROM users ORDER BY handle"))
            .fetch_all(&self.pool)
            .await?;
        rows.into_iter().map(from_row).collect()
    }

    /// A transaction whose account changes `actor` makes, holding the accounts lock.
    async fn begin(&self, actor: Uuid) -> Result<Transaction<'static, Postgres>, AccountError> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("SELECT pg_advisory_xact_lock($1), set_config('photolib.actor', $2, true)")
            .bind(ACCOUNTS_LOCK)
            .bind(actor.to_string())
            .execute(&mut *tx)
            .await?;
        Ok(tx)
    }
}

fn is_active_admin(user: &User) -> bool {
    user.role == UserRole::USER_ROLE_ADMIN && user.status == UserStatus::USER_STATUS_ACTIVE
}

async fn has_admin(conn: &mut sqlx::PgConnection) -> sqlx::Result<bool> {
    sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM users WHERE role = 'admin')")
        .fetch_one(conn)
        .await
}

async fn insert(tx: &mut Transaction<'_, Postgres>, id: Uuid, mut user: User) -> Result<User, AccountError> {
    for field in ["handle", "display_name", "email", "role", "quota_bytes", "locale"] {
        check(&mut user, field)?;
    }
    let role = to_db(&user.role, "USER_ROLE_");
    let row: Row = sqlx::query_as(&format!(
        "INSERT INTO users (id, handle, display_name, email, role, quota_bytes, locale)
         VALUES ($1::uuid, $2, $3, nullif($4, ''), $5, $6, nullif($7, '')) RETURNING {COLUMNS}"
    ))
    .bind(id.to_string())
    .bind(&user.handle)
    .bind(&user.display_name)
    .bind(&user.email)
    .bind(role)
    .bind(user.quota_bytes)
    .bind(&user.locale)
    .fetch_one(&mut **tx)
    .await?;
    // Making the library needs the stores, which the `worker:io` processes hold.
    photolib_jobs::enqueue(tx, &photolib_jobs::NewJob::new(library::CREATE, b"")).await?;
    Ok(from_row(row)?)
}

/// Normalises the value of `field` in `user` and checks it; returns the field's name, or which field is invalid.
fn check(user: &mut User, field: &str) -> Result<&'static str, AccountError> {
    let printable =
        |text: &str, max: usize| !text.is_empty() && text.chars().count() <= max && !text.chars().any(char::is_control);
    let (name, valid) = match field {
        "handle" => ("handle", {
            let handle = user.handle.as_bytes();
            handle.first().is_some_and(u8::is_ascii_alphanumeric)
                && handle.len() <= 64
                && handle
                    .iter()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"._-".contains(b))
        }),
        "display_name" => {
            user.display_name = user.display_name.trim().into();
            ("display_name", printable(&user.display_name, 100))
        }
        "email" => {
            user.email = user.email.trim().to_lowercase();
            let parts: Vec<&str> = user.email.split('@').collect();
            let valid = parts.len() == 2 && parts.iter().all(|part| !part.is_empty());
            let email = &user.email;
            (
                "email",
                email.is_empty() || valid && printable(email, 254) && !email.contains(char::is_whitespace),
            )
        }
        "role" => ("role", to_db(&user.role, "USER_ROLE_").is_some()),
        "status" => ("status", {
            use UserStatus::*;
            [USER_STATUS_ACTIVE, USER_STATUS_DISABLED, USER_STATUS_DELETED]
                .map(EnumValue::from)
                .contains(&user.status)
        }),
        "quota_bytes" => ("quota_bytes", user.quota_bytes.is_none_or(|bytes| bytes >= 0)),
        "locale" => ("locale", {
            // BCP 47: a language of 2 to 8 letters, then subtags of 1 to 8 letters and digits.
            let mut tags = user.locale.split('-');
            let language = tags.next().unwrap_or_default();
            user.locale.is_empty()
                || (2..=8).contains(&language.len())
                    && language.bytes().all(|b| b.is_ascii_alphabetic())
                    && tags.all(|tag| (1..=8).contains(&tag.len()) && tag.bytes().all(|b| b.is_ascii_alphanumeric()))
        }),
        _ => ("update_mask", false),
    };
    if valid {
        Ok(name)
    } else {
        Err(AccountError::Invalid(name))
    }
}

/// The database spelling of a known value: `USER_ROLE_ADMIN` is `admin`; nothing for unspecified or unknown values.
pub(crate) fn to_db<E: Enumeration>(value: &EnumValue<E>, prefix: &str) -> Option<String> {
    let EnumValue::Known(known) = value else {
        return None;
    };
    let name = known.proto_name().strip_prefix(prefix)?;
    (name != "UNSPECIFIED").then(|| name.to_lowercase())
}

pub(crate) fn from_db<E: Enumeration>(text: &str, prefix: &str) -> Result<EnumValue<E>, DbError> {
    E::from_proto_name(&format!("{prefix}{}", text.to_uppercase()))
        .map(EnumValue::Known)
        .ok_or_else(|| format!("unknown {prefix} value {text}").into())
}

pub(crate) fn timestamp(micros: i64) -> Timestamp {
    (UNIX_EPOCH + Duration::from_micros(micros as u64)).into()
}

fn from_row(row: Row) -> Result<User, DbError> {
    let (id, handle, display_name, email, role, status, quota_bytes, locale, created_at, purge_at) = row;
    Ok(User {
        user_id: id,
        handle,
        display_name,
        email,
        role: from_db(&role, "USER_ROLE_")?,
        status: from_db::<UserStatus>(&status, "USER_STATUS_")?,
        quota_bytes,
        locale,
        created_at: Some(timestamp(created_at)).into(),
        purge_at: purge_at.map(timestamp).into(),
        ..Default::default()
    })
}

#[cfg(test)]
mod tests {
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use sqlx::PgPool;

    use super::*;

    fn person(handle: &str) -> User {
        User {
            handle: handle.into(),
            display_name: handle.to_uppercase(),
            role: UserRole::USER_ROLE_USER.into(),
            ..Default::default()
        }
    }

    #[tokio::test]
    async fn only_one_first_admin_is_ever_created_and_they_are_their_own_actor() {
        let pool = migrated().await;
        let accounts = Accounts::new(pool.clone());
        assert!(!accounts.has_admin().await.unwrap());
        let racers = ["ann", "bob", "cy", "dee"].map(|handle| {
            let accounts = accounts.clone();
            tokio::spawn(async move { accounts.create_first_admin(person(handle)).await })
        });
        let mut created = Vec::new();
        for racer in racers {
            match racer.await.unwrap() {
                Ok((user, _)) => created.push(user),
                Err(AccountError::SetupDone) => {}
                Err(error) => panic!("{error:?}"),
            }
        }
        assert_eq!(created.len(), 1, "{created:?}");
        let admin = &created[0];
        assert_eq!(
            (admin.role, admin.status),
            (UserRole::USER_ROLE_ADMIN.into(), UserStatus::USER_STATUS_ACTIVE.into())
        );
        assert!(accounts.has_admin().await.unwrap());
        let events = events(&pool).await;
        let actions: Vec<(&str, Option<&str>)> = events
            .iter()
            .map(|event| (event.0.as_str(), event.1.as_deref()))
            .collect();
        let by_admin = Some(admin.user_id.as_str());
        assert_eq!(
            actions,
            [("user.create", by_admin), ("password_setup.create", by_admin)]
        );
        assert!(matches!(
            accounts.create_first_admin(person("eve")).await,
            Err(AccountError::SetupDone)
        ));
    }

    #[tokio::test]
    async fn each_new_account_queues_the_job_that_creates_its_library_in_its_transaction() {
        let pool = migrated().await;
        let accounts = Accounts::new(pool.clone());
        let root = accounts.create_first_admin(person("root")).await.unwrap().0;
        let actor = root.user_id.parse().unwrap();
        accounts.create(actor, person("kid")).await.unwrap();
        let taken = accounts.create(actor, person("kid")).await;
        assert!(matches!(taken, Err(AccountError::Taken("handle"))), "{taken:?}");
        accounts
            .provision(person("sso"), "https://sso.example", "1")
            .await
            .unwrap();
        let queued: Vec<String> = sqlx::query_scalar("SELECT type FROM jobs ORDER BY id")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(queued, [library::CREATE; 3], "one per account created");
    }

    #[tokio::test]
    async fn a_role_change_queues_the_job_that_gives_the_account_its_library() {
        let pool = migrated().await;
        let accounts = Accounts::new(pool.clone());
        let root = accounts.create_first_admin(person("root")).await.unwrap().0;
        let viewer = User {
            role: UserRole::USER_ROLE_VIEWER.into(),
            ..person("kid")
        };
        let kid = accounts.create(root.user_id.parse().unwrap(), viewer).await.unwrap();
        let queued = || sqlx::query_scalar::<_, i64>("SELECT count(*) FROM jobs").fetch_one(&pool);
        let before = queued().await.unwrap();
        let renamed = User {
            display_name: "Kiddo".into(),
            ..Default::default()
        };
        update(&accounts, &root, &kid.user_id, &["display_name"], renamed)
            .await
            .unwrap();
        assert_eq!(queued().await.unwrap(), before, "the role stays");
        let promoted = User {
            role: UserRole::USER_ROLE_USER.into(),
            ..Default::default()
        };
        update(&accounts, &root, &kid.user_id, &["role"], promoted)
            .await
            .unwrap();
        assert_eq!(queued().await.unwrap(), before + 1);
    }

    /// Gives the account `id` the values of `with` in `fields`, as `actor`.
    async fn update(
        accounts: &Accounts,
        actor: &User,
        id: &str,
        fields: &[&str],
        with: User,
    ) -> Result<User, AccountError> {
        let user = User {
            user_id: id.into(),
            ..with
        };
        let mask: Vec<String> = fields.iter().map(|field| field.to_string()).collect();
        accounts.update(actor.user_id.parse().unwrap(), user, &mask).await
    }

    async fn set_status(accounts: &Accounts, actor: &User, id: &str, status: UserStatus) -> Result<User, AccountError> {
        let with = User {
            status: status.into(),
            ..Default::default()
        };
        update(accounts, actor, id, &["status"], with).await
    }

    #[tokio::test]
    async fn changes_made_through_photolibd_name_the_acting_admin() {
        let pool = migrated().await;
        let accounts = Accounts::new(pool.clone());
        let root = accounts.create_first_admin(person("root")).await.unwrap().0;
        let actor = root.user_id.parse().unwrap();
        let viewer = User {
            role: UserRole::USER_ROLE_VIEWER.into(),
            quota_bytes: Some(0),
            ..person("kid")
        };
        let kid = accounts.create(actor, viewer).await.unwrap();
        let renamed = User {
            display_name: "Kiddo".into(),
            locale: "de-CH".into(),
            ..Default::default()
        };
        let fields = ["display_name", "locale", "quota_bytes"];
        let kid = update(&accounts, &root, &kid.user_id, &fields, renamed).await.unwrap();
        assert_eq!(
            (kid.display_name.as_str(), kid.locale.as_str(), kid.quota_bytes),
            ("Kiddo", "de-CH", None)
        );
        assert_eq!(
            accounts.get(kid.user_id.parse().unwrap()).await.unwrap(),
            Some(kid.clone())
        );
        assert_eq!(accounts.list().await.unwrap(), [kid.clone(), root.clone()], "by handle");
        let events: Vec<_> = events(&pool)
            .await
            .into_iter()
            .skip(2) // the first administrator and their password setup
            .map(|(action, actor, _, details)| (action, actor, details))
            .collect();
        assert_eq!(
            events,
            [
                (
                    "user.create".into(),
                    Some(root.user_id.clone()),
                    serde_json::json!({
                        "fields": ["display_name", "email", "handle", "locale", "purge_at", "quota_bytes", "role", "status"],
                        "locale": null, "purge_at": null, "quota_bytes": 0, "role": "viewer", "status": "active",
                    })
                ),
                (
                    "user.update".into(),
                    Some(root.user_id.clone()),
                    serde_json::json!({ "fields": ["display_name", "locale", "quota_bytes"], "locale": "de-CH", "quota_bytes": null })
                ),
            ]
        );
    }

    #[tokio::test]
    async fn the_last_active_admin_keeps_the_role_and_the_status() {
        let pool = migrated().await;
        let accounts = Accounts::new(pool.clone());
        let root = accounts.create_first_admin(person("root")).await.unwrap().0;
        let id = &root.user_id;
        let demote = || User {
            role: UserRole::USER_ROLE_USER.into(),
            ..Default::default()
        };
        assert!(matches!(
            update(&accounts, &root, id, &["role"], demote()).await,
            Err(AccountError::LastAdmin)
        ));
        for status in [UserStatus::USER_STATUS_DISABLED, UserStatus::USER_STATUS_DELETED] {
            assert!(matches!(
                set_status(&accounts, &root, id, status).await,
                Err(AccountError::LastAdmin)
            ));
        }
        assert_eq!(
            events(&pool).await.len(),
            2,
            "a refused change records nothing after the first administrator and their password setup"
        );
        let other = User {
            role: UserRole::USER_ROLE_ADMIN.into(),
            ..person("other")
        };
        let other = accounts.create(root.user_id.parse().unwrap(), other).await.unwrap();
        update(&accounts, &root, id, &["role"], demote()).await.unwrap();
        let disabled = UserStatus::USER_STATUS_DISABLED;
        assert!(matches!(
            set_status(&accounts, &other, &other.user_id, disabled).await,
            Err(AccountError::LastAdmin)
        ));
    }

    #[tokio::test]
    async fn a_deleted_account_is_purged_after_seven_days_unless_its_status_changes_back() {
        let accounts = Accounts::new(migrated().await);
        let root = accounts.create_first_admin(person("root")).await.unwrap().0;
        let kid = accounts
            .create(root.user_id.parse().unwrap(), person("kid"))
            .await
            .unwrap();
        let set = |status| set_status(&accounts, &root, &kid.user_id, status);
        let deleted = set(UserStatus::USER_STATUS_DELETED).await.unwrap();
        assert_eq!(deleted.status, UserStatus::USER_STATUS_DELETED);
        let delay = deleted.purge_at.seconds - kid.created_at.seconds;
        assert!((7 * 86_400..7 * 86_400 + 60).contains(&delay), "{delay}");
        let again = set(UserStatus::USER_STATUS_DELETED).await.unwrap();
        assert_eq!(again.purge_at, deleted.purge_at, "deleting again keeps the date");
        let restored = set(UserStatus::USER_STATUS_DISABLED).await.unwrap();
        assert_eq!(
            (restored.status, restored.purge_at.is_set()),
            (UserStatus::USER_STATUS_DISABLED.into(), false)
        );
    }

    #[tokio::test]
    async fn accounts_get_valid_values_and_unique_handles_and_emails() {
        let accounts = Accounts::new(migrated().await);
        let with = |handle: &str, edit: fn(&mut User)| {
            let mut user = person(handle);
            edit(&mut user);
            user
        };
        let root = with("root", |u| u.email = " Root@Example.org ".into());
        let root = accounts.create_first_admin(root).await.unwrap().0;
        assert_eq!(root.email, "root@example.org");
        let actor = root.user_id.parse().unwrap();
        let unusual = User {
            display_name: format!("  {}  ", "Zoë".repeat(33) + "!"),
            locale: "zh-Hant-TW".into(),
            quota_bytes: Some(0),
            ..person(&format!("0.a_b-{}", "c".repeat(58)))
        };
        let created = accounts.create(actor, unusual).await.unwrap();
        assert_eq!(created.display_name.chars().count(), 100, "trimmed");
        for (user, taken) in [
            (person("root"), "handle"),
            (with("ann", |u| u.email = "ROOT@example.org".into()), "email"),
        ] {
            let error = accounts.create(actor, user).await.unwrap_err();
            assert!(
                matches!(error, AccountError::Taken(field) if field == taken),
                "{error:?}"
            );
        }
        for (user, invalid) in [
            (person(""), "handle"),
            (person("Ann"), "handle"),
            (person(".ann"), "handle"),
            (person("ann bob"), "handle"),
            (person(&"a".repeat(65)), "handle"),
            (with("ann", |u| u.display_name = " \t ".into()), "display_name"),
            (with("ann", |u| u.display_name = "Ann\u{7}".into()), "display_name"),
            (with("ann", |u| u.display_name = "a".repeat(101)), "display_name"),
            (with("ann", |u| u.email = "ann".into()), "email"),
            (with("ann", |u| u.email = "ann@".into()), "email"),
            (with("ann", |u| u.email = "a@b@c".into()), "email"),
            (with("ann", |u| u.email = "a b@c".into()), "email"),
            (with("ann", |u| u.role = UserRole::USER_ROLE_UNSPECIFIED.into()), "role"),
            (with("ann", |u| u.role = EnumValue::Unknown(9)), "role"),
            (with("ann", |u| u.quota_bytes = Some(-1)), "quota_bytes"),
            (with("ann", |u| u.locale = "de_CH".into()), "locale"),
            (with("ann", |u| u.locale = "-de".into()), "locale"),
            (with("ann", |u| u.locale = "d".into()), "locale"),
            (with("ann", |u| u.locale = "de-toolongtag".into()), "locale"),
        ] {
            let error = accounts.create(actor, user.clone()).await.unwrap_err();
            assert!(
                matches!(error, AccountError::Invalid(field) if field == invalid),
                "{user:?}: {error:?}"
            );
        }
        assert_eq!(accounts.list().await.unwrap().len(), 2);
    }

    #[tokio::test]
    async fn an_update_changes_an_existing_account_in_the_fields_that_may_change() {
        let accounts = Accounts::new(migrated().await);
        let root = accounts.create_first_admin(person("root")).await.unwrap().0;
        let missing = Uuid::now_v7().to_string();
        let blank = User {
            display_name: " ".into(),
            ..Default::default()
        };
        let id = root.user_id.as_str();
        for (id, fields, with, expected) in [
            (missing.as_str(), &["locale"][..], User::default(), "not found"),
            ("42", &["locale"], User::default(), "user_id"),
            (id, &[], User::default(), "update_mask"),
            (id, &["handle"], person("new"), "update_mask"),
            (id, &["created_at"], User::default(), "update_mask"),
            (id, &["display_name"], blank, "display_name"),
        ] {
            let error = update(&accounts, &root, id, fields, with).await;
            let found = match error.unwrap_err() {
                AccountError::NotFound => "not found",
                AccountError::Invalid(field) => field,
                error => panic!("{error:?}"),
            };
            assert_eq!(found, expected);
        }
        for status in [UserStatus::USER_STATUS_INVITED, UserStatus::USER_STATUS_UNSPECIFIED] {
            assert!(matches!(
                set_status(&accounts, &root, id, status).await,
                Err(AccountError::Invalid("status"))
            ));
        }
    }

    async fn migrated() -> PgPool {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        db.pool
    }

    /// The audit events, oldest first: action, actor, target and details.
    async fn events(pool: &PgPool) -> Vec<(String, Option<String>, serde_json::Value, serde_json::Value)> {
        sqlx::query_as("SELECT action, actor_user_id::text, target::text, details::text FROM audit_events ORDER BY id")
            .fetch_all(pool)
            .await
            .unwrap()
            .into_iter()
            .map(
                |(action, actor, target, details): (String, Option<String>, String, String)| {
                    (
                        action,
                        actor,
                        serde_json::from_str(&target).unwrap(),
                        serde_json::from_str(&details).unwrap(),
                    )
                },
            )
            .collect()
    }

    #[tokio::test]
    async fn account_changes_made_around_photolibd_are_audited_without_copying_personal_data() {
        let pool = migrated().await;
        let id = "0190a3c2-0000-7000-8000-000000000001";
        for sql in [
            format!(
                "INSERT INTO users (id, handle, display_name, email) VALUES ('{id}', 'ann', 'Ann', 'ann@example.org')"
            ),
            format!("UPDATE users SET email = 'a@example.org', quota_bytes = 5 WHERE id = '{id}'"),
            format!("UPDATE users SET locale = locale WHERE id = '{id}'"),
            format!("DELETE FROM users WHERE id = '{id}'"),
        ] {
            sqlx::query(&sql).execute(&pool).await.unwrap();
        }
        let events = events(&pool).await;
        let target = serde_json::json!({ "user_id": id });
        assert_eq!(
            events,
            [
                (
                    "user.create".into(),
                    None,
                    target.clone(),
                    serde_json::json!({
                        "fields": ["display_name", "email", "handle", "locale", "purge_at", "quota_bytes", "role", "status"],
                        "locale": null, "purge_at": null, "quota_bytes": null, "role": "user", "status": "active",
                    })
                ),
                (
                    "user.update".into(),
                    None,
                    target.clone(),
                    serde_json::json!({ "fields": ["email", "quota_bytes"], "quota_bytes": 5 })
                ),
                ("user.purge".into(), None, target, serde_json::json!({ "fields": [] })),
            ],
            "an update that changes nothing is no change"
        );
        let copied: i64 = sqlx::query_scalar("SELECT count(*) FROM audit_events WHERE details::text LIKE '%example%'")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(copied, 0);
    }

    /// The events whose hash does not chain them to the event before, as recomputed from their fields.
    async fn broken_links(pool: &PgPool) -> Vec<i64> {
        sqlx::query_scalar(
            "SELECT id FROM (
                SELECT id, hash, prev_hash, lag(hash) OVER (ORDER BY id) AS before,
                    audit_hash(prev_hash, at, actor_user_id, actor_device_id, action, target, details) AS expected
                FROM audit_events) events
            WHERE hash <> expected OR prev_hash IS DISTINCT FROM before ORDER BY id",
        )
        .fetch_all(pool)
        .await
        .unwrap()
    }

    #[tokio::test]
    async fn the_audit_events_form_a_hash_chain_that_shows_tampering() {
        let pool = migrated().await;
        for handle in ["ann", "bob", "cy", "dee"] {
            sqlx::query("INSERT INTO users (id, handle, display_name) VALUES (gen_random_uuid(), $1, $1)")
                .bind(handle)
                .execute(&pool)
                .await
                .unwrap();
        }
        let ids: Vec<i64> = sqlx::query_scalar("SELECT id FROM audit_events ORDER BY id")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(ids.len(), 4);
        assert_eq!(broken_links(&pool).await, Vec::<i64>::new());
        let first_has_no_predecessor: bool =
            sqlx::query_scalar("SELECT prev_hash IS NULL FROM audit_events ORDER BY id LIMIT 1")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert!(first_has_no_predecessor);
        sqlx::query("UPDATE audit_events SET details = details || '{\"role\": \"admin\"}' WHERE id = $1")
            .bind(ids[1])
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("DELETE FROM audit_events WHERE id = $1")
            .bind(ids[2])
            .execute(&pool)
            .await
            .unwrap();
        assert_eq!(broken_links(&pool).await, [ids[1], ids[3]]);
    }

    #[tokio::test]
    async fn an_instance_upgraded_from_the_baseline_keeps_its_accounts_and_audits_them_from_then_on() {
        let db = testpg::database().await;
        let migrations = embedded();
        upgrade(&db.pool, &Upgrade::new(&migrations[..1])).await.unwrap();
        sqlx::raw_sql(
            "INSERT INTO users (id, handle, display_name, role, status) VALUES
                ('0190a3c2-0000-7000-8000-000000000001', 'root', 'Root', 'admin', 'active'),
                ('0190a3c2-0000-7000-8000-000000000002', 'kid', 'Kid', 'user', 'invited')",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        upgrade(&db.pool, &Upgrade::new(&migrations)).await.unwrap();
        let users: Vec<(String, String, String, Option<i64>)> = sqlx::query_as(
            "SELECT handle, role, status, extract(epoch FROM purge_at)::bigint FROM users ORDER BY handle",
        )
        .fetch_all(&db.pool)
        .await
        .unwrap();
        assert_eq!(
            users,
            [
                ("kid".into(), "user".into(), "invited".into(), None),
                ("root".into(), "admin".into(), "active".into(), None)
            ]
        );
        assert!(events(&db.pool).await.is_empty());
        sqlx::query("UPDATE users SET role = 'viewer' WHERE handle = 'kid'")
            .execute(&db.pool)
            .await
            .unwrap();
        let events = events(&db.pool).await;
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].3, serde_json::json!({ "fields": ["role"], "role": "viewer" }));
    }
}
