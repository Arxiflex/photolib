//! The filesystem driver. Every path is resolved by the kernel beneath the store's root (`openat2` with
//! `RESOLVE_BENEATH`), so `..` and symlinks cannot leave it; symlinks are refused unless followed explicitly, and then
//! only inside the root. Writes go to `.photolib/tmp/<key>`, are verified and fsynced, renamed without replacing
//! (`RENAME_NOREPLACE`) and the directory is fsynced. The BLAKE3 hash is kept in the `user.photolib.blake3` xattr.

use std::{
    fs::File,
    io,
    ops::Range,
    os::unix::fs::FileExt,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use async_trait::async_trait;
use rustix::{
    fd::OwnedFd,
    fs::{AtFlags, Dir, FileType, Mode, OFlags, RenameFlags, ResolveFlags, XattrFlags},
    io::Errno,
};

use crate::{BlobStore, Error, Hash, Hook, Local, Meta, Result, Upload, check_key, pool::Pool};

const TMP: &str = ".photolib/tmp";
const XATTR: &str = "user.photolib.blake3";
const CHUNK: usize = 8 << 20;

pub struct FsStore {
    inner: Arc<Inner>,
    pool: Pool,
}

/// What tells a file apart until it is hashed: its device and inode, size and last write.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Identity {
    pub dev: u64,
    pub inode: u64,
    pub size: u64,
    pub mtime_ns: i64,
}

impl Identity {
    fn of(stat: &rustix::fs::Stat) -> Identity {
        Identity {
            dev: stat.st_dev,
            inode: stat.st_ino,
            size: stat.st_size as u64,
            mtime_ns: stat.st_mtime * 1_000_000_000 + stat.st_mtime_nsec as i64,
        }
    }
}

/// An entry of a folder.
#[derive(Debug, PartialEq, Eq)]
pub enum Entry {
    File(String, Identity),
    Dir(String),
}

impl Entry {
    pub fn name(&self) -> &str {
        match self {
            Entry::File(name, _) | Entry::Dir(name) => name,
        }
    }
}

struct Inner {
    root: OwnedFd,
    path: PathBuf,
    resolve: ResolveFlags,
    hook: Option<Hook>,
}

impl FsStore {
    pub async fn open(root: &Path, timeout: Duration) -> Result<FsStore> {
        let pool = Pool::new("fs", timeout)?;
        let path = root.to_owned();
        let flags = OFlags::DIRECTORY | OFlags::RDONLY | OFlags::CLOEXEC;
        let fd = pool
            .blocking(&format!("open {}", root.display()), move || {
                rustix::fs::open(&path, flags, Mode::empty())
                    .map_err(|e| Error::Other(format!("cannot open {}: {}", path.display(), io::Error::from(e))))
            })
            .await?;
        let resolve = ResolveFlags::BENEATH | ResolveFlags::NO_MAGICLINKS | ResolveFlags::NO_SYMLINKS;
        let inner = Inner {
            root: fd,
            path: root.to_owned(),
            resolve,
            hook: None,
        };
        Ok(FsStore {
            inner: Arc::new(inner),
            pool,
        })
    }

    /// Follows symlinks that stay inside the root (external libraries may opt in); others are still refused.
    pub fn follow_symlinks(mut self) -> Self {
        self.configure().resolve.remove(ResolveFlags::NO_SYMLINKS);
        self
    }

    /// The regular files and folders in the folder `dir` (`""` is the root), sorted by name. Symlinks, other kinds of
    /// files and names that are not UTF-8 are left out; listing never follows a symlink.
    pub async fn entries(&self, dir: &str) -> Result<Vec<Entry>> {
        if !dir.is_empty() {
            check_key(dir)?;
        }
        let d = dir.to_owned();
        self.call(format!("list {dir:?}"), move |s| {
            let fd = s.dir(&d, &d, false)?;
            let mut entries = vec![];
            for entry in Dir::read_from(&fd).map_err(|e| errno(&d, "list", e))? {
                let entry = entry.map_err(|e| errno(&d, "list", e))?;
                let Ok(name) = entry.file_name().to_str() else {
                    continue;
                };
                if name == "." || name == ".." {
                    continue;
                }
                match rustix::fs::statat(&fd, name, AtFlags::SYMLINK_NOFOLLOW) {
                    Ok(stat) => match FileType::from_raw_mode(stat.st_mode) {
                        FileType::Directory => entries.push(Entry::Dir(name.into())),
                        FileType::RegularFile => entries.push(Entry::File(name.into(), Identity::of(&stat))),
                        _ => {}
                    },
                    Err(Errno::NOENT) => {}
                    Err(e) => return Err(errno(&format!("{d}/{name}"), "stat", e)),
                }
            }
            entries.sort_by(|a, b| a.name().cmp(b.name()));
            Ok(entries)
        })
        .await
    }

