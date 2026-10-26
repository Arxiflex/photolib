pub mod child;
mod exiftool;
pub mod gainmap;
pub mod hdr;
pub mod heif;
pub mod probe;
mod raster;
pub mod render;
mod worker;

pub use exiftool::ExifTool;
pub use worker::{Worker, run};

use std::{
    ffi::OsString,
    os::unix::process::CommandExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use serde::{Deserialize, Serialize};

/// Why a child could not produce a result; the classes of the media pipeline's failure handling.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Failure {
    Unsupported(String),
    LimitExceeded(String),
    DecoderCrash(String),
    Timeout(String),
    Transient(String),
}

/// What a sandboxed child may touch.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Policy {
    /// Files and directories it may read: its input, or the library root of a pooled child.
    pub read: Vec<PathBuf>,
    /// A directory it may create and write files in but not read.
    pub write: Option<PathBuf>,
    pub limits: Limits,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Limits {
    /// Address space in bytes.
    pub memory: u64,
    /// CPU seconds over the child's life; a pooled child is recycled before it adds up.
    pub cpu_secs: u64,
    /// Wall clock per job, enforced by the parent.
    pub wall: Duration,
    /// Largest file the child may write, in bytes.
    pub file_size: u64,
    pub open_files: u64,
    /// Decoded pixels per still image, checked on the header before decoding.
    pub pixels: u64,
}

impl Limits {
    pub const IMAGE: Limits = Limits {
        memory: 2 << 30,
        cpu_secs: 600,
        wall: Duration::from_secs(180),
        file_size: 64 << 20,
        open_files: 256,
        pixels: 300_000_000,
    };
}

/// The command that starts `photolibd media-child`, which confines itself to `policy` and then runs `tool`, or the
/// built-in prober when `tool` is empty. The child gets no environment and its own process group.
pub fn command(photolibd: &Path, policy: &Policy, tool: &[OsString]) -> Command {
    let mut command = Command::new(photolibd);
    command
        .arg("media-child")
        .arg("--policy")
        .arg(serde_json::to_string(policy).expect("a policy serialises"))
        .arg("--")
        .args(tool)
        .env_clear()
        .process_group(0);
    command
}
