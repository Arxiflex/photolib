//! The `scan` job of one folder of an external library (photolib-design docs/07 §4, ADR-0093, ADR-0257), on a
//! `worker:io` role, in one transaction: the folder's new files recorded and queued for ingest, files that moved kept
//! with their rows and assets, files found again, and a job per subfolder. A scan's root job first checks that the
//! root is still the library's own, else the library goes offline and nothing changes; its last job hides what the
//! scan did not find, unless that is more than the guard allows unconfirmed. A hint lists one folder before other
//! work and only adds.

use std::{
    collections::{HashMap, HashSet},
    io::Read,
    sync::Arc,
};

use async_trait::async_trait;
use photolib_ignore::{Rules, rules_at};
use photolib_jobs::{Handler, Job, NewJob};
use photolib_storage::{
    Error, check_key,
    fs::{Entry, Identity},
};
use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use uuid::Uuid;

use super::{BATCH, Batch, HASH, HINT_PRIORITY, Libraries, Library, SCAN, batches, enqueue, join};
use crate::{guard::Dry, ingest::INGEST};

/// The guard's name for hiding what a scan did not find.
pub const HIDE: &str = "library.hide";
/// The job that starts the scans of libraries that are due.
pub const RESCAN: &str = "rescan";
/// How many of a root's names its fingerprint keeps.
const FINGERPRINT: usize = 64;
/// A folder's ignore rules, which it is read for and never recorded as one of its files.
const IGNORE_FILE: &str = ".photolibignore";
/// The most of an ignore file that is read.
const IGNORE_BYTES: u64 = 64 << 10;

/// The files of library `$1` that its scan `$2` did not find, as `f`: in no folder the scan listed, or not in the one
/// that held them, and neither found since the scan started nor under a folder it could not read.
const GONE: &str = "f.library_id = $1 AND f.missing_since IS NULL
    AND f.found_at < (SELECT started_at FROM library_scans WHERE id = $2)
    AND (f.unseen = $2 OR NOT EXISTS (SELECT FROM scan_dirs s WHERE s.scan_id = $2 AND s.dir = f.dir))
    AND NOT EXISTS (SELECT FROM scan_dirs s WHERE s.scan_id = $2 AND s.skipped
        AND starts_with(f.dir || '/', s.dir || '/'))";
/// A file's path from its folder and name, in SQL.
macro_rules! path {
    ($dir:literal, $name:literal) => {
        concat!(
            "CASE ",
            $dir,
            " WHEN '' THEN ",
            $name,
            " ELSE ",
            $dir,
            " || '/' || ",
            $name,
            " END"
        )
    };
}

/// One folder to list, of a scan or, without one, of a hint.
#[derive(Serialize, Deserialize)]
pub(crate) struct Folder {
    pub scan: Option<Uuid>,
    pub library: Uuid,
    pub dir: String,
    /// The ignore files of the folders above, from the root down (a hint reads them itself).
    #[serde(default)]
    pub ignores: Vec<(String, String)>,
    /// Whether the volume tells names apart by case; the first folder of a scan or hint finds out.
    #[serde(default)]
    pub case_sensitive: Option<bool>,
}

impl Folder {
    pub(crate) fn new(scan: Option<Uuid>, library: Uuid, dir: &str) -> Self {
        Self {
            scan,
            library,
            dir: dir.into(),
            ignores: vec![],
            case_sensitive: None,
        }
    }

    /// Queues its job: once per scan and folder; a hint each time and before other work.
    pub(crate) async fn enqueue(&self, tx: &mut PgConnection) -> sqlx::Result<Uuid> {
        let payload = serde_json::to_vec(self).map_err(|e| sqlx::Error::Encode(e.into()))?;
        let key = self.scan.map(|scan| format!("{SCAN}:{scan}:{}", self.dir));
        let job = NewJob {
            key: key.as_deref(),
            priority: if self.scan.is_some() { 0 } else { HINT_PRIORITY },
            ..NewJob::new(SCAN, &payload)
        };
        photolib_jobs::enqueue(tx, &job).await
    }
}

/// What listing a folder gave.
enum Listing {
    Read(Vec<Entry>),
    /// Gone since its parent was listed: what it held is missing.
    Gone,
    /// Unreadable, or hung past every retry: what lies under it stays as it was.
    Skipped,
}

/// A file the library knows, by folder and name.
struct Known {
    dir: String,
    name: String,
    identity: Identity,
    missing: bool,
}

/// The files of library `$1` that a filter appended to this selects.
const KNOWN: &str = "SELECT dir, name, dev, inode, size, mtime_ns, missing_since IS NOT NULL AS missing
    FROM library_files WHERE library_id = $1 AND";

impl sqlx::FromRow<'_, sqlx::postgres::PgRow> for Known {
    fn from_row(row: &sqlx::postgres::PgRow) -> sqlx::Result<Self> {
        use sqlx::Row;
        let number = |column: &str| row.try_get::<i64, _>(column);
        Ok(Self {
            dir: row.try_get("dir")?,
            name: row.try_get("name")?,
            identity: Identity {
                dev: number("dev")?.cast_unsigned(),
                inode: number("inode")?.cast_unsigned(),
                size: number("size")?.cast_unsigned(),
                mtime_ns: number("mtime_ns")?,
            },
            missing: row.try_get("missing")?,
        })
    }
}

/// A known file, `dir`/`name`, found again as `to` in the folder listed.
struct Move {
    dir: String,
    name: String,
    to: String,
    identity: Identity,
}

/// The `scan` job's handler.
pub struct Scanner(pub Arc<Libraries>);

