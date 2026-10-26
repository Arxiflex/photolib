//! ExifTool as a persistent sandboxed process: one per worker slot, recycled every 1,000 files.

use std::{ffi::OsString, os::unix::fs::symlink, path::PathBuf};

use serde_json::{Map, Value};

use crate::{Failure, Limits, Policy, Worker};

/// The whole command line. Each file is then named by one line on stdin: a random-named link, so that no string a
/// user controls (a file name, a person's name) ever reaches ExifTool's arguments.
const ARGS: &str = "-stay_open True -@ - -common_args -j -G1 -a -n -struct -api LargeFileSupport=1";

pub struct ExifTool {
    worker: Worker,
    scratch: PathBuf,
}

impl ExifTool {
    /// `exiftool` starts it: its path, or an interpreter and the script. It reads the files of `library` through
    /// links it finds in `scratch`.
    pub fn new(photolibd: PathBuf, exiftool: Vec<PathBuf>, library: PathBuf, scratch: PathBuf) -> Self {
        let mut read = vec![library];
        read.extend(exiftool.iter().filter_map(|part| part.parent()).map(PathBuf::from));
        let limits = Limits {
            memory: 1 << 30,
            wall: std::time::Duration::from_secs(30),
            file_size: 0,
            ..Limits::IMAGE
        };
        let tool = exiftool
            .into_iter()
            .map(OsString::from)
            .chain(ARGS.split(' ').map(OsString::from))
            .collect();
        let mut worker = Worker::new(
            photolibd,
            Policy {
                read,
                write: None,
                limits,
            },
            tool,
        );
        worker.max_jobs = 1000;
        ExifTool { worker, scratch }
    }

    /// ExifTool's JSON object for `file`.
    pub async fn dump(&mut self, file: &std::path::Path) -> Result<Map<String, Value>, Failure> {
        let target = std::path::absolute(file).map_err(|e| Failure::Transient(e.to_string()))?;
        // The extension helps ExifTool tell formats apart; it is kept only when it cannot be an option or a newline.
        let extension = file
            .extension()
            .and_then(|e| e.to_str())
            .filter(|e| e.len() <= 8 && e.bytes().all(|b| b.is_ascii_alphanumeric()))
            .map_or(String::new(), |e| format!(".{e}"));
        let link = tempfile::Builder::new()
            .suffix(&extension)
            .rand_bytes(16)
            .make_in(&self.scratch, |path| symlink(&target, path))
            .map_err(|e| {
                Failure::Transient(format!(
                    "cannot link {} into {}: {e}",
                    file.display(),
                    self.scratch.display()
                ))
            })?;
        let request = format!("{}\n-execute\n", link.path().display());
        parse(&self.worker.call(request.as_bytes(), |line| line == "{ready}\n").await?)
    }
}

fn parse(reply: &str) -> Result<Map<String, Value>, Failure> {
    let json = reply.strip_suffix("{ready}\n").unwrap_or(reply);
    if json.is_empty() {
        return Err(Failure::Unsupported("ExifTool read no metadata".into()));
    }
    let Ok([dump]) = serde_json::from_str::<[Map<String, Value>; 1]>(json) else {
        return Err(Failure::DecoderCrash("ExifTool gave a malformed answer".into()));
    };
    match dump.get("ExifTool:Error") {
        Some(error) => Err(Failure::Unsupported(error.as_str().unwrap_or("an error").into())),
        None => Ok(dump),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_exiftool_error_is_a_failure_not_a_dump() {
        let dump = parse("[{\"SourceFile\":\"a.jpg\",\"IFD0:Make\":\"Canon\"}]\n{ready}\n").unwrap();
        assert_eq!(dump["IFD0:Make"], "Canon");
        let denied = "[{\"SourceFile\":\"a.jpg\",\"ExifTool:Error\":\"Error opening file\"}]\n{ready}\n";
        assert_eq!(parse(denied), Err(Failure::Unsupported("Error opening file".into())));
        assert_eq!(
            parse("{ready}\n"),
            Err(Failure::Unsupported("ExifTool read no metadata".into()))
        );
        assert_eq!(
            parse("[{\n{ready}\n"),
            Err(Failure::DecoderCrash("ExifTool gave a malformed answer".into()))
        );
    }
}
