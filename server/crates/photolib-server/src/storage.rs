//! The stores of the configuration (ADR-0022): their markers checked, then the intent log recovered.

use std::{io, path::Path, sync::Arc, time::Duration};

use nix::sys::statvfs::statvfs;

use photolib_storage::{
    BlobStore,
    fs::FsStore,
    journal::Journal,
    marker::{Candidate, Stores},
    s3::{S3Config, S3Store},
};
use sqlx::PgPool;
use uuid::Uuid;

use crate::config::{Config, Store};

/// How long one call to the data directory may take.
pub(crate) const LOCAL_TIMEOUT: Duration = Duration::from_secs(120);

/// The size of the filesystem of `dir` and the space photolibd may still use there, in bytes.
pub fn space(dir: &Path) -> io::Result<(u64, u64)> {
    let fs = statvfs(dir)?;
    let block = fs.fragment_size();
    Ok((
        fs.blocks().saturating_mul(block),
        fs.blocks_available().saturating_mul(block),
    ))
}

/// A configured object store.
pub(crate) fn s3(store: &Store) -> Result<S3Store, String> {
    let s3 = S3Config {
        endpoint: store.endpoint.clone(),
        bucket: store.bucket.clone(),
        region: store.region.clone(),
        prefix: store.prefix.clone(),
        access_key_id: store.access_key_id.clone(),
        secret_access_key: store.secret_access_key.expose().clone(),
    };
    S3Store::open(&s3, Duration::from_secs(store.timeout_secs)).map_err(|e| e.to_string())
}

/// Store `name` of the configuration, unchecked: what recovery and restores read before the stores are checked.
pub(crate) async fn open(config: &Config, name: &str) -> Result<Arc<dyn BlobStore>, String> {
    Ok(match name {
        "local" => {
            let data_dir = config.data_dir.as_ref().ok_or("data_dir is not set")?;
            Arc::new(
                FsStore::open(data_dir, LOCAL_TIMEOUT)
                    .await
                    .map_err(|e| e.to_string())?,
            )
        }
        name => {
            let store = config
                .stores
                .get(name)
                .ok_or_else(|| format!("there is no store named {name:?}"))?;
            Arc::new(s3(store)?)
        }
    })
}

/// Opens the stores and finishes or rolls back what processes that are gone left unfinished. An offline store is
/// logged and changes nothing; the rest of the server runs.
pub async fn start(config: &Config, pool: &PgPool, instance: Uuid) -> Result<Journal, String> {
    let data_dir = config.data_dir.as_ref().ok_or("the stores need a data directory")?;
    let local = FsStore::open(data_dir, LOCAL_TIMEOUT)
        .await
        .map_err(|e| e.to_string())?;
    // The instance marker already vouches for the data directory.
    let mut candidates = vec![Candidate {
        name: "local".into(),
        store: Arc::new(local),
        adopt: true,
    }];
    for (name, store) in &config.stores {
        let opened = s3(store).map_err(|e| format!("store {name}: {e}"))?;
        candidates.push(Candidate {
            name: name.clone(),
            store: Arc::new(opened),
            adopt: false,
        });
    }
    let stores = Stores::check(pool, instance, candidates).await;
    for (name, why) in &stores.offline {
        tracing::error!(store = %name, %why, "store offline: nothing in it changes");
    }
    let journal = Journal::start(pool.clone(), stores)
        .await
        .map_err(|e| format!("cannot start the intent log: {e}"))?;
    match journal.recover().await {
        Ok(done) => tracing::info!(
            rolled_back = done.rolled_back,
            completed = done.completed,
            left = done.busy,
            "file operations recovered"
        ),
        Err(error) => {
            tracing::warn!(%error, "file operation recovery stopped; the next start resumes it")
        }
    }
    Ok(journal)
}

#[cfg(test)]
mod tests {
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use photolib_storage::{
        BlobStore,
        s3::S3Store,
        testing::{garage, staged},
    };
    use uuid::Uuid;

    use super::*;
    use crate::{
        role::Role,
        testing::{config, store},
    };

    #[tokio::test]
    async fn startup_checks_the_stores_and_recovers_what_a_process_that_is_gone_left() {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let data = tempfile::tempdir().unwrap();
        std::fs::write(data.path().join("existing.jpg"), b"the data directory is adopted").unwrap();
        let mut config = config(&[Role::Api], data.path());
        let (fresh, used) = (garage(), garage());
        let staging = tempfile::tempdir().unwrap();
        let (file, hash) = staged(staging.path(), b"a stranger's object");
        S3Store::open(&used, std::time::Duration::from_secs(30))
            .unwrap()
            .put("x.jpg", &file, hash)
            .await
            .unwrap();
        config.stores.insert("b2".into(), store(&fresh));
        config.stores.insert("stranger".into(), store(&used));
        let instance = Uuid::now_v7();

        let journal = start(&config, &db.pool, instance).await.unwrap();
        let online: Vec<_> = journal.stores().online().map(|(name, _)| name).collect();
        assert_eq!(online, ["b2", "local"]);
        assert!(journal.stores().offline["stranger"].contains("not empty"));
        assert!(data.path().join(".photolib/store.json").exists());

        // A planned put whose process is gone is rolled back by the next start.
        let (file, hash) = staged(staging.path(), b"photo");
        drop(journal.put("local", "a.jpg", &file, hash).await.unwrap());
        sqlx::query("UPDATE file_intents SET owner = 42")
            .execute(&db.pool)
            .await
            .unwrap();
        assert!(data.path().join("a.jpg").exists());
        let again = start(&config, &db.pool, instance).await.unwrap();
        assert!(!data.path().join("a.jpg").exists());
        let state: String = sqlx::query_scalar("SELECT state FROM file_intents")
            .fetch_one(&db.pool)
            .await
            .unwrap();
        assert_eq!(state, "rolled_back");
        assert_eq!(
            again.stores().get("b2").unwrap().list("").await.unwrap(),
            [".photolib/store.json"]
        );
    }
}
