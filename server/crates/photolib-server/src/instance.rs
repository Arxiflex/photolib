use std::{
    fs::{self, File},
    io::Write,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{db::Database, mounts};

const MARKER_VERSION: u32 = 1;

#[derive(Serialize, Deserialize)]
struct Marker {
    version: u32,
    instance_id: Uuid,
    /// How often `photolibd restore` replaced the database; kept here, where a restored database cannot take it back.
    #[serde(default)]
    restores: u32,
}

fn marker_path(data_dir: &Path) -> PathBuf {
    data_dir.join(".photolib/instance.json")
}

pub(crate) fn read_marker(data_dir: &Path) -> Result<Option<Uuid>, String> {
    Ok(read(data_dir)?.map(|marker| marker.instance_id))
}

/// The epoch of the instance in `data_dir`, `<instance id>.<restores>`: devices that see it change start their sync
/// over and check what they backed up (design 05 §8).
pub fn epoch(data_dir: &Path) -> Result<Option<String>, String> {
    Ok(read(data_dir)?.map(|marker| format!("{}.{}", marker.instance_id, marker.restores)))
}

/// Counts a restore of the database into the marker in `data_dir`, if there is one.
pub(crate) fn count_restore(data_dir: &Path) -> Result<(), String> {
    let Some(mut marker) = read(data_dir)? else {
        return Ok(());
    };
    marker.restores += 1;
    write(data_dir, &marker).map_err(|error| {
        format!(
            "the instance marker {} cannot be written: {error}",
            marker_path(data_dir).display()
        )
    })
}

fn read(data_dir: &Path) -> Result<Option<Marker>, String> {
    let path = marker_path(data_dir);
    let text = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(format!(
                "the instance marker {} cannot be read: {error}",
                path.display()
            ));
        }
    };
    let marker: Marker = serde_json::from_str(&text)
        .map_err(|error| format!("the instance marker {} cannot be read: {error}", path.display()))?;
    if marker.version != MARKER_VERSION {
        let version = marker.version;
        return Err(format!(
            "the instance marker {} is version {version}; this photolibd reads version {MARKER_VERSION}",
            path.display()
        ));
    }
    Ok(Some(marker))
}

pub(crate) fn write_marker(data_dir: &Path, id: Uuid) -> std::io::Result<()> {
    let marker = Marker {
        version: MARKER_VERSION,
        instance_id: id,
        restores: 0,
    };
    write(data_dir, &marker)
}

fn write(data_dir: &Path, marker: &Marker) -> std::io::Result<()> {
    let path = marker_path(data_dir);
    let dir = data_dir.join(".photolib");
    fs::create_dir_all(&dir)?;
    let temp = path.with_extension("json.tmp");
    let mut file = File::create(&temp)?;
    file.write_all(&serde_json::to_vec(marker)?)?;
    file.sync_all()?;
    fs::rename(&temp, &path)?;
    File::open(dir)?.sync_all()
}

fn is_empty_root(data_dir: &Path) -> std::io::Result<bool> {
    let mut entries = fs::read_dir(data_dir)?;
    Ok(entries.all(|entry| entry.is_ok_and(|entry| entry.file_name() == "lost+found")))
}

