//! The parent side: starts a sandboxed child, talks to it line by line and survives whatever it does.

use std::{
    ffi::OsString,
    os::unix::process::ExitStatusExt,
    path::{Path, PathBuf},
    process::{ExitStatus, Stdio},
    time::{Duration, Instant},
};

use nix::{
    sys::signal::{Signal, killpg},
    unistd::Pid,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    process::{Child, ChildStdin, ChildStdout},
};

use crate::{
    Failure, Limits, Policy,
    child::{Hello, Sandbox},
    command,
    probe::Probe,
};

/// One sandboxed child at a time, restarted after a crash or a timeout and recycled after `max_jobs` jobs or
/// `max_age`. A failure costs the job that caused it, never the caller.
pub struct Worker {
    photolibd: PathBuf,
    policy: Policy,
    tool: Vec<OsString>,
    pub max_jobs: u32,
    pub max_age: Duration,
    /// The longest answer the child may give.
    pub max_reply: usize,
    running: Option<Running>,
}

struct Running {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    jobs: u32,
    started: Instant,
}

impl Running {
    /// The whole process group: whatever the tool started dies with it.
    fn kill(&self) {
        if let Some(pid) = self.child.id() {
            let _ = killpg(Pid::from_raw(pid as i32), Signal::SIGKILL);
        }
    }
}

impl Drop for Running {
    fn drop(&mut self) {
        self.kill();
    }
}

enum Broken {
    Gone,
    TooLarge,
}

impl Worker {
    /// `photolibd` is the binary that provides `media-child`; `tool` is the parser to run, none for the prober.
    pub fn new(photolibd: PathBuf, policy: Policy, tool: Vec<OsString>) -> Self {
        Worker {
            photolibd,
            policy,
            tool,
            max_jobs: 500,
            max_age: Duration::from_secs(600),
            max_reply: 1 << 20,
            running: None,
        }
    }

    /// The built-in prober for the files of one library.
    pub fn prober(photolibd: PathBuf, library: PathBuf) -> Self {
        let policy = Policy {
            read: vec![library],
            write: None,
            limits: Limits::IMAGE,
        };
        Worker::new(photolibd, policy, vec![])
    }

    /// Format and dimensions of `path`, or `limit_exceeded` above the pixel limit.
    pub async fn probe(&mut self, path: &Path) -> Result<Probe, Failure> {
        let request = serde_json::to_string(path).map_err(|e| Failure::Unsupported(e.to_string()))? + "\n";
        let reply = self.call(request.as_bytes(), |_| true).await?;
        serde_json::from_str(&reply).unwrap_or_else(|_| Err(Failure::DecoderCrash("a malformed answer".into())))
    }

    /// Sends `request` and returns the answer: the lines up to and including the first one `last` accepts.
    pub async fn call(&mut self, request: &[u8], last: impl Fn(&str) -> bool) -> Result<String, Failure> {
        if let Some(running) = &self.running
            && (running.jobs >= self.max_jobs || running.started.elapsed() >= self.max_age)
        {
            self.stop().await;
        }
        let wall = self.policy.limits.wall;
        let running = match &mut self.running {
            Some(running) => running,
            None => self.running.insert(self.spawn().await?),
        };
        let max_reply = self.max_reply;
        let exchange = async {
            running.stdin.write_all(request).await.map_err(|_| Broken::Gone)?;
            running.stdin.flush().await.map_err(|_| Broken::Gone)?;
            let mut reply = String::new();
            loop {
                let start = reply.len();
                let room = (max_reply + 1).saturating_sub(start) as u64;
                match (&mut running.stdout).take(room).read_line(&mut reply).await {
                    Ok(0) | Err(_) => return Err(Broken::Gone),
                    Ok(_) if reply.len() > max_reply => return Err(Broken::TooLarge),
                    Ok(_) if last(&reply[start..]) => return Ok(reply),
                    Ok(_) => {}
                }
            }
        };
        let outcome = tokio::time::timeout(wall, exchange).await;
        if let Ok(Ok(reply)) = outcome {
            running.jobs += 1;
            return Ok(reply);
        }
        let status = self.stop().await;
        Err(match outcome {
            Err(_) => Failure::Timeout(format!("no answer within {wall:?}")),
            Ok(Err(Broken::TooLarge)) => Failure::LimitExceeded(format!("an answer above {max_reply} bytes")),
            _ => status.map_or_else(|| Failure::DecoderCrash("lost".into()), died),
        })
    }

