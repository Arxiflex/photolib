//! Blob stores and journaled file operations (photolib-design docs/07 §3, §6 and ADR-0022): the filesystem driver,
//! the S3 driver, store and library markers, and the intent log in PostgreSQL with its recovery pass.

use std::{fmt, ops::Range, path::Path, path::PathBuf, sync::Arc, time::SystemTime};

use async_trait::async_trait;

pub mod fs;
pub mod hash;
pub mod journal;
pub mod marker;
mod pool;
pub mod s3;
#[cfg(any(test, feature = "testing"))]
pub mod testing;

pub use hash::Hash;

#[derive(Debug)]
pub enum Error {
    /// The key is not a relative path that stays inside the store.
    InvalidKey(String),
    NotFound(String),
    /// Keys are never overwritten.
    Exists(String),
    /// What was read or written does not match its expected size and BLAKE3 hash.
    Integrity(String),
    /// A filesystem or object-store call did not finish in time.
    Timeout(String),
    /// The store's marker is missing or names another store, or the store cannot be reached: nothing in it changes.
    Offline(String),
    Other(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::InvalidKey(why) => write!(f, "invalid key: {why}"),
            Error::NotFound(key) => write!(f, "{key} does not exist"),
            Error::Exists(key) => write!(f, "{key} exists already and is never overwritten"),
            Error::Integrity(why) => write!(f, "integrity: {why}"),
            Error::Timeout(what) => write!(f, "timed out: {what}"),
            Error::Offline(why) => write!(f, "store offline: {why}"),
            Error::Other(why) => f.write_str(why),
        }
    }
}

impl std::error::Error for Error {}

impl From<sqlx::Error> for Error {
    fn from(error: sqlx::Error) -> Error {
        Error::Other(format!("database: {error}"))
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// What `head` knows about an object: its size and the BLAKE3 hash stored with it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Meta {
    pub size: u64,
    pub hash: Option<Hash>,
}

/// A write that was started and neither completed nor aborted: a temporary file or a multipart upload.
#[derive(Debug, Clone)]
pub struct Upload {
    pub key: String,
    pub id: String,
    pub started: SystemTime,
}

/// A file a sandboxed child can read: the original itself, or a verified copy in the job's scratch directory.
#[derive(Debug, PartialEq, Eq)]
pub enum Local {
    InPlace(PathBuf),
    Copy(PathBuf),
}

/// Called at each named step of a write; crash-injection tests stop the process there. An error aborts the write.
pub type Hook = Arc<dyn Fn(&str) -> Result<()> + Send + Sync>;

/// A store of immutable objects under relative keys. Every call runs on the store's own thread pool with a
/// timeout, so a hung mount or endpoint fails calls instead of stalling the server.
#[async_trait]
pub trait BlobStore: Send + Sync {
    /// Writes the staged file under a new key and verifies its size and hash; the hash is kept as object metadata.
    async fn put(&self, key: &str, staged: &Path, hash: Hash) -> Result<Meta>;
    async fn get(&self, key: &str, range: Option<Range<u64>>) -> Result<Vec<u8>>;
    async fn head(&self, key: &str) -> Result<Option<Meta>>;
    /// Succeeds when the key is already gone.
    async fn delete(&self, key: &str) -> Result<()>;
    /// A server-side copy to a new key, verified against the source's size and hash.
    async fn copy(&self, from: &str, to: &str) -> Result<Meta>;
    /// Every key that starts with `prefix`, sorted.
    async fn list(&self, prefix: &str) -> Result<Vec<String>>;
    /// The unfinished writes of keys that start with `prefix`.
    async fn uploads(&self, prefix: &str) -> Result<Vec<Upload>>;
    async fn abort(&self, upload: &Upload) -> Result<()>;
    /// The object as a local file for a job: in place on a filesystem, else a copy in `scratch` checked against
    /// `hash` (a mismatch is an [`Error::Integrity`] and leaves no copy).
    async fn local(&self, key: &str, hash: Hash, scratch: &Path) -> Result<Local>;
}

/// Checks that a key is a relative path of names (no `.`, `..` or empty names, no NUL) within S3's limits.
pub fn check_key(key: &str) -> Result<()> {
    let why = if key.is_empty() {
        "the key is empty"
    } else if key.len() > 1024 {
        "the key is longer than 1024 bytes"
    } else if key.contains('\0') {
        "the key contains NUL"
    } else if key
        .split('/')
        .any(|name| name.is_empty() || name == "." || name == "..")
    {
        "the key has an empty, `.` or `..` name, or starts or ends with /"
    } else if key.split('/').any(|name| name.len() > 255) {
        "a name in the key is longer than 255 bytes"
    } else {
        return Ok(());
    };
    Err(Error::InvalidKey(format!("{why}: {key:?}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_that_could_leave_the_store_are_refused() {
        for bad in [
            "",
            "/etc/passwd",
            "../outside",
            "a/../../b",
            "a/./b",
            "a//b",
            "a/",
            ".",
            "..",
            "a/\0b",
            &format!("{}.jpg", "x".repeat(252)),
            &"a/".repeat(513),
        ] {
            assert!(matches!(check_key(bad), Err(Error::InvalidKey(_))), "{bad:?}");
        }
        for good in [
            "a",
            "2024/2024-01/IMG_0001.HEIC",
            ".photolib/library.json",
            "...",
            "..a/b..",
            "back\\slash",
            "new\nline",
            &"é".repeat(127),
        ] {
            assert!(check_key(good).is_ok(), "{good:?}");
        }
    }
}