#[async_trait]
impl Handler for Scanner {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        let mut at: Folder = serde_json::from_slice(&job.payload).map_err(|_| "a malformed payload")?;
        let library = match self.0.root(tx, at.library).await.map_err(|e| e.to_string())? {
            None => return Ok(()),
            Some(Ok(library)) => library,
            Some(Err(Error::Timeout(why))) if !job.last_attempt() => return Err(why),
            Some(Err(error)) => return offline(tx, at.library, at.scan, &error.to_string()).await,
        };
        let mut listing = match library.store.entries(&at.dir).await {
            Ok(entries) => Listing::Read(entries),
            Err(Error::Timeout(why)) if !job.last_attempt() => return Err(why),
            Err(error) if at.dir.is_empty() => return offline(tx, at.library, at.scan, &error.to_string()).await,
            Err(Error::NotFound(_)) => Listing::Gone,
            Err(error) => {
                tracing::warn!(library = %at.library, %error, "a folder cannot be listed: what it holds stays");
                Listing::Skipped
            }
        };
        let mut subfolders = 0;
        if let Listing::Read(entries) = &listing {
            if at.dir.is_empty() && at.scan.is_some() && !own_root(tx, at.library, entries).await? {
                return offline(tx, at.library, at.scan, "its root lacks every name it had").await;
            }
            if at.case_sensitive.is_none() {
                at.case_sensitive = Some(case_sensitive(&library, &at.dir, entries).await?);
            }
            match list(tx, &library, &at, entries).await? {
                Some(queued) => subfolders = queued,
                // Excluded since its parent was listed: as if gone.
                None => listing = Listing::Gone,
            }
        }
        let Some(scan) = at.scan else {
            return Ok(());
        };
        if !matches!(listing, Listing::Gone) {
            sqlx::query("INSERT INTO scan_dirs (scan_id, dir, skipped) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING")
                .bind(scan)
                .bind(&at.dir)
                .bind(matches!(listing, Listing::Skipped))
                .execute(&mut *tx)
                .await
                .map_err(|e| e.to_string())?;
        }
        let left: Option<i32> = sqlx::query_scalar(
            "UPDATE library_scans SET pending = pending - 1 + $2,
               finished_at = CASE WHEN pending - 1 + $2 = 0 THEN now() END
             WHERE id = $1 AND finished_at IS NULL RETURNING pending",
        )
        .bind(scan)
        .bind(i32::try_from(subfolders).map_err(|e| e.to_string())?)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
        if left == Some(0) {
            finish(tx, &library, at.library, scan).await?;
        }
        Ok(())
    }
}