    /// Runs `read` on the regular file at `key` and its identity, on the store's threads within its timeout.
    pub async fn with_file<T: Send + 'static>(
        &self,
        key: &str,
        read: impl FnOnce(&File, Identity) -> T + Send + 'static,
    ) -> Result<T> {
        check_key(key)?;
        let k = key.to_owned();
        self.call(format!("read {key:?}"), move |s| {
            let file = s.existing(&k)?;
            let stat = rustix::fs::fstat(&file).map_err(|e| errno(&k, "stat", e))?;
            Ok(read(&file, Identity::of(&stat)))
        })
        .await
    }

    pub fn with_hook(mut self, hook: Hook) -> Self {
        self.configure().hook = Some(hook);
        self
    }

    fn configure(&mut self) -> &mut Inner {
        Arc::get_mut(&mut self.inner).expect("a store is configured before it is shared")
    }

    async fn call<T: Send + 'static>(
        &self,
        what: String,
        call: impl FnOnce(&Inner) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let inner = self.inner.clone();
        self.pool.blocking(&what, move || call(&inner)).await
    }

    /// Copies `src` to a new key chunk by chunk (each chunk one timed call), checks `expected`, then commits.
    async fn write(&self, key: &str, src: File, expected: Option<Hash>) -> Result<Meta> {
        check_key(key)?;
        let k = key.to_owned();
        let w = Arc::new(self.call(format!("create {key:?}"), move |s| s.create(&k, src)).await?);
        let mut hasher = blake3::Hasher::new();
        let mut size = 0;
        let written = loop {
            let (w2, mut h) = (w.clone(), hasher.clone());
            let chunk = self
                .call(format!("write {key:?}"), move |s| {
                    let n = w2.chunk(size, &mut h)?;
                    if n > 0 {
                        s.step("part")?;
                    }
                    Ok((n, h))
                })
                .await;
            match chunk {
                Ok((0, _)) => break Ok(()),
                Ok((n, h)) => (size, hasher) = (size + n as u64, h),
                Err(error) => break Err(error),
            }
        };
        let hash = Hash::from(hasher.finalize());
        let w2 = w.clone();
        let committed = match (written, expected) {
            (Err(error), _) => Err(error),
            (Ok(()), Some(expected)) if expected != hash => Err(Error::Integrity(format!(
                "{key:?} was written as {hash:?}, expected {expected:?}"
            ))),
            (Ok(()), _) => self.call(format!("commit {key:?}"), move |s| w2.commit(s, hash)).await,
        };
        if committed.is_err() {
            let w2 = w.clone();
            let _ = self.call(format!("discard {key:?}"), move |_| w2.discard()).await;
        }
        committed.map(|()| Meta { size, hash: Some(hash) })
    }
}

/// A write in progress: the temporary file and the directories it moves between.
struct Writer {
    key: String,
    name: String,
    tmp_dir: OwnedFd,
    dir: OwnedFd,
    file: File,
    src: File,
}

impl Writer {
    fn chunk(&self, offset: u64, hasher: &mut blake3::Hasher) -> Result<usize> {
        let mut buf = vec![0; CHUNK];
        let mut n = 0;
        while n < buf.len() {
            match self.src.read_at(&mut buf[n..], offset + n as u64) {
                Ok(0) => break,
                Ok(read) => n += read,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                Err(e) => return Err(io_error(&self.key, "read the source of", e)),
            }
        }
        self.file
            .write_all_at(&buf[..n], offset)
            .map_err(|e| io_error(&self.key, "write", e))?;
        hasher.update(&buf[..n]);
        Ok(n)
    }

