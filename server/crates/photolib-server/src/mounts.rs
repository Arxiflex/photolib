use std::{
    fs,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
};

#[derive(Debug, PartialEq, Eq)]
pub struct Mount {
    pub point: PathBuf,
    pub fstype: String,
    pub options: String,
}

impl Mount {
    /// NFS, SMB and FUSE give no usable locking, `fsync` or latency guarantees for a database or scratch space.
    pub fn is_unsafe_for_state(&self) -> bool {
        matches!(self.fstype.as_str(), "nfs" | "nfs4" | "cifs" | "smb3" | "smbfs") || self.fstype.starts_with("fuse")
    }
}

fn unescape(field: &str) -> String {
    let mut out = String::new();
    let mut rest = field;
    while let Some(at) = rest.find('\\') {
        out.push_str(&rest[..at]);
        let code = rest
            .get(at + 1..at + 4)
            .and_then(|digits| u8::from_str_radix(digits, 8).ok());
        match code {
            Some(byte) => out.push(char::from(byte)),
            None => out.push('\\'),
        }
        rest = &rest[at + if code.is_some() { 4 } else { 1 }..];
    }
    out + rest
}

fn parse_line(line: &str) -> Option<Mount> {
    let fields: Vec<&str> = line.split_whitespace().collect();
    let separator = fields.iter().position(|field| *field == "-")?;
    // The mount's own options, then the filesystem's (`barrier`, `data=`).
    let options = [*fields.get(5)?, fields.get(separator + 3).copied().unwrap_or_default()];
    Some(Mount {
        point: PathBuf::from(unescape(fields.get(4)?)),
        options: options.join(",").trim_end_matches(',').to_string(),
        fstype: (*fields.get(separator + 1)?).to_string(),
    })
}

/// The mount that holds `path` (symlinks resolved where it exists), from the text of `/proc/self/mountinfo`; the
/// longest mount point wins.
pub fn mount_of(mountinfo: &str, path: &Path) -> Option<Mount> {
    let path = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    mountinfo
        .lines()
        .filter_map(parse_line)
        .filter(|mount| path.starts_with(&mount.point))
        .max_by_key(|mount| mount.point.components().count())
}

/// Why `path` may not hold the database or the work directory, or `None` when it may (or cannot be told).
pub fn refusal(mountinfo: &str, path: &Path) -> Option<String> {
    let mount = mount_of(mountinfo, path).filter(Mount::is_unsafe_for_state)?;
    Some(format!(
        "{} is on a {} filesystem (mounted at {}, options {}); locking and fsync cannot be trusted there",
        path.display(),
        mount.fstype,
        mount.point.display(),
        mount.options,
    ))
}

/// Facts an administrator needs to fix a refused directory: who runs the process, who owns the path, and where it lives.
pub fn diagnostics(path: &Path) -> String {
    let process = fs::metadata("/proc/self").map_or("unknown".into(), |meta| format!("{}:{}", meta.uid(), meta.gid()));
    let owner = match fs::metadata(path) {
        Ok(meta) => format!(
            "owned by {}:{} (mode {:o})",
            meta.uid(),
            meta.gid(),
            meta.mode() & 0o7777
        ),
        Err(error) => format!("not readable: {error}"),
    };
    let mount = current_mountinfo()
        .and_then(|text| mount_of(&text, path))
        .map_or(String::new(), |mount| {
            format!(
                "; on {} mounted at {} ({})",
                mount.fstype,
                mount.point.display(),
                mount.options
            )
        });
    format!(
        "{}: the process runs as {process}, the path is {owner}{mount}",
        path.display()
    )
}

/// Refuses database and work directories on network or FUSE filesystems unless `allow` overrides it; every offender is reported.
pub fn check_state_dirs(dirs: &[(&str, PathBuf)], allow: bool, mountinfo: Option<&str>) -> Result<(), Vec<String>> {
    let Some(mountinfo) = mountinfo.filter(|_| !allow) else {
        return Ok(());
    };
    let errors: Vec<String> = dirs
        .iter()
        .filter_map(|(key, dir)| {
            refusal(mountinfo, dir).map(|why| {
                format!("{key}: {why}; move it to local storage, or set allow_network_fs: true to accept the risk")
            })
        })
        .collect();
    if errors.is_empty() { Ok(()) } else { Err(errors) }
}

