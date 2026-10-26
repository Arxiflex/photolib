//! What this client has sent to a library: one JSON line per change of a file's record, in
//! `<state>/<library>.jsonl`, the last line of a file winning (ADR-0065). A crash loses nothing the operating system
//! received; a power loss at most the last second, which costs uploading those files again.

use std::{
    collections::HashMap,
    fs::File,
    io::{self, BufRead, Seek, Write},
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};

use serde::{Deserialize, Serialize};

use crate::files;

/// A file as the last run left it.
#[derive(Clone, Serialize, Deserialize)]
pub struct Record {
    pub path: String,
    pub size: u64,
    pub mtime: i128,
    /// Its BLAKE3, lowercase hex, once read.
    pub blake3: Option<String>,
    /// Its upload's path on the server, once created.
    pub upload: Option<String>,
    /// Uploaded, verified and stored by the server.
    pub done: bool,
}

pub struct Journal {
    file: Arc<Mutex<File>>,
    records: Mutex<Records>,
}

/// Records by path, and the upload of each content uploaded.
#[derive(Default)]
struct Records(HashMap<String, Record>, HashMap<String, String>);

impl Records {
    fn insert(&mut self, record: Record) {
        if let (true, Some(hash), Some(upload)) = (record.done, &record.blake3, &record.upload) {
            self.1.insert(hash.clone(), upload.clone());
        }
        self.0.insert(record.path.clone(), record);
    }
}

impl Journal {
    /// Opens the journal at `path` for this process alone.
    pub fn open(path: &Path) -> io::Result<Journal> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut file = File::options().create(true).read(true).append(true).open(path)?;
        file.try_lock()
            .map_err(|_| io::Error::other(format!("{} is in use by another upload", path.display())))?;
        let mut records = Records::default();
        for line in io::BufReader::new(&file).split(b'\n') {
            // A line that does not parse was torn by a crash while it was written.
            if let Ok(record) = serde_json::from_slice(&line?) {
                records.insert(record);
            }
        }
        if file.seek(io::SeekFrom::End(0))? > 0 && !ends_in_newline(&file)? {
            file.write_all(b"\n")?;
        }
        let file = Arc::new(Mutex::new(file));
        let journal = Arc::downgrade(&file);
        std::thread::spawn(move || {
            while let Some(file) = {
                std::thread::sleep(Duration::from_secs(1));
                journal.upgrade()
            } {
                let _ = file.lock().map(|file| file.sync_data());
            }
        });
        Ok(Journal {
            file,
            records: Mutex::new(records),
        })
    }

    /// What the last run did with `file`, unless the file changed since.
    pub fn get(&self, file: &files::File) -> Option<Record> {
        let record = self.records().0.get(&*file.path.to_string_lossy()).cloned();
        record.filter(|r| r.size == file.size && r.mtime == file.mtime)
    }

    /// Whether an earlier run uploaded `file` as it is.
    pub fn done(&self, file: &files::File) -> bool {
        self.get(file).is_some_and(|r| r.done)
    }

    /// The upload of a content that was uploaded.
    pub fn uploaded(&self, hash: &str) -> Option<String> {
        self.records().1.get(hash).cloned()
    }

    pub fn put(&self, record: Record) -> io::Result<()> {
        let mut line = serde_json::to_vec(&record).expect("a record serializes");
        line.push(b'\n');
        let file = self.file.lock();
        file.expect("no thread panics holding the journal").write_all(&line)?;
        self.records().insert(record);
        Ok(())
    }

    pub fn sync(&self) -> io::Result<()> {
        let file = self.file.lock();
        file.expect("no thread panics holding the journal").sync_data()
    }

    fn records(&self) -> std::sync::MutexGuard<'_, Records> {
        self.records.lock().expect("no thread panics holding the records")
    }
}

impl Drop for Journal {
    /// Lets the next run in now, rather than when the thread that syncs it lets go of the file.
    fn drop(&mut self) {
        let _ = self.file.lock().map(|file| file.unlock());
    }
}

fn ends_in_newline(mut file: &File) -> io::Result<bool> {
    let mut last = [0];
    file.seek(io::SeekFrom::End(-1))?;
    io::Read::read_exact(&mut file, &mut last)?;
    Ok(last == *b"\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(path: &str, done: bool) -> Record {
        let (blake3, upload) = (Some(format!("{path}-hash")), Some(format!("upload/{path}")));
        let (size, mtime) = (1, 2);
        Record {
            path: path.into(),
            size,
            mtime,
            blake3,
            upload,
            done,
        }
    }

    /// A crash while a line was written leaves it torn: the journal skips it and goes on after it.
    #[test]
    fn a_torn_line_is_skipped_and_the_next_record_starts_a_line() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("library.jsonl");
        let mut line = serde_json::to_string(&record("a", true)).unwrap() + "\n";
        line += &serde_json::to_string(&record("b", true)).unwrap()[..20];
        std::fs::write(&path, line).unwrap();
        Journal::open(&path).unwrap().put(record("c", false)).unwrap();
        let journal = Journal::open(&path).unwrap();
        let found = |path: &str| journal.records().0.get(path).map(|r| r.done);
        assert_eq!([found("a"), found("b"), found("c")], [Some(true), None, Some(false)]);
        assert_eq!(journal.uploaded("a-hash").as_deref(), Some("upload/a"));
    }
}
