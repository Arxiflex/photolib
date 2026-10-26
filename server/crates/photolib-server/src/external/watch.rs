//! Watches the folders of external libraries on local file systems with inotify (photolib-design docs/07 §4,
//! ADR-0257), from each `worker:io` process: a file written or moved into a folder, or a new subfolder, is a hint of
//! that folder a second after the last change. A watch per folder, up to half of the kernel's `max_user_watches` or
//! until it refuses more; a library on a network file system, whose events never come, gets none. Its library records
//! how many folders no watch covers, which `rescan` polls instead, and the log says so.

use std::{
    collections::{BTreeSet, HashMap, HashSet},
    os::fd::AsFd,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use nix::{
    errno::Errno,
    poll::{PollFd, PollFlags, PollTimeout},
    sys::inotify::{AddWatchFlags, InitFlags, Inotify, InotifyEvent, WatchDescriptor},
};
use sqlx::PgPool;
use tokio::{sync::mpsc, time::Instant};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use super::{hint, join};
use crate::mounts;

/// How long a folder stays quiet before its hint: a copy of several files becomes one listing.
const SETTLE: Duration = Duration::from_secs(1);
/// How often the watches follow the libraries and their folders.
const REFRESH: Duration = Duration::from_mins(10);

/// The folders watched, by watch and by library and path (a relocated library's are other paths).
struct Watches {
    inotify: Arc<Inotify>,
    folders: HashMap<WatchDescriptor, (Uuid, String, PathBuf)>,
    watched: HashSet<(Uuid, PathBuf)>,
    limit: usize,
}

/// Watches until `shutdown`, at most `limit` folders (`None`: half of what the kernel allows).
pub async fn watch(pool: PgPool, limit: Option<usize>, shutdown: CancellationToken) {
    let inotify = match Inotify::init(InitFlags::IN_NONBLOCK | InitFlags::IN_CLOEXEC) {
        Ok(inotify) => Arc::new(inotify),
        Err(error) => {
            tracing::warn!(%error, "cannot watch external libraries: they are polled");
            return shutdown.cancelled().await;
        }
    };
    let (events, mut received) = mpsc::unbounded_channel();
    let reader = inotify.clone();
    std::thread::spawn(move || read(&reader, &events));
    let mut watches = Watches {
        inotify,
        folders: HashMap::new(),
        watched: HashSet::new(),
        limit: limit.unwrap_or_else(|| kernel_limit() / 2),
    };
    let (mut pending, mut changed, mut refresh) = (HashSet::new(), Instant::now(), Instant::now());
    loop {
        let wake = if pending.is_empty() {
            refresh
        } else {
            refresh.min(after(changed, SETTLE))
        };
        tokio::select! {
            () = shutdown.cancelled() => return,
            Some(events) = received.recv() => {
                watches.changed(&pool, events, &mut pending).await;
                changed = Instant::now();
            }
            () = tokio::time::sleep_until(wake) => {
                if !pending.is_empty()
                    && Instant::now() >= after(changed, SETTLE)
                    && let Err(error) = hints(&pool, pending.drain()).await
                {
                    tracing::warn!(%error, "cannot queue the hints of changed folders");
                }
                if Instant::now() >= refresh {
                    if let Err(error) = watches.refresh(&pool).await {
                        tracing::warn!(%error, "cannot follow the external libraries' folders");
                    }
                    refresh = after(Instant::now(), REFRESH);
                }
            }
        }
    }
}

/// `wait` after `at`.
fn after(at: Instant, wait: Duration) -> Instant {
    at.checked_add(wait).unwrap_or(at)
}

/// Reads the events of `inotify` into `events` on a thread of its own, until nobody receives them.
fn read(inotify: &Inotify, events: &mpsc::UnboundedSender<Vec<InotifyEvent>>) {
    while !events.is_closed() {
        let mut ready = [PollFd::new(inotify.as_fd(), PollFlags::POLLIN)];
        let read = match nix::poll::poll(&mut ready, PollTimeout::from(1000_u16)) {
            Ok(0) | Err(Errno::EINTR) => continue,
            Ok(_) => inotify.read_events(),
            Err(error) => Err(error),
        };
        match read {
            Ok(read) => {
                if events.send(read).is_err() {
                    return;
                }
            }
            Err(Errno::EAGAIN) => {}
            Err(error) => return tracing::warn!(%error, "cannot read the watches' events: folders are polled"),
        }
    }
}

impl Watches {
    /// Watches every folder of every external library that is not offline, as far as the limit allows, and records
    /// how many no watch covers.
    async fn refresh(&mut self, pool: &PgPool) -> sqlx::Result<()> {
        let libraries: Vec<(Uuid, String)> =
            sqlx::query_as("SELECT id, root_uri FROM libraries WHERE kind = 'external' AND state <> 'offline'")
                .fetch_all(pool)
                .await?;
        let mountinfo = mounts::current_mountinfo().unwrap_or_default();
        for (id, root) in libraries {
            let files: Vec<String> = sqlx::query_scalar("SELECT DISTINCT dir FROM library_files WHERE library_id = $1")
                .bind(id)
                .fetch_all(pool)
                .await?;
            // Each folder with the folders above it, the shallow ones first.
            let mut dirs = BTreeSet::from([(0, String::new())]);
            for dir in files.iter().filter(|dir| !dir.is_empty()) {
                let ends = dir.match_indices('/').map(|(end, _)| end).chain([dir.len()]);
                for (depth, end) in ends.enumerate() {
                    dirs.extend(dir.get(..end).map(|above| (depth.saturating_add(1), above.to_owned())));
                }
            }
            let remote = mounts::mount_of(&mountinfo, Path::new(&root)).is_some_and(|m| m.is_unsafe_for_state());
            let unwatched = (dirs.iter())
                .filter(|(_, dir)| remote || !self.add(id, &root, dir))
                .count();
            if unwatched > 0 && !remote {
                tracing::warn!(
                    library = %id,
                    unwatched,
                    "the watches ran out: these folders are polled; raise fs.inotify.max_user_watches"
                );
            }
            sqlx::query("UPDATE libraries SET unwatched = $2 WHERE id = $1 AND unwatched IS DISTINCT FROM $2")
                .bind(id)
                .bind(i32::try_from(unwatched).unwrap_or(i32::MAX))
                .execute(pool)
                .await?;
        }
        Ok(())
    }

    /// Watches the folder `dir` of library `id` at `root`, unless the limit is reached or the kernel refuses.
    fn add(&mut self, id: Uuid, root: &str, dir: &str) -> bool {
        let path = Path::new(root).join(dir);
        if self.watched.contains(&(id, path.clone())) {
            return true;
        }
        if self.folders.len() >= self.limit {
            return false;
        }
        let events = AddWatchFlags::IN_CLOSE_WRITE
            | AddWatchFlags::IN_MOVED_TO
            | AddWatchFlags::IN_CREATE
            | AddWatchFlags::IN_ONLYDIR
            | AddWatchFlags::IN_DONT_FOLLOW;
        match self.inotify.add_watch(&path, events) {
            Ok(wd) => {
                self.watched.insert((id, path.clone()));
                self.folders.insert(wd, (id, dir.to_owned(), path));
                true
            }
            Err(error) => {
                if error == Errno::ENOSPC {
                    self.limit = self.folders.len();
                }
                false
            }
        }
    }

    /// Notes the folders that `events` changed in `pending` and watches new subfolders; when the kernel dropped
    /// events, every watched library is scanned again.
    async fn changed(&mut self, pool: &PgPool, events: Vec<InotifyEvent>, pending: &mut HashSet<(Uuid, String)>) {
        let mut overflow = false;
        for event in events {
            overflow |= event.mask.contains(AddWatchFlags::IN_Q_OVERFLOW);
            let Some((id, dir, path)) = self.folders.get(&event.wd).cloned() else {
                continue;
            };
            if event.mask.contains(AddWatchFlags::IN_IGNORED) {
                self.folders.remove(&event.wd);
                self.watched.remove(&(id, path));
                continue;
            }
            let folder = event.mask.contains(AddWatchFlags::IN_ISDIR);
            if event.mask.contains(AddWatchFlags::IN_CREATE) && !folder {
                // Written still: its IN_CLOSE_WRITE follows.
                continue;
            }
            if let (true, Some(name)) = (folder, event.name.as_ref().and_then(|name| name.to_str())) {
                let root: Option<String> = sqlx::query_scalar("SELECT root_uri FROM libraries WHERE id = $1")
                    .bind(id)
                    .fetch_optional(pool)
                    .await
                    .ok()
                    .flatten();
                if let Some(root) = root {
                    self.add(id, &root, &join(&dir, name));
                }
            }
            pending.insert((id, dir));
        }
        if overflow {
            let libraries: BTreeSet<Uuid> = self.watched.iter().map(|(id, _)| *id).collect();
            if let Err(error) = scans(pool, libraries).await {
                tracing::warn!(%error, "cannot scan the watched libraries after lost events");
            }
        }
    }
}

/// Queues a hint of each folder.
async fn hints(pool: &PgPool, folders: impl Iterator<Item = (Uuid, String)>) -> sqlx::Result<()> {
    let mut tx = pool.begin().await?;
    for (id, dir) in folders {
        hint(&mut tx, id, &[&dir]).await?;
    }
    tx.commit().await
}

/// Starts a scan of each library.
async fn scans(pool: &PgPool, libraries: BTreeSet<Uuid>) -> sqlx::Result<()> {
    let mut tx = pool.begin().await?;
    for id in libraries {
        super::scan(&mut tx, id).await?;
    }
    tx.commit().await
}

/// The kernel's `max_user_watches`, or its usual default.
fn kernel_limit() -> usize {
    let limit = std::fs::read_to_string("/proc/sys/fs/inotify/max_user_watches");
    limit.ok().and_then(|limit| limit.trim().parse().ok()).unwrap_or(8192)
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use serde_json::Value;

    use super::*;
    use crate::{
        config::Log,
        external::{RESCAN, SCAN, tests::instance, tests::jpeg, tests::write},
        ingest::INGEST,
        testing::Capture,
    };

    /// Each folder gets a watch up to the limit, the shallow ones first; the library counts the rest as polled and the
    /// log says so. A file written into a watched folder, dated 2100 or not, or into a new subfolder of one, is an
    /// asset within a minute; one in a polled folder waits for the hourly rescan.
    #[tokio::test]
    async fn a_file_dated_2100_shows_at_once_in_a_watched_folder_and_polled_ones_wait() {
        let at = instance(Value::Null).await;
        for path in ["a.jpg", "2024/05/b.jpg", "2025/c.jpg"] {
            write(&at.root, path, &jpeg());
        }
        at.scan().await;
        at.run(&[SCAN, INGEST]).await;
        let capture = Capture::default();
        let _logs = capture.set_default(&Log::default());
        let shutdown = CancellationToken::new();
        let watcher = tokio::spawn(watch(at.pool.clone(), Some(3), shutdown.clone()));
        let unwatched = "SELECT unwatched FROM libraries WHERE id = $1";
        while sqlx::query_scalar::<_, Option<i32>>(unwatched)
            .bind(at.library)
            .fetch_one(&at.pool)
            .await
            .unwrap()
            != Some(1)
        {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert!(capture.text().contains("the watches ran out"), "{}", capture.text());

        let started = std::time::Instant::now();
        write(&at.root, "2025/d.jpg", &jpeg());
        let year_2100 = std::time::UNIX_EPOCH + Duration::from_hours(1_139_568);
        std::fs::File::open(at.root.join("2025/d.jpg"))
            .unwrap()
            .set_modified(year_2100)
            .unwrap();
        write(&at.root, "2025/trip/e.jpg", &jpeg());
        write(&at.root, "2024/05/f.jpg", &jpeg());
        let assets = "SELECT count(*) FROM library_files WHERE library_id = $1 AND state = 'ingested'";
        let count = || {
            sqlx::query_scalar::<_, i64>(assets)
                .bind(at.library)
                .fetch_one(&at.pool)
        };
        // Workers run once the watcher has queued its hints, which it does a second after the last change.
        while count().await.unwrap() < 5 {
            assert!(started.elapsed() < Duration::from_secs(60), "visible within a minute");
            tokio::time::sleep(SETTLE * 3).await;
            at.run(&[SCAN, INGEST]).await;
        }
        assert_eq!(count().await.unwrap(), 5, "2024/05 is polled: {:?}", started.elapsed());

        sqlx::query("UPDATE library_scans SET started_at = now() - interval '61 minutes'")
            .execute(&at.pool)
            .await
            .unwrap();
        let mut conn = at.pool.acquire().await.unwrap();
        photolib_jobs::enqueue(&mut conn, &photolib_jobs::NewJob::new(RESCAN, b""))
            .await
            .unwrap();
        at.run(&[RESCAN, SCAN, INGEST]).await;
        assert_eq!(count().await.unwrap(), 6);
        shutdown.cancel();
        watcher.await.unwrap();
    }
}
