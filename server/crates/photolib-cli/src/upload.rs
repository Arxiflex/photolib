//! Uploads files: hashes each, creates its upload and sends it, recording each step in the journal.

use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex},
};

use crate::{
    client::{Client, Error, local},
    files::File,
    journal::{Journal, Record},
};

/// What happened to a file; a hash is its BLAKE3, lowercase hex.
pub enum Outcome {
    Uploaded(String),
    /// Its content was uploaded from another file.
    Duplicate(String),
    Failed(Error),
}

pub struct Uploader {
    pub client: Client,
    pub journal: Journal,
    /// The content each file of this run is uploading, so that a copy waits and then skips it.
    claims: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>,
}

impl Uploader {
    pub fn new(client: Client, journal: Journal) -> Uploader {
        Uploader {
            client,
            journal,
            claims: Mutex::default(),
        }
    }

    /// Uploads a file that is not done, telling `progress` the bytes the server has after each append.
    pub async fn upload(&self, file: &File, progress: impl Fn(u64)) -> Outcome {
        let record = self.journal.get(file).unwrap_or(Record {
            path: file.path.to_string_lossy().into_owned(),
            size: file.size,
            mtime: file.mtime,
            blake3: None,
            upload: None,
            done: false,
        });
        let sent = match self.send(file, record.clone(), &progress).await {
            // The server forgot the upload, or the file changed since it was hashed: start over, once.
            Err(Error::Server { reason, .. })
                if ["upload.not_found", "upload.hash_mismatch"].contains(&reason.as_str()) =>
            {
                let fresh = Record {
                    blake3: None,
                    upload: None,
                    ..record
                };
                self.send(file, fresh, &progress).await
            }
            sent => sent,
        };
        sent.unwrap_or_else(Outcome::Failed)
    }

    async fn send(&self, file: &File, mut record: Record, progress: &impl Fn(u64)) -> Result<Outcome, Error> {
        let hash = match record.blake3.take() {
            Some(hash) => hash,
            None => self::hash(&file.path).await?,
        };
        record.blake3 = Some(hash.clone());
        let claim = {
            let mut claims = self.claims.lock().expect("no thread panics holding the claims");
            claims.entry(hash.clone()).or_default().clone()
        };
        let _claimed = claim.lock().await;
        if let Some(upload) = self.journal.uploaded(&hash) {
            record.upload = Some(upload);
            record.done = true;
            self.journal.put(record).map_err(local)?;
            return Ok(Outcome::Duplicate(hash));
        }
        let offset = match record.upload {
            Some(_) => None,
            None => {
                record.upload = Some(self.client.create(file.size, &hash).await?);
                self.journal.put(record.clone()).map_err(local)?;
                Some(0)
            }
        };
        let upload = record.upload.as_deref().expect("created");
        self.client
            .upload(upload, &file.path, offset, file.size, progress)
            .await?;
        record.done = true;
        self.journal.put(record).map_err(local)?;
        Ok(Outcome::Uploaded(hash))
    }
}

/// The BLAKE3 of a file, lowercase hex.
async fn hash(path: &Path) -> Result<String, Error> {
    let path = path.to_owned();
    let hashed = tokio::task::spawn_blocking(move || {
        let mut hasher = blake3::Hasher::new();
        hasher.update_reader(std::fs::File::open(&path)?)?;
        Ok::<_, std::io::Error>(hasher.finalize().to_hex().to_string())
    });
    hashed.await.expect("hashing does not panic").map_err(local)
}