pub fn current_mountinfo() -> Option<String> {
    fs::read_to_string("/proc/self/mountinfo").ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::assert_contains;

    const MOUNTINFO: &str = "\
22 1 8:1 / / rw,relatime shared:1 - ext4 /dev/sda1 rw
30 22 0:40 / /data rw,relatime shared:5 - nfs4 nas:/export rw,vers=4.2
31 30 0:41 / /data/fuse rw,nosuid - fuse.sshfs user@host:/ rw,user_id=0
32 22 0:42 / /mnt/my\\040share rw - cifs //nas/photos rw
33 22 0:43 / /mnt/ntfs rw - fuseblk /dev/sdb1 rw
34 22 0:44 / /srv/local rw - xfs /dev/sdc1 rw
";

    #[test]
    fn mount_lookup_uses_the_longest_whole_path_prefix() {
        for (path, expected) in [
            ("/home/user", "ext4"),
            ("/data/photos", "nfs4"),
            ("/data/fuse/deep/dir", "fuse.sshfs"),
            ("/srv/local/x", "xfs"),
            ("/data2/x", "ext4"),
            ("/data", "nfs4"),
        ] {
            assert_eq!(mount_of(MOUNTINFO, Path::new(path)).unwrap().fstype, expected, "{path}");
        }
    }

    #[test]
    fn escaped_spaces_in_mount_points_are_decoded() {
        let mount = mount_of(MOUNTINFO, Path::new("/mnt/my share/photos")).unwrap();
        assert_eq!(
            (mount.fstype.as_str(), mount.point.as_path()),
            ("cifs", Path::new("/mnt/my share"))
        );
    }

    #[test]
    fn network_and_fuse_filesystems_are_unsafe_and_local_ones_are_not() {
        for (path, expected) in [
            ("/data/x", true),
            ("/data/fuse/x", true),
            ("/mnt/my share/x", true),
            ("/mnt/ntfs/x", true),
            ("/home/x", false),
            ("/srv/local/x", false),
        ] {
            assert_eq!(
                mount_of(MOUNTINFO, Path::new(path)).unwrap().is_unsafe_for_state(),
                expected,
                "{path}"
            );
        }
    }

    #[test]
    fn a_refusal_names_the_path_the_filesystem_and_the_mount() {
        let message = refusal(MOUNTINFO, Path::new("/data/photos")).unwrap();
        assert_contains(&message, &["/data/photos", "nfs4", "mounted at /data", "rw,relatime"]);
        assert_eq!(refusal(MOUNTINFO, Path::new("/home/x")), None);
    }

    #[test]
    fn an_unreadable_mount_table_refuses_nothing() {
        assert_eq!(refusal("", Path::new("/data")), None);
    }

    #[test]
    fn diagnostics_state_who_runs_the_process_and_who_owns_the_path() {
        let dir = tempfile::tempdir().unwrap();
        let message = diagnostics(dir.path());
        let owner = fs::metadata(dir.path()).unwrap();
        assert!(
            message.contains(&format!("owned by {}:{}", owner.uid(), owner.gid())),
            "{message}"
        );
        assert!(message.contains("the process runs as"), "{message}");
        assert!(message.contains(&dir.path().display().to_string()), "{message}");
        assert!(diagnostics(Path::new("/nonexistent/x")).contains("No such file"));
    }

    #[test]
    fn state_directories_on_network_filesystems_are_refused_unless_overridden() {
        let dirs = [
            ("work_dir", PathBuf::from("/data/tmp")),
            ("database.data_dir", PathBuf::from("/mnt/ntfs/pg")),
            ("other", PathBuf::from("/home/x")),
        ];
        let errors = check_state_dirs(&dirs, false, Some(MOUNTINFO)).unwrap_err();
        assert_eq!(errors.len(), 2, "{errors:?}");
        assert!(
            errors[0].starts_with("work_dir: ") && errors[0].contains("nfs4") && errors[0].contains("allow_network_fs"),
            "{errors:?}"
        );
        assert!(
            errors[1].starts_with("database.data_dir: ") && errors[1].contains("fuseblk"),
            "{errors:?}"
        );
        assert!(check_state_dirs(&dirs, true, Some(MOUNTINFO)).is_ok());
    }

    #[test]
    fn an_unreadable_mount_table_does_not_block_startup() {
        let dirs = [("work_dir", PathBuf::from("/data/tmp"))];
        assert!(check_state_dirs(&dirs, false, None).is_ok());
    }
}