/// Checks that the data directory and the database belong together, and initialises both on a first start.
pub async fn verify(data_dir: &Path, db: &dyn Database) -> Result<Uuid, String> {
    let facts = || mounts::diagnostics(data_dir);
    if !data_dir.is_dir() {
        return Err(format!(
            "the data directory {} does not exist or is not a directory; {}",
            data_dir.display(),
            facts()
        ));
    }
    let on_disk = read_marker(data_dir)?;
    let in_db = db
        .instance_id()
        .await
        .map_err(|error| format!("the instance marker cannot be read from the database: {error}"))?;
    let marker = marker_path(data_dir);
    match (on_disk, in_db) {
        (Some(disk), Some(database)) if disk == database => Ok(disk),
        (Some(disk), Some(database)) => Err(format!(
            "the data directory and the database belong to different instances: {} says {disk}, the database says {database}; \
             the data directory or the database was replaced, restored from another instance or pointed at the wrong server; {}",
            marker.display(),
            facts()
        )),
        (Some(disk), None) => Err(format!(
            "{} says instance {disk} but the database has no instance marker; the database is empty or was replaced; \
             restore it, or point database.url at the right server; {}",
            marker.display(),
            facts()
        )),
        (None, Some(database)) => Err(format!(
            "the database has instance {database} but the data directory has no instance marker at {}; \
             the volume may be empty or not mounted; {}",
            marker.display(),
            facts()
        )),
        (None, None) => {
            let empty = is_empty_root(data_dir).map_err(|error| {
                format!(
                    "the data directory {} cannot be listed: {error}; {}",
                    data_dir.display(),
                    facts()
                )
            })?;
            if !empty {
                return Err(format!(
                    "the data directory {} is not empty and has no instance marker; photolibd will never initialise a non-empty root; \
                     restore the marker, or start from an empty directory",
                    data_dir.display()
                ));
            }
            let id = Uuid::now_v7();
            let won = db
                .init_instance_id(id)
                .await
                .map_err(|error| format!("the instance marker cannot be stored in the database: {error}"))?;
            if !won {
                return Err("another process initialised the database at the same moment; start again".into());
            }
            write_marker(data_dir, id).map_err(|error| {
                format!(
                    "the instance marker {} cannot be written: {error}; {}",
                    marker.display(),
                    facts()
                )
            })?;
            Ok(id)
        }
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;
    use crate::testing::FakeDb;

    fn marker(dir: &Path) -> std::path::PathBuf {
        dir.join(".photolib/instance.json")
    }

    fn write_marker(dir: &Path, id: Uuid) {
        fs::create_dir_all(dir.join(".photolib")).unwrap();
        fs::write(marker(dir), format!(r#"{{"version":1,"instance_id":"{id}"}}"#)).unwrap();
    }

    #[test]
    fn the_epoch_is_the_instance_and_its_restores_which_an_older_marker_has_none_of() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(epoch(dir.path()), Ok(None));
        let id = Uuid::now_v7();
        write_marker(dir.path(), id);
        assert_eq!(epoch(dir.path()), Ok(Some(format!("{id}.0"))));
        count_restore(dir.path()).unwrap();
        count_restore(dir.path()).unwrap();
        assert_eq!(epoch(dir.path()), Ok(Some(format!("{id}.2"))));
        assert_eq!(read_marker(dir.path()), Ok(Some(id)), "the instance stays");
    }

    async fn refusal(dir: &Path, db: &FakeDb) -> String {
        verify(dir, db).await.expect_err("startup must be refused")
    }

    #[tokio::test]
    async fn a_first_start_on_an_empty_root_and_an_empty_database_initialises_both() {
        let dir = tempfile::tempdir().unwrap();
        let db = FakeDb::default();
        let id = verify(dir.path(), &db).await.unwrap();
        assert_eq!(db.stored(), Some(id));
        let written: serde_json::Value = serde_json::from_slice(&fs::read(marker(dir.path())).unwrap()).unwrap();
        assert_eq!(written["instance_id"], id.to_string());
        assert_eq!(written["version"], 1);
        assert_eq!(
            verify(dir.path(), &db).await.unwrap(),
            id,
            "the next start accepts what the first one wrote"
        );
    }

    #[tokio::test]
    async fn lost_and_found_does_not_make_a_fresh_volume_non_empty() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir(dir.path().join("lost+found")).unwrap();
        assert!(verify(dir.path(), &FakeDb::default()).await.is_ok());
    }

    #[tokio::test]
    async fn matching_markers_are_accepted() {
        let dir = tempfile::tempdir().unwrap();
        let id = Uuid::now_v7();
        write_marker(dir.path(), id);
        assert_eq!(verify(dir.path(), &FakeDb::with_id(id)).await.unwrap(), id);
    }

    #[tokio::test]
    async fn mismatching_markers_are_refused_with_both_ids_and_the_path() {
        let dir = tempfile::tempdir().unwrap();
        let (on_disk, in_db) = (Uuid::now_v7(), Uuid::now_v7());
        write_marker(dir.path(), on_disk);
        let message = refusal(dir.path(), &FakeDb::with_id(in_db)).await;
        for part in [
            on_disk.to_string(),
            in_db.to_string(),
            marker(dir.path()).display().to_string(),
            "the process runs as".into(),
        ] {
            assert!(message.contains(&part), "{part} missing from {message}");
        }
    }

    #[tokio::test]
    async fn an_empty_root_with_a_database_that_has_a_marker_is_refused_and_left_alone() {
        let dir = tempfile::tempdir().unwrap();
        let in_db = Uuid::now_v7();
        let message = refusal(dir.path(), &FakeDb::with_id(in_db)).await;
        assert!(
            message.contains("no instance marker") && message.contains("mounted"),
            "{message}"
        );
        assert!(
            !marker(dir.path()).exists(),
            "an unmounted volume must not be initialised"
        );
        assert!(fs::read_dir(dir.path()).unwrap().next().is_none());
    }

    #[tokio::test]
    async fn a_root_with_a_marker_and_a_database_without_one_is_refused_and_left_alone() {
        let dir = tempfile::tempdir().unwrap();
        write_marker(dir.path(), Uuid::now_v7());
        let db = FakeDb::default();
        let message = refusal(dir.path(), &db).await;
        assert!(message.contains("database has no instance marker"), "{message}");
        assert_eq!(db.stored(), None, "an existing root must never initialise a database");
    }

    #[tokio::test]
    async fn a_non_empty_root_without_a_marker_is_never_initialised() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("IMG_0001.jpg"), b"photo").unwrap();
        let db = FakeDb::default();
        let message = refusal(dir.path(), &db).await;
        assert!(
            message.contains("not empty") && message.contains("never initialise"),
            "{message}"
        );
        assert_eq!(db.stored(), None);
        assert!(!marker(dir.path()).exists());
    }

    #[tokio::test]
    async fn a_missing_data_directory_is_refused_not_created() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("data");
        let message = refusal(&missing, &FakeDb::default()).await;
        assert!(message.contains("does not exist"), "{message}");
        assert!(!missing.exists());
    }

    #[tokio::test]
    async fn a_corrupt_or_newer_marker_is_refused() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join(".photolib")).unwrap();
        fs::write(marker(dir.path()), "{not json").unwrap();
        assert!(refusal(dir.path(), &FakeDb::default()).await.contains("cannot be read"));
        fs::write(
            marker(dir.path()),
            format!(r#"{{"version":2,"instance_id":"{}"}}"#, Uuid::now_v7()),
        )
        .unwrap();
        assert!(refusal(dir.path(), &FakeDb::default()).await.contains("version 2"));
    }

    #[tokio::test]
    async fn losing_the_initialisation_race_writes_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let db = FakeDb::default();
        db.lose_init_race.store(true, std::sync::atomic::Ordering::SeqCst);
        let message = refusal(dir.path(), &db).await;
        assert!(message.contains("another process"), "{message}");
        assert!(!marker(dir.path()).exists());
    }

    #[tokio::test]
    async fn an_unreachable_database_is_reported_as_such() {
        let dir = tempfile::tempdir().unwrap();
        let db = FakeDb::default();
        db.set_down(true);
        assert!(refusal(dir.path(), &db).await.contains("connection refused"));
    }
}
