//! Store and library markers (ADR-0022 point 2, photolib-design docs/07 §3–4). `.photolib/store.json` ties a store to
//! the instance and its row in `stores`; `.photolib/library.json` ties a library root to its library. A store or
//! library whose marker is missing or names another is offline and nothing in it changes, so a wrong bucket or prefix
//! or an unmounted volume never looks like mass deletion or adopts a stranger's data.

use std::{collections::BTreeMap, sync::Arc};

use serde::{Deserialize, Serialize, de::DeserializeOwned};
use sqlx::PgPool;
use uuid::Uuid;

use crate::{BlobStore, Error, Hash, Result};

pub const STORE_MARKER: &str = ".photolib/store.json";
pub const LIBRARY_MARKER: &str = ".photolib/library.json";

#[derive(Serialize, Deserialize)]
struct StoreMarker {
    version: u32,
    instance_id: Uuid,
    store_id: Uuid,
}

#[derive(Serialize, Deserialize)]
struct LibraryMarker {
    version: u32,
    library_id: Uuid,
    layout_version: u32,
    created_at: String,
}

/// A configured store; `adopt` is for the data directory, which the instance marker already vouches for.
pub struct Candidate {
    pub name: String,
    pub store: Arc<dyn BlobStore>,
    pub adopt: bool,
}

/// The configured stores after their markers were checked.
#[derive(Default)]
pub struct Stores {
    online: BTreeMap<String, Arc<dyn BlobStore>>,
    /// Why each offline store is offline.
    pub offline: BTreeMap<String, String>,
}

impl Stores {
    /// Checks each store's marker against the database, initialising a store that was never used: an empty one, or
    /// an adopted one. A store that cannot be checked is offline too.
    pub async fn check(pool: &PgPool, instance: Uuid, candidates: Vec<Candidate>) -> Stores {
        let mut stores = Stores::default();
        for c in candidates {
            match check_store(pool, instance, &c).await {
                Ok(()) => drop(stores.online.insert(c.name, c.store)),
                Err(Error::Offline(why)) => drop(stores.offline.insert(c.name, why)),
                Err(error) => drop(stores.offline.insert(c.name, error.to_string())),
            }
        }
        stores
    }

    pub fn get(&self, name: &str) -> Result<&Arc<dyn BlobStore>> {
        self.online.get(name).ok_or_else(|| match self.offline.get(name) {
            Some(why) => Error::Offline(format!("{name}: {why}")),
            None => Error::Other(format!("there is no store named {name:?}")),
        })
    }

    pub fn online(&self) -> impl Iterator<Item = (&str, &Arc<dyn BlobStore>)> {
        self.online.iter().map(|(name, store)| (name.as_str(), store))
    }
}

async fn read_json<T: DeserializeOwned>(store: &dyn BlobStore, key: &str) -> Result<Option<T>> {
    match store.get(key, None).await {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|e| Error::Offline(format!("{key} cannot be read: {e}"))),
        Err(Error::NotFound(_)) => Ok(None),
        Err(error) => Err(error),
    }
}

async fn write_json(store: &dyn BlobStore, key: &str, value: &impl Serialize) -> Result<()> {
    write(
        store,
        key,
        &serde_json::to_vec_pretty(value).expect("a marker serialises"),
    )
    .await
}

async fn write(store: &dyn BlobStore, key: &str, bytes: &[u8]) -> Result<()> {
    let fail = |e: std::io::Error| Error::Other(format!("cannot stage {key}: {e}"));
    let staged = tempfile::NamedTempFile::new().map_err(fail)?;
    std::fs::write(staged.path(), bytes).map_err(fail)?;
    store.put(key, staged.path(), Hash::of(bytes)).await.map(drop)
}

fn names(m: &StoreMarker) -> String {
    format!(
        "{STORE_MARKER} names store {} of instance {}",
        m.store_id, m.instance_id
    )
}

/// The store's row in `stores` and its marker.
async fn state(pool: &PgPool, name: &str, store: &dyn BlobStore) -> Result<(Option<Uuid>, Option<StoreMarker>)> {
    let registered = sqlx::query_scalar("SELECT id FROM stores WHERE name = $1")
        .bind(name)
        .fetch_optional(pool)
        .await?;
    Ok((registered, read_json(store, STORE_MARKER).await?))
}