    async fn spawn(&self) -> Result<Running, Failure> {
        let mut child = tokio::process::Command::from(command(&self.photolibd, &self.policy, &self.tool))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| Failure::Transient(format!("cannot start {}: {e}", self.photolibd.display())))?;
        let (stdin, stdout) = (child.stdin.take().unwrap(), child.stdout.take().unwrap());
        let mut running = Running {
            child,
            stdin,
            stdout: BufReader::new(stdout),
            jobs: 0,
            started: Instant::now(),
        };
        greeted(&mut running.stdout, self.policy.limits.wall).await?;
        Ok(running)
    }

    async fn stop(&mut self) -> Option<ExitStatus> {
        let mut running = self.running.take()?;
        running.kill();
        running.child.wait().await.ok()
    }
}

/// Reads the child's first line, which says whether it is confined.
async fn greeted(stdout: &mut BufReader<ChildStdout>, wall: Duration) -> Result<(), Failure> {
    let mut hello = String::new();
    let _ = tokio::time::timeout(wall, stdout.read_line(&mut hello)).await;
    match serde_json::from_str::<Hello>(&hello).map(|hello| hello.sandbox) {
        Ok(Sandbox::Full) => Ok(()),
        Ok(Sandbox::Partial) => {
            tracing::warn!(
                "sandbox: partial; this kernel lacks Landlock features, so media children are less isolated"
            );
            Ok(())
        }
        Err(_) => Err(Failure::Transient(format!("the media child did not start: {hello:?}"))),
    }
}

/// The most a one-shot tool may print on stdout.
const MAX_PRINTED: usize = 1 << 20;

/// Runs `tool` once in a sandboxed child confined to `policy` and returns what it printed after its greeting, at most
/// 1 MiB. The whole process group is killed when the wall clock runs out; a tool that fails says why on stderr.
pub async fn run(photolibd: &Path, policy: &Policy, tool: &[OsString]) -> Result<Vec<u8>, Failure> {
    let mut child = tokio::process::Command::from(command(photolibd, policy, tool))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Failure::Transient(format!("cannot start {}: {e}", photolibd.display())))?;
    let group = Pid::from_raw(child.id().unwrap_or_default() as i32);
    let (mut stdout, mut stderr) = (
        BufReader::new(child.stdout.take().unwrap()),
        child.stderr.take().unwrap(),
    );
    let work = async {
        greeted(&mut stdout, policy.limits.wall).await?;
        let mut printed = vec![];
        let mut said = vec![];
        let mut limited = (&mut stdout).take(MAX_PRINTED as u64 + 1);
        let printing = async {
            match limited.read_to_end(&mut printed).await {
                Ok(n) if n > MAX_PRINTED => Err(Failure::LimitExceeded(format!("an answer above {MAX_PRINTED} bytes"))),
                _ => Ok(()),
            }
        };
        tokio::try_join!(printing, async {
            head(&mut stderr, &mut said).await;
            Ok(())
        })?;
        let status = child.wait().await.map_err(|e| Failure::Transient(e.to_string()))?;
        let words = String::from_utf8_lossy(&said).trim().to_owned();
        match (status.success(), status.signal()) {
            (true, _) => Ok(printed),
            // EAGAIN: the machine had no thread or process to spare, which says nothing about the file.
            (false, None) if words.contains("Resource temporarily unavailable") => Err(Failure::Transient(words)),
            (false, None) if !words.is_empty() => Err(Failure::DecoderCrash(words)),
            (false, _) => Err(died(status)),
        }
    };
    let outcome = tokio::time::timeout(policy.limits.wall, work).await;
    let _ = killpg(group, Signal::SIGKILL);
    outcome.unwrap_or_else(|_| Err(Failure::Timeout(format!("no result within {:?}", policy.limits.wall))))
}

/// Reads `from` to its end, keeping its first 4 KiB in `kept`: where a tool says what went wrong first.
async fn head(from: &mut (impl AsyncReadExt + Unpin), kept: &mut Vec<u8>) {
    let mut buffer = [0; 4096];
    while let Ok(n @ 1..) = from.read(&mut buffer).await {
        let room = buffer.len().saturating_sub(kept.len());
        kept.extend_from_slice(&buffer[..n.min(room)]);
    }
}

fn died(status: ExitStatus) -> Failure {
    match (status.signal(), status.code()) {
        (Some(signal), _) if signal == Signal::SIGXCPU as i32 => Failure::Timeout("the CPU limit ran out".into()),
        (Some(signal), _) => Failure::DecoderCrash(format!("killed by signal {signal}")),
        (None, code) => Failure::DecoderCrash(format!("exited with status {}", code.unwrap_or(-1))),
    }
}