/// Records what the folder `at` lists in `entries`, by the ignore rules in force there, and queues the subfolders to
/// list: every one in a scan, the new ones in a hint. Returns how many it queued, or `None` when the folder itself is
/// excluded.
async fn list(
    tx: &mut PgConnection,
    library: &Library,
    at: &Folder,
    entries: &[Entry],
) -> Result<Option<usize>, String> {
    let ignores = ignores(library, at, entries).await?;
    let texts: HashMap<&str, &str> = ignores
        .iter()
        .map(|(dir, text)| (dir.as_str(), text.as_str()))
        .collect();
    let read = |dir: &str| texts.get(dir).map_or_else(String::new, |text| (*text).to_owned());
    let Some(rules) = rules_at(&Rules::defaults(at.case_sensitive.unwrap_or(true)), &at.dir, read) else {
        return Ok(None);
    };
    let known: Vec<Known> = sqlx::query_as(&format!("{KNOWN} dir = $2"))
        .bind(at.library)
        .bind(&at.dir)
        .fetch_all(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    let mut found = Found::sort(at, &rules, &known, entries);
    library
        .limits
        .files
        .take(u64::try_from(found.new.len()).unwrap_or(u64::MAX).saturating_add(1))
        .await;
    let listed: HashSet<&str> = entries.iter().map(Entry::name).collect();
    let moves = moves(tx, library, at, &listed, &mut found.new).await?;
    let (mut ingest, mut hash) = moved(tx, at, &moves).await.map_err(|e| e.to_string())?;
    ingest.extend(insert(tx, at, &found.new).await.map_err(|e| e.to_string())?);
    update(tx, at, &found).await.map_err(|e| e.to_string())?;
    for (kind, names) in [(INGEST, &mut ingest), (HASH, &mut hash)] {
        names.sort_unstable();
        for names in batches(names, BATCH) {
            let batch = Batch {
                library: at.library,
                dir: at.dir.clone(),
                names: names.to_vec(),
            };
            enqueue(tx, kind, &batch, at.scan.is_none())
                .await
                .map_err(|e| e.to_string())?;
        }
    }
    subfolders(tx, at, found.dirs, &ignores)
        .await
        .map(Some)
        .map_err(|e| e.to_string())
}

/// What a folder's listing says of the files the library knows there.
#[derive(Default)]
struct Found {
    new: Vec<(String, Identity)>,
    back: Vec<String>,
    /// Same size and time, another device or inode: a share mounted again or elsewhere.
    renumbered: Vec<(String, Identity)>,
    /// Known, present, and not listed.
    unseen: Vec<String>,
    dirs: Vec<String>,
}

impl Found {
    /// Sorts the `entries` of the folder `at` that `rules` keep against the `known` files there.
    fn sort(at: &Folder, rules: &Rules, known: &[Known], entries: &[Entry]) -> Self {
        let known: HashMap<&str, &Known> = known.iter().map(|k| (k.name.as_str(), k)).collect();
        let (mut found, mut seen) = (Self::default(), HashSet::new());
        for entry in entries {
            let path = join(&at.dir, entry.name());
            if let Err(error) = check_key(&path) {
                tracing::warn!(library = %at.library, %error, "a file is skipped");
                continue;
            }
            if entry.name() == IGNORE_FILE || rules.ignores(&path, matches!(entry, Entry::Dir(_))) {
                continue;
            }
            let (name, identity) = match entry {
                Entry::Dir(_) => {
                    found.dirs.push(path);
                    continue;
                }
                Entry::File(name, identity) => (name, *identity),
            };
            let Some(file) = known.get(name.as_str()) else {
                found.new.push((name.clone(), identity));
                continue;
            };
            seen.insert(name.as_str());
            if file.missing {
                found.back.push(name.clone());
            }
            let content = |i: Identity| (i.size, i.mtime_ns);
            if content(file.identity) == content(identity) && !same_file(file.identity, identity) {
                found.renumbered.push((name.clone(), identity));
            }
        }
        found.unseen = (known.values())
            .filter(|file| !file.missing && !seen.contains(file.name.as_str()))
            .map(|file| file.name.clone())
            .collect();
        found
    }
}

/// Whether two identities are of the same file, whatever its content.
const fn same_file(a: Identity, b: Identity) -> bool {
    a.dev == b.dev && a.inode == b.inode
}

/// Queues the subfolders `dirs` of the folder `at` with the ignore files above them: every one in a scan, the ones
/// the library knows no file in for a hint. Returns how many it queued.
async fn subfolders(
    tx: &mut PgConnection,
    at: &Folder,
    mut dirs: Vec<String>,
    ignores: &[(String, String)],
) -> sqlx::Result<usize> {
    if at.scan.is_none() {
        let old: HashSet<String> =
            sqlx::query_scalar("SELECT DISTINCT dir FROM library_files WHERE library_id = $1 AND dir = ANY($2)")
                .bind(at.library)
                .bind(&dirs)
                .fetch_all(&mut *tx)
                .await?
                .into_iter()
                .collect();
        dirs.retain(|dir| !old.contains(dir));
    }
    for dir in &dirs {
        let folder = Folder {
            ignores: ignores.to_vec(),
            case_sensitive: at.case_sensitive,
            ..Folder::new(at.scan, at.library, dir)
        };
        folder.enqueue(tx).await?;
    }
    Ok(dirs.len())
}

/// The ignore files in force in the folder `at`, from the root down: those its payload holds, or for a hint that holds
/// none those it reads, then its own.
async fn ignores(library: &Library, at: &Folder, entries: &[Entry]) -> Result<Vec<(String, String)>, String> {
    let mut ignores = at.ignores.clone();
    if at.scan.is_none() && ignores.is_empty() {
        let above = at.dir.match_indices('/').filter_map(|(end, _)| at.dir.get(..end));
        for dir in std::iter::once("").chain(above).filter(|_| !at.dir.is_empty()) {
            ignores.extend(read_ignore(library, dir).await?.map(|text| (dir.to_owned(), text)));
        }
    }
    if entries
        .iter()
        .any(|entry| matches!(entry, Entry::File(name, _) if name == IGNORE_FILE))
    {
        ignores.extend(read_ignore(library, &at.dir).await?.map(|text| (at.dir.clone(), text)));
    }
    Ok(ignores)
}

/// The ignore file of the folder `dir`, if it has one that can be read.
async fn read_ignore(library: &Library, dir: &str) -> Result<Option<String>, String> {
    let path = join(dir, IGNORE_FILE);
    let read = library.store.with_file(&path, |file, _| {
        let mut text = vec![];
        file.take(IGNORE_BYTES)
            .read_to_end(&mut text)
            .map(|_| String::from_utf8_lossy(&text).into_owned())
    });
    match read.await {
        Ok(text) => Ok(text.ok()),
        Err(Error::Timeout(why)) => Err(why),
        Err(_) => Ok(None),
    }
}

/// The new files of the folder `at` that are known files moved, taken out of `new`: a file with the same device, inode,
/// size and time elsewhere is one that the folder `listed` lacks, or that is no longer at its path, or is there only
/// in another case (a case-insensitive volume); otherwise both paths hold it (a hard link) and it is new.
async fn moves(
    tx: &mut PgConnection,
    library: &Library,
    at: &Folder,
    listed: &HashSet<&str>,
    new: &mut Vec<(String, Identity)>,
) -> Result<Vec<Move>, String> {
    if new.is_empty() {
        return Ok(vec![]);
    }
    let inodes: Vec<i64> = new.iter().map(|(_, identity)| identity.inode.cast_signed()).collect();
    let known: Vec<Known> = sqlx::query_as(&format!("{KNOWN} inode = ANY($2)"))
        .bind(at.library)
        .bind(inodes)
        .fetch_all(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    let (mut moves, mut kept) = (Vec::<Move>::new(), vec![]);
    for (to, identity) in new.drain(..) {
        let path = join(&at.dir, &to);
        let taken = |k: &Known| moves.iter().any(|m| (&m.dir, &m.name) == (&k.dir, &k.name));
        let from = (known.iter()).find(|k| k.identity == identity && join(&k.dir, &k.name) != path && !taken(k));
        let moved = match from {
            None => false,
            Some(from) if from.dir == at.dir => !listed.contains(from.name.as_str()),
            Some(from) => {
                let old = join(&from.dir, &from.name);
                match library.store.with_file(&old, |_, now| now).await {
                    Ok(now) => !same_file(now, identity) || old.to_lowercase() == path.to_lowercase(),
                    Err(Error::NotFound(_)) => true,
                    Err(Error::Timeout(why)) => return Err(why),
                    Err(_) => false,
                }
            }
        };
        match from.filter(|_| moved) {
            Some(from) => moves.push(Move {
                dir: from.dir.clone(),
                name: from.name.clone(),
                to,
                identity,
            }),
            None => kept.push((to, identity)),
        }
    }
    *new = kept;
    Ok(moves)
}

/// Moves the rows of `moves` into the folder `at`, with their assets' files, and returns the names whose ingest is still
/// to come and those of ingested files not hashed yet.
async fn moved(tx: &mut PgConnection, at: &Folder, moves: &[Move]) -> sqlx::Result<(Vec<String>, Vec<String>)> {
    if moves.is_empty() {
        return Ok((vec![], vec![]));
    }
    let column = |f: fn(&Move) -> i64| moves.iter().map(f).collect::<Vec<_>>();
    let text = |f: fn(&Move) -> &str| moves.iter().map(f).collect::<Vec<_>>();
    let rows: Vec<(String, String, bool)> = sqlx::query_as(concat!(
        "WITH m AS (SELECT * FROM unnest($3::text[], $4::text[], $5::text[], $6::bigint[], $7::bigint[], $8::bigint[],
           $9::bigint[]) AS m (dir, name, to_name, dev, inode, size, mtime_ns)),
         moved AS (UPDATE library_files f SET dir = $2, name = m.to_name, dev = m.dev, inode = m.inode, size = m.size,
             mtime_ns = m.mtime_ns, unseen = NULL, missing_since = NULL, found_at = now()
           FROM m WHERE f.library_id = $1 AND f.dir = m.dir AND f.name = m.name
           RETURNING f.asset_id, f.state, f.name, ",
        path!("m.dir", "m.name"),
        " AS from_key, ",
        path!("$2", "m.to_name"),
        " AS key),
         files AS (UPDATE asset_files a SET key = moved.key, state = 'present' FROM moved
           WHERE a.asset_id = moved.asset_id AND a.storage = 'external' AND a.key = moved.from_key
           RETURNING a.asset_id, a.content_hash IS NOT NULL AND a.byte_offset IS NULL AS hashed),
         assets AS (UPDATE assets SET source_ref = moved.key FROM moved
           WHERE assets.id = moved.asset_id AND assets.source_ref = moved.from_key)
         SELECT moved.name, moved.state, coalesce(bool_or(files.hashed), false) FROM moved
         LEFT JOIN files ON files.asset_id = moved.asset_id GROUP BY moved.name, moved.state"
    ))
    .bind(at.library)
    .bind(&at.dir)
    .bind(text(|m| &m.dir))
    .bind(text(|m| &m.name))
    .bind(text(|m| &m.to))
    .bind(column(|m| m.identity.dev.cast_signed()))
    .bind(column(|m| m.identity.inode.cast_signed()))
    .bind(column(|m| m.identity.size.cast_signed()))
    .bind(column(|m| m.identity.mtime_ns))
    .fetch_all(&mut *tx)
    .await?;
    let (mut ingest, mut hash) = (vec![], vec![]);
    for (name, state, hashed) in rows {
        match (state.as_str(), hashed) {
            ("pending", _) => ingest.push(name),
            ("ingested", false) => hash.push(name),
            _ => {}
        }
    }
    Ok((ingest, hash))
}

/// Records the new files of the folder `at`, pending, and returns the names of those no other job recorded first.
async fn insert(tx: &mut PgConnection, at: &Folder, new: &[(String, Identity)]) -> sqlx::Result<Vec<String>> {
    if new.is_empty() {
        return Ok(vec![]);
    }
    let column = |f: fn(&Identity) -> i64| new.iter().map(|(_, identity)| f(identity)).collect::<Vec<_>>();
    sqlx::query_scalar(
        "INSERT INTO library_files (library_id, dir, name, dev, inode, size, mtime_ns)
         SELECT $1, $2, * FROM unnest($3::text[], $4::bigint[], $5::bigint[], $6::bigint[], $7::bigint[])
         ON CONFLICT DO NOTHING RETURNING name",
    )
    .bind(at.library)
    .bind(&at.dir)
    .bind(new.iter().map(|(name, _)| name).collect::<Vec<_>>())
    .bind(column(|i| i.dev.cast_signed()))
    .bind(column(|i| i.inode.cast_signed()))
    .bind(column(|i| i.size.cast_signed()))
    .bind(column(|i| i.mtime_ns))
    .fetch_all(&mut *tx)
    .await
}

/// Of the known files of the folder `at`: those `found` back are present again, the renumbered keep their new device
/// and inode, and those a scan did not see are marked `unseen` by it.
async fn update(tx: &mut PgConnection, at: &Folder, found: &Found) -> sqlx::Result<()> {
    let Found {
        back,
        renumbered,
        unseen,
        ..
    } = found;
    if !back.is_empty() {
        sqlx::query(concat!(
            "WITH back AS (UPDATE library_files SET missing_since = NULL WHERE library_id = $1 AND dir = $2
               AND name = ANY($3) RETURNING asset_id, ",
            path!("$2", "name"),
            " AS key)
             UPDATE asset_files a SET state = 'present' FROM back
             WHERE a.asset_id = back.asset_id AND a.storage = 'external' AND a.key = back.key"
        ))
        .bind(at.library)
        .bind(&at.dir)
        .bind(back)
        .execute(&mut *tx)
        .await?;
    }
    if !renumbered.is_empty() {
        let column = |f: fn(&Identity) -> i64| renumbered.iter().map(|(_, identity)| f(identity)).collect::<Vec<_>>();
        sqlx::query(
            "UPDATE library_files f SET dev = n.dev, inode = n.inode
             FROM unnest($3::text[], $4::bigint[], $5::bigint[]) AS n (name, dev, inode)
             WHERE f.library_id = $1 AND f.dir = $2 AND f.name = n.name",
        )
        .bind(at.library)
        .bind(&at.dir)
        .bind(renumbered.iter().map(|(name, _)| name).collect::<Vec<_>>())
        .bind(column(|i| i.dev.cast_signed()))
        .bind(column(|i| i.inode.cast_signed()))
        .execute(&mut *tx)
        .await?;
    }
    if let (Some(scan), false) = (at.scan, unseen.is_empty()) {
        sqlx::query("UPDATE library_files SET unseen = $3 WHERE library_id = $1 AND dir = $2 AND name = ANY($4)")
            .bind(at.library)
            .bind(&at.dir)
            .bind(scan)
            .bind(unseen)
            .execute(&mut *tx)
            .await?;
    }
    Ok(())
}

/// Whether a root that lists `entries` is library `id`'s own: it lists one of the names it had at the last scan, or
/// had none, and it is not empty while the library has files. An own root's names become the fingerprint and its
/// library is scanning; any other is a mount point without its share, or another share.
async fn own_root(tx: &mut PgConnection, id: Uuid, entries: &[Entry]) -> Result<bool, String> {
    let (fingerprint, has_files): (Option<Vec<String>>, bool) = sqlx::query_as(
        "SELECT fingerprint, EXISTS (SELECT FROM library_files WHERE library_id = $1) FROM libraries WHERE id = $1",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;
    let names: Vec<&str> = entries.iter().map(Entry::name).collect();
    let fingerprint = fingerprint.unwrap_or_default();
    let own = (fingerprint.is_empty() || fingerprint.iter().any(|name| names.contains(&name.as_str())))
        && (!names.is_empty() || !has_files);
    if own {
        sqlx::query("UPDATE libraries SET fingerprint = $2, state = 'scanning' WHERE id = $1")
            .bind(id)
            .bind(names.iter().take(FINGERPRINT).collect::<Vec<_>>())
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
    }
    Ok(own)
}

/// Whether the volume of the folder `dir` tells names apart by case, probed without writing as the apps and
/// `photolib upload` do: not when the first name in it that has a case is, in the other case, the same file or folder.
/// With no such name, as Linux's file systems do.
async fn case_sensitive(library: &Library, dir: &str, entries: &[Entry]) -> Result<bool, String> {
    let names: HashSet<&str> = entries.iter().map(Entry::name).collect();
    for entry in entries {
        let name = entry.name();
        let lower = name.to_lowercase();
        let other = if lower == name { name.to_uppercase() } else { lower };
        if other == name {
            continue;
        }
        if names.contains(other.as_str()) {
            return Ok(true);
        }
        let other = join(dir, &other);
        let same = match entry {
            Entry::File(_, identity) => {
                (library.store.with_file(&other, |_, other| other).await).map(|o| o == *identity)
            }
            Entry::Dir(_) => library.store.entries(&other).await.map(|_| true),
        };
        return match same {
            Err(error @ Error::Timeout(_)) => Err(error.to_string()),
            same => Ok(!same.unwrap_or(false)),
        };
    }
    Ok(true)
}

/// Marks library `id` offline, changing nothing else, and ends its `scan`.
async fn offline(tx: &mut PgConnection, id: Uuid, scan: Option<Uuid>, why: &str) -> Result<(), String> {
    tracing::warn!(library = %id, why, "an external library is offline: nothing in it changes");
    sqlx::query("UPDATE libraries SET state = 'offline' WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    sqlx::query("UPDATE library_scans SET pending = 0, finished_at = now() WHERE id = $1 AND finished_at IS NULL")
        .bind(scan)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Ends `scan` of library `id`: what it did not find turns missing, unless that is more than the guard allows, when
/// it waits for an administrator's confirmation; a root lost meanwhile puts the library offline instead.
async fn finish(tx: &mut PgConnection, library: &Library, id: Uuid, scan: Uuid) -> Result<(), String> {
    let own = match library.store.entries("").await {
        Ok(entries) => own_root(tx, id, &entries).await?,
        Err(_) => false,
    };
    if !own {
        return offline(tx, id, None, "its root was lost during the scan").await;
    }
    let dry = gone(tx, id, scan).await.map_err(|e| e.to_string())?;
    let held = !dry.plausible();
    if held {
        let (count, total) = (dry.count, dry.total);
        tracing::warn!(library = %id, count, total, "a scan would hide more than the guard allows: it waits for an administrator");
    } else {
        hide(tx, id, scan).await.map_err(|e| e.to_string())?;
    }
    sqlx::query("UPDATE library_scans SET missing = $2, held = $3 WHERE id = $1")
        .bind(scan)
        .bind(i32::try_from(dry.count).unwrap_or(i32::MAX))
        .bind(held)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    sqlx::query("UPDATE libraries SET state = 'online' WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    sqlx::query("DELETE FROM scan_dirs WHERE scan_id IN (SELECT id FROM library_scans WHERE library_id = $1 AND (id <> $2 OR NOT $3))")
        .bind(id)
        .bind(scan)
        .bind(held)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// What hiding the files that `scan` of library `id` did not find would change: their assets, of the assets present.
async fn gone(tx: &mut PgConnection, id: Uuid, scan: Uuid) -> sqlx::Result<Dry> {
    let (count, total): (i64, i64) = sqlx::query_as(&format!(
        "SELECT (SELECT count(DISTINCT f.asset_id) FROM library_files f WHERE {GONE}),
           (SELECT count(DISTINCT asset_id) FROM library_files WHERE library_id = $1 AND missing_since IS NULL)"
    ))
    .bind(id)
    .bind(scan)
    .fetch_one(&mut *tx)
    .await?;
    Ok(Dry::new(HIDE, id, scan, count, total))
}

/// Marks the files that `scan` of library `id` did not find missing, and their assets' files.
async fn hide(tx: &mut PgConnection, id: Uuid, scan: Uuid) -> sqlx::Result<()> {
    sqlx::query(&format!(
        concat!(
            "WITH gone AS (UPDATE library_files f SET missing_since = now() WHERE {} RETURNING f.asset_id, ",
            path!("f.dir", "f.name"),
            " AS key)
             UPDATE asset_files a SET state = 'missing' FROM gone
             WHERE a.asset_id = gone.asset_id AND a.storage = 'external' AND a.key = gone.key"
        ),
        GONE
    ))
    .bind(id)
    .bind(scan)
    .execute(&mut *tx)
    .await
    .map(drop)
}

/// Hides what the last scan of library `id` held back for confirmation, if `token` is its dry run's or it is no longer
/// more than the guard allows: `Ok` with how many assets it hid, else `Err` with the dry run to confirm; `None` when
/// no scan waits.
pub(crate) async fn confirm(tx: &mut PgConnection, id: Uuid, token: &str) -> sqlx::Result<Option<Result<i64, Dry>>> {
    let Some(scan) = held(tx, id).await? else {
        return Ok(None);
    };
    let dry = gone(tx, id, scan).await?;
    if !dry.allows(token) {
        return Ok(Some(Err(dry)));
    }
    hide(tx, id, scan).await?;
    for statement in [
        "UPDATE library_scans SET held = false WHERE id = $1",
        "DELETE FROM scan_dirs WHERE scan_id = $1",
    ] {
        sqlx::query(statement).bind(scan).execute(&mut *tx).await?;
    }
    Ok(Some(Ok(dry.count)))
}

/// The last scan of library `id` if it waits for a confirmation.
async fn held(tx: &mut PgConnection, id: Uuid) -> sqlx::Result<Option<Uuid>> {
    sqlx::query_scalar(
        "SELECT id FROM library_scans WHERE library_id = $1 AND held
           AND started_at = (SELECT max(started_at) FROM library_scans WHERE library_id = $1)",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
}

/// Queues a hint of each of the folders `dirs` of library `id`, so that what is new in them shows before other work.
pub(crate) async fn hint(tx: &mut PgConnection, id: Uuid, dirs: &[&str]) -> sqlx::Result<()> {
    for dir in dirs {
        Folder::new(None, id, dir).enqueue(tx).await?;
    }
    Ok(())
}

/// The `rescan` job, scheduled every 15 minutes: starts a scan of each external library that is offline or has folders
/// no watch covers (a network file system, past the watch limit, or with no watcher) an hour after its last, and of
/// every other a day after, so that offline libraries come back by themselves.
pub struct Rescan;

#[async_trait]
impl Handler for Rescan {
    async fn run(&self, _job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        let due: Vec<Uuid> = sqlx::query_scalar(
            "SELECT l.id FROM libraries l WHERE l.kind = 'external' AND NOT EXISTS (SELECT FROM library_scans s
               WHERE s.library_id = l.id AND (s.finished_at IS NULL OR s.started_at > now()
                 - CASE WHEN l.unwatched = 0 AND l.state <> 'offline' THEN interval '1 day' ELSE interval '1 hour' END))
             ORDER BY l.id",
        )
        .fetch_all(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
        for id in due {
            super::scan(tx, id).await.map_err(|e| e.to_string())?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;
    use crate::external::tests::{Instance, instance, jpeg, write};

    const WHOLE: &[&str] = &[SCAN, INGEST];

    impl Instance {
        /// Every row that the library's assets are made of, as text: assets, their files, versions, album items and
        /// faces; and the library's files.
        async fn rows(&self) -> (String, String) {
            sqlx::query_as(
                "SELECT concat_ws(' | ',
                   (SELECT string_agg(a::text, ',' ORDER BY a.id) FROM assets a WHERE a.library_id = $1),
                   (SELECT string_agg(f::text, ',' ORDER BY f.id) FROM asset_files f),
                   (SELECT string_agg(v::text, ',' ORDER BY v.id) FROM versions v),
                   (SELECT string_agg(i::text, ',' ORDER BY i.id) FROM album_items i),
                   (SELECT string_agg(f::text, ',' ORDER BY f.id) FROM faces f)),
                   (SELECT string_agg(l::text, ',' ORDER BY l.dir, l.name) FROM library_files l)",
            )
            .bind(self.library)
            .fetch_one(&self.pool)
            .await
            .unwrap()
        }

        /// Puts every asset in an album, gives each a face and an edit.
        async fn organise(&self) {
            sqlx::raw_sql(&format!(
                "INSERT INTO albums (id, owner_id, title) VALUES ('{album}', '{owner}', 'Trip');
                 INSERT INTO album_items (id, album_id, kind, asset_id)
                   SELECT gen_random_uuid(), '{album}', 'asset', id FROM assets;
                 INSERT INTO faces (id, asset_id, bbox, model_id) SELECT gen_random_uuid(), id, '{{0,0,1,1}}', 'm'
                   FROM assets;
                 INSERT INTO versions (id, asset_id, kind, parent_id)
                   SELECT gen_random_uuid(), id, 'edit', current_version_id FROM assets",
                album = Uuid::now_v7(),
                owner = self.owner
            ))
            .execute(&self.pool)
            .await
            .unwrap();
        }

        /// The library's state, and the last scan's count of missing assets and whether it waits.
        async fn state(&self) -> (String, Option<i32>, bool) {
            sqlx::query_as(
                "SELECT l.state, s.missing, s.held FROM libraries l
                 JOIN library_scans s ON s.library_id = l.id WHERE l.id = $1 ORDER BY s.started_at DESC LIMIT 1",
            )
            .bind(self.library)
            .fetch_one(&self.pool)
            .await
            .unwrap()
        }

        /// The asset of each file, by path, and whether its file is missing.
        async fn files_assets(&self) -> Vec<(String, Option<Uuid>, bool)> {
            sqlx::query_as(
                "SELECT CASE dir WHEN '' THEN name ELSE dir || '/' || name END, asset_id, missing_since IS NOT NULL
                 FROM library_files WHERE library_id = $1 ORDER BY 1",
            )
            .bind(self.library)
            .fetch_all(&self.pool)
            .await
            .unwrap()
        }

        /// How many jobs of `kind` were queued.
        async fn jobs(&self, kind: &str) -> i64 {
            sqlx::query_scalar("SELECT count(*) FROM jobs WHERE type = $1")
                .bind(kind)
                .fetch_one(&self.pool)
                .await
                .unwrap()
        }

        async fn rescan(&self) {
            assert!(self.scan().await.is_some());
            self.run(WHOLE).await;
        }
    }

    /// An unmounted share leaves an empty mount point, none, or another share's files in its place: the library goes
    /// offline and nothing else changes, not one asset, file, version, album item or face; mounted again, it is
    /// online and whole.
    #[tokio::test]
    async fn unmounting_the_share_changes_nothing_but_the_library_state() {
        let at = instance(Value::Null).await;
        for path in ["a.jpg", "2024/b.jpg", "2024/05/c.jpg"] {
            write(&at.root, path, &jpeg());
        }
        at.rescan().await;
        at.organise().await;
        let (before, ingested) = (at.rows().await, at.jobs(INGEST).await);
        let away = at.root.with_extension("away");
        for unmounted in ["an empty mount point", "no mount point", "another share"] {
            std::fs::rename(&at.root, &away).unwrap();
            match unmounted {
                "an empty mount point" => std::fs::create_dir(&at.root).unwrap(),
                "another share" => write(&at.root, "x.jpg", &jpeg()),
                _ => {}
            }
            at.rescan().await;
            assert_eq!(at.state().await.0, "offline", "{unmounted}");
            assert_eq!(at.rows().await, before, "{unmounted}");
            assert_eq!(at.jobs(INGEST).await, ingested, "{unmounted}");
            if at.root.exists() {
                std::fs::remove_dir_all(&at.root).unwrap();
            }
            std::fs::rename(&away, &at.root).unwrap();
        }
        // Mounted again, the hourly rescan of an offline library brings it back, though every folder is watched.
        sqlx::raw_sql(
            "UPDATE libraries SET unwatched = 0; UPDATE library_scans SET started_at = now() - interval '61 min'",
        )
        .execute(&at.pool)
        .await
        .unwrap();
        let mut conn = at.pool.acquire().await.unwrap();
        photolib_jobs::enqueue(&mut conn, &NewJob::new(RESCAN, b""))
            .await
            .unwrap();
        at.run(&[RESCAN, SCAN, INGEST]).await;
        assert_eq!(at.state().await, ("online".into(), Some(0), false));
        assert_eq!(at.rows().await, before);
    }

    /// A scan that would hide more than 5 % of the library's assets hides nothing and waits; its dry run's token, and
    /// only that, hides them. A later scan within the guard hides at once, and a file found again is back.
    #[tokio::test]
    async fn a_scan_that_would_hide_more_than_five_percent_waits_for_its_token() {
        let at = instance(Value::Null).await;
        for n in 0..40 {
            write(&at.root, &format!("d{}/f{n:02}.jpg", n / 10), &jpeg());
        }
        at.rescan().await;
        let before = at.files_assets().await;
        let remove = |path: &str| std::fs::remove_file(at.root.join(path)).unwrap();
        for path in ["d0/f00.jpg", "d0/f01.jpg", "d1/f10.jpg"] {
            remove(path);
        }
        at.rescan().await;
        assert_eq!(at.state().await, ("online".into(), Some(3), true), "3 of 40 is 7.5 %");
        assert_eq!(at.files_assets().await, before, "nothing hidden yet");
        let mut tx = at.pool.begin().await.unwrap();
        let Some(Err(dry)) = confirm(&mut tx, at.library, "").await.unwrap() else {
            panic!("a confirmation without its token");
        };
        assert_eq!((dry.count, dry.total), (3, 40));
        assert!(matches!(
            confirm(&mut tx, at.library, "0123").await.unwrap(),
            Some(Err(_))
        ));
        assert!(matches!(
            confirm(&mut tx, at.library, &dry.token).await.unwrap(),
            Some(Ok(3))
        ));
        assert!(
            confirm(&mut tx, at.library, &dry.token).await.unwrap().is_none(),
            "nothing waits any more"
        );
        tx.commit().await.unwrap();
        let missing = |files: Vec<(String, Option<Uuid>, bool)>| -> Vec<String> {
            files.into_iter().filter(|f| f.2).map(|f| f.0).collect()
        };
        assert_eq!(
            missing(at.files_assets().await),
            ["d0/f00.jpg", "d0/f01.jpg", "d1/f10.jpg"]
        );
        let gone: i64 = sqlx::query_scalar("SELECT count(*) FROM asset_files WHERE state = 'missing'")
            .fetch_one(&at.pool)
            .await
            .unwrap();
        assert_eq!(gone, 3);

        remove("d2/f20.jpg");
        at.rescan().await;
        assert_eq!(
            at.state().await,
            ("online".into(), Some(1), false),
            "1 of 37 is within the guard"
        );
        std::fs::remove_dir_all(at.root.join("d3")).unwrap();
        write(&at.root, "d0/f00.jpg", &jpeg());
        at.rescan().await;
        assert_eq!(at.state().await, ("online".into(), Some(10), true), "a folder of 10");
        let files = at.files_assets().await;
        assert_eq!(
            missing(files.clone()),
            ["d0/f01.jpg", "d1/f10.jpg", "d2/f20.jpg"],
            "f00 is back"
        );
        let assets = |files: &[(String, Option<Uuid>, bool)]| files.iter().map(|f| f.1).collect::<Vec<_>>();
        assert_eq!(assets(&files), assets(&before), "the same assets");
        assert_eq!(at.jobs(INGEST).await, 4, "nothing read again");
    }

    /// Files renamed, in case only or not, moved to another folder, or moved with their folder keep their rows and
    /// assets, and so their album items, faces and edits: nothing is read, hashed or hidden again. A hard link is a
    /// file of its own.
    #[tokio::test]
    async fn moved_files_keep_their_assets() {
        let at = instance(Value::Null).await;
        for path in ["a.jpg", "b.jpg", "2024/c.jpg", "2024/d.jpg", "old/e.jpg"] {
            write(&at.root, path, &jpeg());
        }
        at.rescan().await;
        at.run(&[HASH]).await;
        at.organise().await;
        let asset = |files: &[(String, Option<Uuid>, bool)], path: &str| {
            files.iter().find(|f| f.0 == path).and_then(|f| f.1).unwrap()
        };
        let before = at.files_assets().await;
        let jobs = (at.jobs(INGEST).await, at.jobs(HASH).await);
        let root = |path: &str| at.root.join(path);
        std::fs::rename(root("a.jpg"), root("A.JPG")).unwrap();
        std::fs::create_dir(root("2025")).unwrap();
        std::fs::rename(root("b.jpg"), root("2025/b2.jpg")).unwrap();
        std::fs::rename(root("2024/c.jpg"), root("c.jpg")).unwrap();
        std::fs::rename(root("old"), root("new")).unwrap();
        std::fs::hard_link(root("2024/d.jpg"), root("d-link.jpg")).unwrap();
        at.rescan().await;
        at.run(&[HASH]).await;

        let after = at.files_assets().await;
        let paths: Vec<&str> = after.iter().map(|f| f.0.as_str()).collect();
        assert_eq!(
            paths,
            ["2024/d.jpg", "2025/b2.jpg", "A.JPG", "c.jpg", "d-link.jpg", "new/e.jpg"]
        );
        for (from, to) in [
            ("a.jpg", "A.JPG"),
            ("b.jpg", "2025/b2.jpg"),
            ("2024/c.jpg", "c.jpg"),
            ("old/e.jpg", "new/e.jpg"),
            ("2024/d.jpg", "2024/d.jpg"),
        ] {
            assert_eq!(asset(&after, to), asset(&before, from), "{from} → {to}");
        }
        assert!(after.iter().all(|f| !f.2), "nothing missing");
        assert_eq!(
            (at.jobs(INGEST).await, at.jobs(HASH).await),
            (jobs.0 + 1, jobs.1 + 1),
            "only the link is read"
        );
        let keys: Vec<(String, Option<String>, i64, i64)> = sqlx::query_as(
            "SELECT f.key, a.source_ref, (SELECT count(*) FROM album_items i WHERE i.asset_id = a.id),
               (SELECT count(*) FROM faces x WHERE x.asset_id = a.id)
             FROM assets a JOIN asset_files f ON f.asset_id = a.id AND f.role = 'original' AND f.state = 'present'
               AND f.content_hash IS NOT NULL ORDER BY 1",
        )
        .fetch_all(&at.pool)
        .await
        .unwrap();
        let kept = |key: &str, items| (key.to_string(), Some(key.to_string()), items, items);
        assert_eq!(
            keys,
            [
                kept("2024/d.jpg", 1),
                kept("2025/b2.jpg", 1),
                kept("A.JPG", 1),
                kept("c.jpg", 1),
                kept("d-link.jpg", 0),
                kept("new/e.jpg", 1)
            ]
        );
    }

    /// An exclusion added to a `.photolibignore` hides what it matches at the next scan, reading nothing; removed, it
    /// brings the same assets back. The defaults never take a NAS's thumbnails in.
    #[tokio::test]
    async fn an_exclusion_applies_without_reading_anything_again() {
        let at = instance(Value::Null).await;
        for n in 0..60 {
            write(&at.root, &format!("keep/{n:02}.jpg"), &jpeg());
        }
        for path in [
            "drafts/x.jpg",
            "drafts/deeper/y.jpg",
            "2024/z.tmp.jpg",
            "@eaDir/a.jpg/SYNOPHOTO_THUMB_S.jpg",
        ] {
            write(&at.root, path, &jpeg());
        }
        at.rescan().await;
        let before = at.files_assets().await;
        assert_eq!(before.len(), 63, "no thumbnail of the NAS");
        let ingested = at.jobs(INGEST).await;
        write(&at.root, IGNORE_FILE, b"drafts/\n*.TMP.jpg\n");
        at.rescan().await;
        let hidden: Vec<String> = at
            .files_assets()
            .await
            .into_iter()
            .filter(|f| f.2)
            .map(|f| f.0)
            .collect();
        assert_eq!(hidden, ["drafts/deeper/y.jpg", "drafts/x.jpg"], "matched in exact case");
        write(&at.root, IGNORE_FILE, b"drafts/\n*.tmp.jpg\n");
        at.rescan().await;
        let hidden: Vec<String> = at
            .files_assets()
            .await
            .into_iter()
            .filter(|f| f.2)
            .map(|f| f.0)
            .collect();
        assert_eq!(hidden, ["2024/z.tmp.jpg", "drafts/deeper/y.jpg", "drafts/x.jpg"]);
        std::fs::remove_file(at.root.join(IGNORE_FILE)).unwrap();
        at.rescan().await;
        assert_eq!(at.files_assets().await, before, "the same assets back");
        assert_eq!(at.jobs(INGEST).await, ingested, "nothing read again");
    }

    /// A corrupt, empty or vanished file, or a folder that cannot be read, never stops a scan: each file is recorded
    /// with its outcome, what lies in an unreadable folder stays as it was, and the scan ends.
    #[tokio::test]
    async fn one_bad_file_or_folder_never_stops_a_scan() {
        use std::os::unix::fs::PermissionsExt;

        let at = instance(Value::Null).await;
        let jpeg = jpeg();
        write(&at.root, "a.jpg", &jpeg);
        write(&at.root, "bad/truncated.jpg", &jpeg[..200]);
        write(&at.root, "bad/empty.jpg", b"");
        write(&at.root, "bad/noise.jpg", &[0x5a; 4096]);
        write(&at.root, "locked/x.jpg", &jpeg);
        write(&at.root, "z/b.jpg", &jpeg);
        for n in 0..30 {
            write(&at.root, &format!("keep/{n:02}.jpg"), &jpeg);
        }
        at.rescan().await;
        let locked = at.root.join("locked");
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o000)).unwrap();
        // Whoever may read anything (root) lists it anyway.
        let unreadable = std::fs::read_dir(&locked).is_err();
        std::fs::remove_file(at.root.join("z/b.jpg")).unwrap();
        write(&at.root, "c.jpg", &jpeg);
        at.rescan().await;
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o755)).unwrap();
        let files = at.files().await;
        let state = |path: &str| files.iter().find(|f| f.0 == path).map(|f| f.1.as_str());
        assert_eq!(
            (state("a.jpg"), state("c.jpg"), state("locked/x.jpg")),
            (Some("ingested"), Some("ingested"), Some("ingested"))
        );
        for path in ["bad/truncated.jpg", "bad/empty.jpg", "bad/noise.jpg"] {
            assert!(
                matches!(state(path), Some("ingested" | "unsupported" | "failed")),
                "{path}: {files:?}"
            );
        }
        let missing: Vec<String> = at
            .files_assets()
            .await
            .into_iter()
            .filter(|f| f.2)
            .map(|f| f.0)
            .collect();
        assert_eq!(
            missing,
            ["z/b.jpg"],
            "the locked folder's file stays (unreadable: {unreadable})"
        );
        assert_eq!(at.state().await, ("online".into(), Some(1), false));
    }

    /// A hint lists its folder before other work and only adds: a new file, or one in a new subfolder, is an asset
    /// at once, a deleted one stays until a scan; a hint into an excluded folder finds nothing.
    #[tokio::test]
    async fn a_hint_adds_what_is_new_in_its_folder_first() {
        let at = instance(Value::Null).await;
        write(&at.root, "2024/a.jpg", &jpeg());
        write(&at.root, IGNORE_FILE, b"private/\n");
        at.rescan().await;
        write(&at.root, "2024/b.jpg", &jpeg());
        write(&at.root, "2024/trip/c.jpg", &jpeg());
        write(&at.root, "private/d.jpg", &jpeg());
        std::fs::remove_file(at.root.join("2024/a.jpg")).unwrap();
        let mut tx = at.pool.begin().await.unwrap();
        hint(&mut tx, at.library, &["2024", "private"]).await.unwrap();
        tx.commit().await.unwrap();
        let queued = "SELECT priority FROM jobs WHERE status = 'queued' AND type = $1 ORDER BY id";
        let priorities: Vec<i16> = sqlx::query_scalar(queued).bind(SCAN).fetch_all(&at.pool).await.unwrap();
        assert_eq!(priorities, [HINT_PRIORITY, HINT_PRIORITY]);
        at.run(WHOLE).await;
        let files: Vec<(String, bool)> = (at.files_assets().await.into_iter())
            .map(|f| (f.0, f.1.is_some() && !f.2))
            .collect();
        let file = |path: &str| (path.to_string(), true);
        assert_eq!(files, [file("2024/a.jpg"), file("2024/b.jpg"), file("2024/trip/c.jpg")]);
        let ingests = "SELECT priority FROM jobs WHERE type = $1 ORDER BY id";
        let priorities: Vec<i16> = sqlx::query_scalar(ingests)
            .bind(INGEST)
            .fetch_all(&at.pool)
            .await
            .unwrap();
        assert_eq!(priorities, [0, HINT_PRIORITY, HINT_PRIORITY]);
    }

    /// A library relocated to its share mounted elsewhere, where each file has another device and inode but the same
    /// size and time, keeps every asset, album item, face and edit: nothing is read or hashed again, and each file
    /// takes its new identity, which its pending hash job reads.
    #[tokio::test]
    async fn a_relocated_library_keeps_everything_and_reads_nothing_again() {
        let at = instance(Value::Null).await;
        for path in ["a.jpg", "2024/b.jpg", "2024/Trip/c.jpg"] {
            write(&at.root, path, &jpeg());
        }
        at.rescan().await;
        at.organise().await;
        let (assets, files) = at.rows().await;
        let jobs = (at.jobs(INGEST).await, at.jobs(HASH).await);
        let moved = at.root.with_extension("moved");
        for path in ["a.jpg", "2024/b.jpg", "2024/Trip/c.jpg"] {
            write(&moved, path, &jpeg());
            let time = std::fs::metadata(at.root.join(path)).unwrap().modified().unwrap();
            std::fs::File::options()
                .write(true)
                .open(moved.join(path))
                .unwrap()
                .set_modified(time)
                .unwrap();
        }
        std::fs::remove_dir_all(&at.root).unwrap();
        sqlx::query("UPDATE libraries SET root_uri = $2 WHERE id = $1")
            .bind(at.library)
            .bind(moved.to_str().unwrap())
            .execute(&at.pool)
            .await
            .unwrap();
        at.rescan().await;
        assert_eq!(at.state().await, ("online".into(), Some(0), false));
        let (assets_now, files_now) = at.rows().await;
        assert_eq!(assets_now, assets, "every asset, file, edit, album item and face");
        assert_ne!(files_now, files, "new identities");
        assert_eq!((at.jobs(INGEST).await, at.jobs(HASH).await), jobs, "nothing read again");
        at.run(&[HASH]).await;
        let hashed: i64 = sqlx::query_scalar("SELECT count(*) FROM assets WHERE content_hash IS NOT NULL")
            .fetch_one(&at.pool)
            .await
            .unwrap();
        assert_eq!(hashed, 3);
    }
}
