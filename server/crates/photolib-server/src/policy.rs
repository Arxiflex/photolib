//! The server's policy (R-MODE-5, ADR-0240): its presets, and the pins of the configuration file, which every start
//! writes over the database. `photolib_authz` enforces the switches.

use photolib_authz::Capability::{self, Deletes, DeviceFolders, Edits, ManagedLibraries, Sharing, Uploads, XmpWrites};
use sqlx::PgPool;

use crate::config::Pinned;

/// What each preset switches off, by the name `Preset` gives it; it switches the rest on.
pub const PRESETS: [(&str, &[Capability]); 3] = [
    // External read-only libraries are the only source of truth.
    (
        "archive_viewer",
        &[ManagedLibraries, Uploads, DeviceFolders, Edits, Deletes, XmpWrites],
    ),
    // Edits stay in Photolib; nobody's sidecar is written for them.
    ("family_backup", &[XmpWrites]),
    ("personal", &[Sharing]),
];

/// Writes what `pinned` pins over the database: the instance settings, and the server's switches, marked pinned; a
/// switch no longer pinned keeps its value and can be changed again. A change is an audit event of nobody's.
pub async fn pin(pool: &PgPool, pinned: &Pinned) -> sqlx::Result<()> {
    let mut tx = pool.begin().await?;
    let number = |value: Option<u32>| value.and_then(|value| i32::try_from(value).ok());
    let settings = sqlx::query(
        "UPDATE instance_settings SET require_two_factor = coalesce($1, require_two_factor),
           face_recognition_default = coalesce($2, face_recognition_default),
           trash_retention_days = coalesce($3, trash_retention_days),
           min_free_disk_percent = coalesce($4, min_free_disk_percent), scrub_days = coalesce($5, scrub_days),
           backup_silent_hours = coalesce($6, backup_silent_hours)
         WHERE $1 <> require_two_factor OR $2 <> face_recognition_default OR $3 <> trash_retention_days
           OR $4 <> min_free_disk_percent OR $5 <> scrub_days OR $6 <> backup_silent_hours",
    )
    .bind(pinned.require_two_factor)
    .bind(pinned.face_recognition_default)
    .bind(number(pinned.trash_retention_days))
    .bind(number(pinned.min_free_disk_percent))
    .bind(number(pinned.scrub_days))
    .bind(number(pinned.backup_silent_hours))
    .execute(&mut *tx)
    .await?;
    let (names, values): (Vec<&str>, Vec<bool>) = pinned.policy.iter().map(|(name, on)| (name.as_str(), *on)).unzip();
    let released = sqlx::query("UPDATE policy_switches SET pinned = false WHERE pinned AND capability <> ALL($1)")
        .bind(&names)
        .execute(&mut *tx)
        .await?;
    let switched = sqlx::query(
        "INSERT INTO policy_switches (capability, enabled, pinned) SELECT *, true FROM unnest($1::text[], $2::bool[])
         ON CONFLICT (capability, user_id, library_id) DO UPDATE SET enabled = excluded.enabled, pinned = true
         WHERE NOT policy_switches.pinned OR policy_switches.enabled <> excluded.enabled",
    )
    .bind(&names)
    .bind(&values)
    .execute(&mut *tx)
    .await?;
    if [settings, released, switched]
        .iter()
        .any(|done| done.rows_affected() > 0)
    {
        sqlx::query("SELECT audit_append(NULL, 'settings.pin', '{}', $1::jsonb)")
            .bind(serde_json::to_value(pinned).unwrap_or_default())
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await
}

#[cfg(test)]
mod tests {
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };

    use super::*;

    #[tokio::test]
    async fn every_start_writes_the_pins_over_the_database_and_audits_only_a_change() {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let state = async || -> (i32, Vec<(String, bool, bool)>, i64) {
            let days = sqlx::query_scalar("SELECT trash_retention_days FROM instance_settings");
            let switches = sqlx::query_as("SELECT capability, enabled, pinned FROM policy_switches ORDER BY 1");
            let audited = sqlx::query_scalar("SELECT count(*) FROM audit_events WHERE action = 'settings.pin'");
            (
                days.fetch_one(&db.pool).await.unwrap(),
                switches.fetch_all(&db.pool).await.unwrap(),
                audited.fetch_one(&db.pool).await.unwrap(),
            )
        };
        pin(&db.pool, &Pinned::default()).await.unwrap();
        assert_eq!(state().await, (60, vec![], 0), "nothing pinned, nothing changed");
        sqlx::query("INSERT INTO policy_switches (capability, enabled) VALUES ('sharing', false)")
            .execute(&db.pool)
            .await
            .unwrap();
        let pinned = Pinned {
            trash_retention_days: Some(30),
            policy: [("uploads".into(), false), ("sharing".into(), true)].into(),
            ..Pinned::default()
        };
        let switches = vec![("sharing".into(), true, true), ("uploads".into(), false, true)];
        pin(&db.pool, &pinned).await.unwrap();
        assert_eq!(state().await, (30, switches.clone(), 1));
        pin(&db.pool, &pinned).await.unwrap();
        assert_eq!(state().await, (30, switches, 1), "the same pins change nothing");
        pin(&db.pool, &Pinned::default()).await.unwrap();
        let released = vec![("sharing".into(), true, false), ("uploads".into(), false, false)];
        assert_eq!(state().await, (30, released, 2), "unpinned, a setting keeps its value");
    }
}
