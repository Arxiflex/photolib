//! The files an upload sends.

use std::{
    io,
    path::{Path, PathBuf},
};

use photolib_ignore::Rules;

/// A file to upload: its path, size and modification time in nanoseconds since the epoch.
pub(crate) struct File {
    pub path: PathBuf,
    pub size: u64,
    pub mtime: i128,
}

/// Extensions of the photos and videos a folder walk uploads, in lower case: those of the app's folder sources
/// (`folder_indexer.dart`).
const MEDIA: &str = "jpg jpeg png gif webp heic heif avif jxl bmp tif tiff dng cr2 cr3 nef arw orf rw2 raf srw pef \
    mp4 mov m4v avi mkv webm 3gp mts m2ts";

/// `root` itself if it is a file, else the photos and videos under it that `Rules` keep, in path order.
pub(crate) fn walk(root: &Path) -> io::Result<Vec<File>> {
    let meta = std::fs::metadata(root)?;
    if !meta.is_dir() {
        return Ok(vec![file(root.to_owned(), &meta)?]);
    }
    let rules = Rules::defaults(case_sensitive(root)?);
    let (mut files, mut pending) = (Vec::new(), vec![(String::new(), rules)]);
    while let Some((dir, above)) = pending.pop() {
        let at = root.join(&dir);
        let ignore = std::fs::read_to_string(at.join(".photolibignore")).unwrap_or_default();
        let rules = above.add(&dir, &ignore);
        let mut entries = std::fs::read_dir(&at)?.collect::<io::Result<Vec<_>>>()?;
        entries.sort_by_key(std::fs::DirEntry::file_name);
        let mut dirs = Vec::new();
        for entry in entries {
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = if dir.is_empty() {
                name.clone()
            } else {
                format!("{dir}/{name}")
            };
            let kind = entry.file_type()?;
            if rules.ignores(&path, kind.is_dir()) {
                continue;
            }
            let extension = name.rsplit_once('.').map(|(_, e)| e.to_lowercase());
            if kind.is_dir() {
                dirs.push(path);
            } else if kind.is_file() && extension.is_some_and(|e| MEDIA.split(' ').any(|m| m == e)) {
                files.push(file(entry.path(), &entry.metadata()?)?);
            }
        }
        pending.extend(dirs.into_iter().rev().map(|dir| (dir, rules.clone())));
    }
    Ok(files)
}

/// Whether the volume of the folder `root` tells names apart by case, probed without writing as the apps do
/// (`isCaseSensitive`): not when the first name in it that has a case is, in the other case, the same file. With no
/// such name, as the platform's file systems do by default.
fn case_sensitive(root: &Path) -> io::Result<bool> {
    #[cfg(unix)]
    for entry in std::fs::read_dir(root)? {
        use std::os::unix::fs::MetadataExt;
        let name = entry?.file_name().to_string_lossy().into_owned();
        let lower = name.to_lowercase();
        let other = if lower == name { name.to_uppercase() } else { lower };
        let id = |name: &str| std::fs::symlink_metadata(root.join(name)).map(|m| (m.dev(), m.ino()));
        if let (true, Ok(this)) = (other != name, id(&name)) {
            return Ok(id(&other).ok() != Some(this));
        }
    }
    Ok(!cfg!(any(windows, target_os = "macos")))
}

fn file(path: PathBuf, meta: &std::fs::Metadata) -> io::Result<File> {
    let mtime = meta.modified()?.duration_since(std::time::UNIX_EPOCH);
    Ok(File {
        path,
        size: meta.len(),
        mtime: mtime.map_or(0, |d| i128::try_from(d.as_nanos()).unwrap_or(i128::MAX)),
    })
}