    fn commit(&self, store: &Inner, hash: Hash) -> Result<()> {
        let fail = |op, e: Errno| errno(&self.key, op, e);
        match rustix::fs::fsetxattr(&self.file, XATTR, &hash.0, XattrFlags::empty()) {
            Ok(()) | Err(Errno::NOTSUP) => {}
            Err(e) => return Err(fail("tag", e)),
        }
        rustix::fs::fsync(&self.file).map_err(|e| fail("fsync", e))?;
        store.step("synced")?;
        let flags = RenameFlags::NOREPLACE;
        match rustix::fs::renameat_with(&self.tmp_dir, &self.name, &self.dir, &self.name, flags) {
            Ok(()) => {}
            // Filesystems without RENAME_NOREPLACE (some NFS and SMB servers): a hard link never replaces either.
            Err(Errno::INVAL | Errno::NOSYS | Errno::NOTSUP) => {
                rustix::fs::linkat(&self.tmp_dir, &self.name, &self.dir, &self.name, AtFlags::empty())
                    .map_err(|e| fail("link", e))?;
                rustix::fs::unlinkat(&self.tmp_dir, &self.name, AtFlags::empty()).map_err(|e| fail("unlink", e))?;
            }
            Err(e) => return Err(fail("rename", e)),
        }
        rustix::fs::fsync(&self.dir).map_err(|e| fail("fsync the directory of", e))
    }

    fn discard(&self) -> Result<()> {
        match rustix::fs::unlinkat(&self.tmp_dir, &self.name, AtFlags::empty()) {
            Ok(()) | Err(Errno::NOENT) => Ok(()),
            Err(e) => Err(errno(&self.key, "discard", e)),
        }
    }
}

impl Inner {
    fn step(&self, name: &str) -> Result<()> {
        self.hook.as_ref().map_or(Ok(()), |hook| hook(name))
    }

    fn open_at(&self, dir: &OwnedFd, path: &str, flags: OFlags) -> rustix::io::Result<OwnedFd> {
        // openat2 refuses a mode without O_CREAT.
        let mode = Mode::from_raw_mode(if flags.contains(OFlags::CREATE) { 0o644 } else { 0 });
        rustix::fs::openat2(dir, path, flags | OFlags::CLOEXEC, mode, self.resolve)
    }

    /// The directory of a key, created (and its parents fsynced) when `create` is set.
    fn dir(&self, key: &str, rel: &str, create: bool) -> Result<OwnedFd> {
        let flags = OFlags::DIRECTORY | OFlags::RDONLY;
        let fail = |e| errno(key, "open the directory of", e);
        match self.open_at(&self.root, if rel.is_empty() { "." } else { rel }, flags) {
            Err(Errno::NOENT) if create => {
                let mut dir = self.open_at(&self.root, ".", flags).map_err(fail)?;
                for name in rel.split('/') {
                    match rustix::fs::mkdirat(&dir, name, Mode::from_raw_mode(0o755)) {
                        Ok(()) => rustix::fs::fsync(&dir).map_err(fail)?,
                        Err(Errno::EXIST) => {}
                        Err(e) => return Err(fail(e)),
                    }
                    dir = self.open_at(&dir, name, flags).map_err(fail)?;
                }
                Ok(dir)
            }
            opened => opened.map_err(fail),
        }
    }

    /// The regular file at `key`, `None` when there is none.
    fn file(&self, key: &str) -> Result<Option<File>> {
        // O_NONBLOCK: opening a FIFO must not wait for a writer.
        match self.open_at(&self.root, key, OFlags::RDONLY | OFlags::NONBLOCK) {
            Ok(fd) => match rustix::fs::fstat(&fd) {
                Ok(stat) if FileType::from_raw_mode(stat.st_mode) == FileType::RegularFile => Ok(Some(fd.into())),
                Ok(_) => Ok(None),
                Err(e) => Err(errno(key, "stat", e)),
            },
            Err(Errno::NOENT | Errno::NOTDIR) => Ok(None),
            Err(e) => Err(errno(key, "open", e)),
        }
    }

