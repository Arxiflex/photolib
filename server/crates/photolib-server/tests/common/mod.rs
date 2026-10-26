//! What the test binaries share: the pinned FFmpeg and the fixture commands run with it.

use std::{
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use photolib_spawn::{output, tool};

/// How long a fixture's encode or probe may take: the slowest takes 10 s alone, 35 s on a machine loaded ninefold.
pub(crate) const FIXTURE: Duration = Duration::from_secs(300);

/// The pinned FFmpeg (`tools/video/ffmpeg.sh`), or the directory `TEST_FFMPEG` names.
pub(crate) fn tools() -> PathBuf {
    if let Some(dir) = std::env::var_os("TEST_FFMPEG") {
        return dir.into();
    }
    let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../tools/video/ffmpeg.sh");
    // It fetches FFmpeg when it is missing.
    let output = output(tool("bash").arg(&script), Duration::from_secs(600));
    assert!(
        output.status.success(),
        "the video tests need FFmpeg: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    PathBuf::from(String::from_utf8(output.stdout).unwrap().trim())
}

/// The pauses before each try again of what failed for want of a thread or process: the machine's limit is shared
/// with the suites running beside this one.
pub(crate) const AGAIN: [Duration; 4] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(4),
    Duration::from_secs(8),
];

/// Runs a fixture's `command`, made by `tool`, and returns its stdout; fails with its command line and stderr when it
/// fails or is not done within `limit`, rather than hanging the gate.
pub(crate) fn run(command: &mut Command, limit: Duration) -> Vec<u8> {
    let mut pauses = AGAIN.iter();
    loop {
        let done = output(command, limit);
        let said = String::from_utf8_lossy(&done.stderr);
        match pauses.next() {
            Some(pause) if !done.status.success() && said.contains("Resource temporarily unavailable") => {
                std::thread::sleep(*pause);
            }
            _ => {
                assert!(done.status.success(), "{command:?} {}: {said}", done.status);
                return done.stdout;
            }
        }
    }
}

pub(crate) fn ffmpeg(tools: &Path, args: &[&str]) {
    run(
        tool(tools.join("ffmpeg"))
            .args(["-nostdin", "-hide_banner", "-loglevel", "error", "-y"])
            .args(args),
        FIXTURE,
    );
}