/// Whether a registered store's marker names it and the instance.
fn registered(id: Uuid, found: Option<StoreMarker>, instance: Uuid) -> Result<Uuid> {
    match found {
        Some(m) if (m.instance_id, m.store_id) == (instance, id) => Ok(id),
        Some(m) => Err(Error::Offline(names(&m))),
        None => Err(Error::Offline(format!(
            "{STORE_MARKER} of store {id} is missing: the bucket, prefix or mount is wrong, or the store was emptied"
        ))),
    }
}

/// The instance a store's marker names, if it has one: what recovery from storage takes over.
pub async fn instance(store: &dyn BlobStore) -> Result<Option<Uuid>> {
    Ok(read_json::<StoreMarker>(store, STORE_MARKER)
        .await?
        .map(|m| m.instance_id))
}

/// Checks a store's marker against the database without changing either: its store id, or why it is offline.
pub async fn verify(pool: &PgPool, instance: Uuid, name: &str, store: &dyn BlobStore) -> Result<Uuid> {
    match state(pool, name, store).await? {
        (Some(id), found) => registered(id, found, instance),
        (None, _) => Err(Error::Offline(format!(
            "store {name} was never set up; photolibd sets it up when it starts"
        ))),
    }
}

async fn check_store(pool: &PgPool, instance: Uuid, c: &Candidate) -> Result<()> {
    let store_id = match state(pool, &c.name, c.store.as_ref()).await? {
        (Some(id), found) => return registered(id, found, instance).map(drop),
        (None, Some(m)) if m.instance_id != instance => {
            return Err(Error::Offline(format!("{}, another instance", names(&m))));
        }
        (None, Some(m)) => {
            let other: Option<String> = sqlx::query_scalar("SELECT name FROM stores WHERE id = $1")
                .bind(m.store_id)
                .fetch_optional(pool)
                .await?;
            if let Some(other) = other {
                return Err(Error::Offline(format!("{}, which is {other:?}", names(&m))));
            }
            // Ours, but unrecorded: a first start stopped between the marker and the row.
            m.store_id
        }
        (None, None) => {
            if !c.adopt && !c.store.list("").await?.is_empty() {
                return Err(Error::Offline(format!(
                    "the store is not empty and has no {STORE_MARKER}; photolibd never adopts existing data"
                )));
            }
            let marker = StoreMarker {
                version: 1,
                instance_id: instance,
                store_id: Uuid::now_v7(),
            };
            match write_json(c.store.as_ref(), STORE_MARKER, &marker).await {
                Ok(()) => marker.store_id,
                // Another process initialised it first.
                Err(Error::Exists(_)) => return Box::pin(check_store(pool, instance, c)).await,
                Err(error) => return Err(error),
            }
        }
    };
    sqlx::query("INSERT INTO stores (name, id) VALUES ($1, $2) ON CONFLICT DO NOTHING")
        .bind(&c.name)
        .bind(store_id)
        .execute(pool)
        .await?;
    // Whoever won a race, the row and the marker must now agree.
    Box::pin(check_store(pool, instance, c)).await
}

fn library_marker(root: &str) -> String {
    match root {
        "" => LIBRARY_MARKER.into(),
        root => format!("{root}/{LIBRARY_MARKER}"),
    }
}

/// The marker of a new library, for its root's `.photolib/library.json`.
pub fn library_json(library_id: Uuid) -> Vec<u8> {
    let marker = LibraryMarker {
        version: 1,
        library_id,
        layout_version: 1,
        created_at: jiff::Timestamp::now().to_string(),
    };
    serde_json::to_vec_pretty(&marker).expect("a marker serialises")
}

/// Writes the marker of a new library whose files live under `root`.
pub async fn create_library(store: &dyn BlobStore, root: &str, library_id: Uuid) -> Result<()> {
    write(store, &library_marker(root), &library_json(library_id)).await
}

/// Whether the library root carries the library's own marker; a library without it is offline.
pub async fn library_online(store: &dyn BlobStore, root: &str, library_id: Uuid) -> Result<bool> {
    match read_json::<LibraryMarker>(store, &library_marker(root)).await {
        Ok(found) => Ok(found.is_some_and(|m| m.library_id == library_id)),
        Err(Error::Offline(_)) => Ok(false),
        Err(error) => Err(error),
    }
}