    fn existing(&self, key: &str) -> Result<File> {
        self.file(key)?.ok_or_else(|| Error::NotFound(key.into()))
    }

    fn create(&self, key: &str, src: File) -> Result<Writer> {
        if self.file(key)?.is_some() {
            return Err(Error::Exists(key.into()));
        }
        let (rel, name) = key.rsplit_once('/').unwrap_or(("", key));
        let tmp_rel = if rel.is_empty() {
            TMP.to_string()
        } else {
            format!("{TMP}/{rel}")
        };
        let tmp_dir = self.dir(key, &tmp_rel, true)?;
        let dir = self.dir(key, rel, true)?;
        let flags = OFlags::WRONLY | OFlags::CREATE | OFlags::TRUNC;
        let file = self
            .open_at(&tmp_dir, name, flags)
            .map_err(|e| errno(key, "create", e))?;
        Ok(Writer {
            key: key.into(),
            name: name.into(),
            tmp_dir,
            dir,
            file: file.into(),
            src,
        })
    }

    fn meta(&self, key: &str, file: &File) -> Result<Meta> {
        let size = file.metadata().map_err(|e| io_error(key, "stat", e))?.len();
        let mut hash = [0u8; 32];
        let hash = match rustix::fs::fgetxattr(file, XATTR, &mut hash) {
            Ok(32) => Some(Hash(hash)),
            Ok(_) | Err(Errno::NODATA | Errno::NOTSUP | Errno::RANGE) => None,
            Err(e) => return Err(errno(key, "read the hash of", e)),
        };
        Ok(Meta { size, hash })
    }

    /// Regular files below `rel`, as keys; the temporary directory is skipped unless it is what is walked. Nothing
    /// stays open, so millions of files list within the process's file limit.
    fn walk(&self, rel: &str, keys: &mut Vec<String>) -> Result<()> {
        // Listing never follows a symlink, as S3 has no directories that could lead elsewhere.
        let dir = match self.dir(rel, rel, false) {
            Err(Error::NotFound(_) | Error::InvalidKey(_)) => return Ok(()),
            dir => dir?,
        };
        let entries = Dir::read_from(&dir).map_err(|e| errno(rel, "list", e))?;
        for entry in entries {
            let entry = entry.map_err(|e| errno(rel, "list", e))?;
            let Ok(name) = entry.file_name().to_str() else {
                continue;
            };
            if name == "." || name == ".." {
                continue;
            }
            let key = if rel.is_empty() {
                name.to_string()
            } else {
                format!("{rel}/{name}")
            };
            if key == TMP && rel != TMP {
                continue;
            }
            match rustix::fs::statat(&dir, name, AtFlags::SYMLINK_NOFOLLOW).map(|s| FileType::from_raw_mode(s.st_mode))
            {
                Ok(FileType::Directory) => self.walk(&key, keys)?,
                Ok(FileType::RegularFile) => keys.push(key),
                Ok(_) | Err(Errno::NOENT) => {}
                Err(e) => return Err(errno(&key, "stat", e)),
            }
        }
        Ok(())
    }

    /// Keys starting with `prefix` below `base` (relative to `base`).
    fn keys(&self, base: &str, prefix: &str) -> Result<Vec<String>> {
        let start = prefix.rsplit_once('/').map_or("", |(dir, _)| dir);
        let rel = [base, start]
            .iter()
            .filter(|p| !p.is_empty())
            .copied()
            .collect::<Vec<_>>()
            .join("/");
        let mut found = Vec::new();
        self.walk(&rel, &mut found)?;
        let strip = if base.is_empty() { 0 } else { base.len() + 1 };
        let mut keys: Vec<_> = found
            .into_iter()
            .map(|key| key[strip..].to_string())
            .filter(|key| key.starts_with(prefix))
            .collect();
        keys.sort();
        Ok(keys)
    }
}

fn errno(key: &str, op: &str, e: Errno) -> Error {
    match e {
        Errno::NOENT => Error::NotFound(key.into()),
        Errno::EXIST => Error::Exists(key.into()),
        Errno::XDEV | Errno::LOOP => {
            Error::InvalidKey(format!("{key:?} leads outside the store root or through a symlink"))
        }
        _ => io_error(key, op, e.into()),
    }
}

fn io_error(key: &str, op: &str, e: io::Error) -> Error {
    Error::Other(format!("cannot {op} {key:?}: {e}"))
}

#[async_trait]
impl BlobStore for FsStore {
    async fn put(&self, key: &str, staged: &Path, hash: Hash) -> Result<Meta> {
        let src = File::open(staged).map_err(|e| Error::Other(format!("cannot open {}: {e}", staged.display())))?;
        self.write(key, src, Some(hash)).await
    }

    async fn get(&self, key: &str, range: Option<Range<u64>>) -> Result<Vec<u8>> {
        check_key(key)?;
        let k = key.to_owned();
        self.call(format!("get {key:?}"), move |s| {
            let file = s.existing(&k)?;
            let size = file.metadata().map_err(|e| io_error(&k, "stat", e))?.len();
            let range = range.unwrap_or(0..size);
            let range = range.start.min(size)..range.end.min(size);
            let mut buf = vec![0; (range.end.saturating_sub(range.start)) as usize];
            file.read_exact_at(&mut buf, range.start)
                .map_err(|e| io_error(&k, "read", e))?;
            Ok(buf)
        })
        .await
    }

    async fn head(&self, key: &str) -> Result<Option<Meta>> {
        check_key(key)?;
        let k = key.to_owned();
        self.call(format!("head {key:?}"), move |s| {
            s.file(&k)?.map(|f| s.meta(&k, &f)).transpose()
        })
        .await
    }

    async fn delete(&self, key: &str) -> Result<()> {
        check_key(key)?;
        let k = key.to_owned();
        self.call(format!("delete {key:?}"), move |s| {
            let (rel, name) = k.rsplit_once('/').unwrap_or(("", &k));
            let dir = match s.dir(&k, rel, false) {
                Err(Error::NotFound(_)) => return Ok(()),
                dir => dir?,
            };
            match rustix::fs::statat(&dir, name, AtFlags::SYMLINK_NOFOLLOW).map(|s| FileType::from_raw_mode(s.st_mode))
            {
                Ok(FileType::RegularFile) => {}
                Err(Errno::NOENT) => return Ok(()),
                Ok(FileType::Symlink) => return Err(errno(&k, "delete", Errno::LOOP)),
                Ok(_) => return Err(Error::Other(format!("cannot delete {k:?}: not a file"))),
                Err(e) => return Err(errno(&k, "stat", e)),
            }
            match rustix::fs::unlinkat(&dir, name, AtFlags::empty()) {
                Ok(()) => rustix::fs::fsync(&dir).map_err(|e| errno(&k, "fsync the directory of", e)),
                Err(Errno::NOENT) => Ok(()),
                Err(e) => Err(errno(&k, "delete", e)),
            }
        })
        .await
    }

    async fn copy(&self, from: &str, to: &str) -> Result<Meta> {
        check_key(from)?;
        let k = from.to_owned();
        let (src, meta) = self
            .call(format!("open {from:?}"), move |s| {
                let file = s.existing(&k)?;
                let meta = s.meta(&k, &file)?;
                Ok((file, meta))
            })
            .await?;
        self.write(to, src, meta.hash).await
    }

    async fn list(&self, prefix: &str) -> Result<Vec<String>> {
        let p = prefix.to_owned();
        self.call(format!("list {prefix:?}"), move |s| s.keys("", &p)).await
    }

    async fn uploads(&self, prefix: &str) -> Result<Vec<Upload>> {
        let p = prefix.to_owned();
        self.call(format!("list the uploads of {prefix:?}"), move |s| {
            let mut uploads = vec![];
            for key in s.keys(TMP, &p)? {
                // A write that ended meanwhile left nothing to abort.
                let Some(file) = s.file(&format!("{TMP}/{key}"))? else {
                    continue;
                };
                let modified = file.metadata().and_then(|m| m.modified());
                let started = modified.map_err(|e| io_error(&key, "stat", e))?;
                uploads.push(Upload {
                    key,
                    id: String::new(),
                    started,
                });
            }
            Ok(uploads)
        })
        .await
    }

    async fn abort(&self, upload: &Upload) -> Result<()> {
        check_key(&upload.key)?;
        let k = upload.key.clone();
        self.call(format!("abort {k:?}"), move |s| {
            let (rel, name) = k.rsplit_once('/').unwrap_or(("", &k));
            let tmp = if rel.is_empty() {
                TMP.to_string()
            } else {
                format!("{TMP}/{rel}")
            };
            match s.dir(&k, &tmp, false) {
                Ok(dir) => match rustix::fs::unlinkat(&dir, name, AtFlags::empty()) {
                    Ok(()) | Err(Errno::NOENT) => Ok(()),
                    Err(e) => Err(errno(&k, "abort", e)),
                },
                Err(Error::NotFound(_)) => Ok(()),
                Err(e) => Err(e),
            }
        })
        .await
    }

    async fn local(&self, key: &str, _hash: Hash, _scratch: &Path) -> Result<Local> {
        check_key(key)?;
        let k = key.to_owned();
        self.call(format!("open {key:?}"), move |s| {
            s.existing(&k)?;
            Ok(Local::InPlace(s.path.join(&k)))
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::symlink;

    use super::*;
    use crate::testing::staged;

    async fn store(root: &Path) -> FsStore {
        FsStore::open(root, Duration::from_secs(10)).await.unwrap()
    }

    /// A root holding `inside.jpg`, `in` -> `inside.jpg`, `out` -> a directory outside, `abs` -> an outside file
    /// by absolute path and `rel` -> the same by `..`.
    fn layout() -> (tempfile::TempDir, PathBuf, PathBuf) {
        let base = tempfile::tempdir().unwrap();
        let (root, outside) = (base.path().join("root"), base.path().join("outside"));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("secret"), b"secret").unwrap();
        std::fs::write(root.join("inside.jpg"), b"inside").unwrap();
        symlink("inside.jpg", root.join("in")).unwrap();
        symlink(&outside, root.join("out")).unwrap();
        symlink(outside.join("secret"), root.join("abs")).unwrap();
        symlink("../outside/secret", root.join("rel")).unwrap();
        (base, root, outside)
    }

    fn outside_is_untouched(outside: &Path) {
        let names: Vec<_> = std::fs::read_dir(outside)
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names, ["secret"]);
        assert_eq!(std::fs::read(outside.join("secret")).unwrap(), b"secret");
    }

    async fn escapes_are_refused(store: &FsStore, outside: &Path) {
        let dir = tempfile::tempdir().unwrap();
        let (file, hash) = staged(dir.path(), b"x");
        let escaping = |result: Result<()>| assert!(matches!(result, Err(Error::InvalidKey(_))), "{result:?}");
        for key in ["out/secret", "abs", "rel"] {
            escaping(store.get(key, None).await.map(drop));
            escaping(store.head(key).await.map(drop));
            escaping(store.delete(key).await);
            escaping(store.copy(key, "copied").await.map(drop));
            escaping(store.local(key, hash, dir.path()).await.map(drop));
        }
        escaping(store.put("out/new", &file, hash).await.map(drop));
        escaping(store.put("out/deeper/new", &file, hash).await.map(drop));
        escaping(store.copy("inside.jpg", "out/copied").await.map(drop));
        assert_eq!(store.list("").await.unwrap(), ["inside.jpg"]);
        assert_eq!(store.list("out/").await.unwrap(), Vec::<String>::new());
        outside_is_untouched(outside);
    }

    #[tokio::test]
    async fn symlinks_are_refused_by_default() {
        let (_base, root, outside) = layout();
        let store = store(&root).await;
        escapes_are_refused(&store, &outside).await;
        assert!(matches!(store.get("in", None).await, Err(Error::InvalidKey(_))));
    }

    #[tokio::test]
    async fn followed_symlinks_never_leave_the_root() {
        let (_base, root, outside) = layout();
        let store = store(&root).await.follow_symlinks();
        escapes_are_refused(&store, &outside).await;
        assert_eq!(store.get("in", None).await.unwrap(), b"inside");
    }

    #[tokio::test]
    async fn a_folder_lists_its_files_with_their_identity_and_its_folders_never_through_symlinks() {
        let (_base, root, _outside) = layout();
        std::fs::create_dir(root.join("2024")).unwrap();
        std::fs::write(root.join("2024/b.jpg"), b"bb").unwrap();
        let fifo = root.join("2024/pipe");
        rustix::fs::mknodat(rustix::fs::CWD, &fifo, FileType::Fifo, Mode::RUSR, 0).unwrap();
        let identity = |path: PathBuf| {
            use std::os::unix::fs::MetadataExt;
            let meta = std::fs::metadata(path).unwrap();
            Identity {
                dev: meta.dev(),
                inode: meta.ino(),
                size: meta.size(),
                mtime_ns: meta.mtime() * 1_000_000_000 + meta.mtime_nsec(),
            }
        };
        let (inside, b) = (identity(root.join("inside.jpg")), identity(root.join("2024/b.jpg")));
        for store in [store(&root).await, store(&root).await.follow_symlinks()] {
            assert_eq!(
                store.entries("").await.unwrap(),
                [Entry::Dir("2024".into()), Entry::File("inside.jpg".into(), inside)]
            );
            assert_eq!(store.entries("2024").await.unwrap(), [Entry::File("b.jpg".into(), b)]);
            assert!(matches!(store.entries("out").await, Err(Error::InvalidKey(_))));
            assert!(matches!(store.entries("nowhere").await, Err(Error::NotFound(_))));
            let read = store.with_file("2024/b.jpg", |file, id| {
                let mut data = vec![0; 2];
                file.read_exact_at(&mut data, 0).map(|()| (data, id)).unwrap()
            });
            assert_eq!(read.await.unwrap(), (b"bb".to_vec(), b));
            for (key, refused) in [("abs", "symlink"), ("2024/pipe", "fifo"), ("2024", "folder")] {
                let opened = store.with_file(key, |_, _| ()).await;
                assert!(
                    matches!(opened, Err(Error::InvalidKey(_) | Error::NotFound(_))),
                    "{refused}"
                );
            }
        }
    }

    #[tokio::test]
    async fn a_fifo_is_not_an_object_and_never_blocks() {
        let root = tempfile::tempdir().unwrap();
        rustix::fs::mknodat(
            rustix::fs::CWD,
            root.path().join("pipe"),
            FileType::Fifo,
            Mode::from_raw_mode(0o600),
            0,
        )
        .unwrap();
        let store = store(root.path()).await;
        assert_eq!(store.head("pipe").await.unwrap(), None);
        assert!(matches!(store.get("pipe", None).await, Err(Error::NotFound(_))));
    }

    #[tokio::test]
    async fn a_hung_filesystem_call_times_out_while_other_stores_carry_on() {
        let root = tempfile::tempdir().unwrap();
        let hung = FsStore::open(root.path(), Duration::from_millis(300))
            .await
            .unwrap()
            .with_hook(Arc::new(|_| {
                std::thread::sleep(Duration::from_secs(5));
                Ok(())
            }));
        let staging = tempfile::tempdir().unwrap();
        let (file, hash) = staged(staging.path(), b"photo");
        let started = photolib_spawn::Running::start();
        let put = hung.put("a.jpg", &file, hash).await;
        assert!(matches!(put, Err(Error::Timeout(_))), "{put:?}");
        assert!(started.elapsed() < Duration::from_secs(2), "{:?}", started.elapsed());
        store(root.path()).await.put("b.jpg", &file, hash).await.unwrap();
        assert_eq!(hung.list("").await.unwrap(), ["b.jpg"]);
    }

    #[tokio::test]
    async fn writes_leave_no_temporary_files_and_keep_the_hash_in_an_xattr() {
        let root = tempfile::tempdir().unwrap();
        let store = store(root.path()).await;
        let (file, hash) = staged(root.path(), b"photo");
        store.put("a/b.jpg", &file, hash).await.unwrap();
        let mut xattr = [0u8; 32];
        rustix::fs::getxattr(root.path().join("a/b.jpg"), XATTR, &mut xattr).unwrap();
        assert_eq!(Hash(xattr), hash);
        assert!(
            std::fs::read_dir(root.path().join(TMP))
                .unwrap()
                .all(|e| e.unwrap().path().is_dir())
        );
        assert!(store.uploads("").await.unwrap().is_empty());
    }
}
