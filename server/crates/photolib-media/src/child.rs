//! The child side: `photolibd media-child` confines itself, announces the result and runs the untrusted parser.

use std::{
    error::Error,
    ffi::OsString,
    fs::File,
    io::{self, BufRead, Read, Write},
    os::unix::process::CommandExt,
    path::PathBuf,
    process::{Command, ExitCode},
};

use landlock::{
    ABI, Access, AccessFs, AccessNet, Ruleset, RulesetAttr, RulesetCreatedAttr, RulesetStatus, Scope,
    path_beneath_rules,
};
use nix::sys::resource::{Resource, setrlimit};
use seccompiler::{SeccompAction, SeccompFilter};
use serde::{Deserialize, Serialize};

use crate::{Failure, Limits, Policy, probe::probe, render};

/// What a tool needs to start: its loader, libraries and interpreter. Nothing here holds user data.
pub const SYSTEM: [&str; 5] = ["/usr", "/bin", "/lib", "/lib64", "/etc/ld.so.cache"];

/// The first line a child writes: whether every requested restriction is in force on this kernel.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Sandbox {
    Full,
    Partial,
}

#[derive(Serialize, Deserialize)]
pub struct Hello {
    pub sandbox: Sandbox,
}

/// Must run while the process has a single thread: the restrictions apply to the calling thread and its children.
pub fn main(policy: &str, tool: &[OsString]) -> ExitCode {
    match run(policy, tool) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("photolibd media-child: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run(policy: &str, tool: &[OsString]) -> Result<(), Box<dyn Error>> {
    let policy: Policy = serde_json::from_str(policy)?;
    rlimits(&policy.limits)?;
    let sandbox = landlock(&policy, tool.first())?;
    seccomp()?;
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "{}", serde_json::to_string(&Hello { sandbox })?)?;
    stdout.flush()?;
    match tool.split_first() {
        Some((program, args)) => Err(Command::new(program).args(args).exec().into()),
        None => serve(&policy),
    }
}

/// A request to the built-in tools: a path to probe, or an image to render.
#[derive(Deserialize)]
#[serde(untagged)]
enum Request {
    Probe(PathBuf),
    Render(render::Request),
}

/// The built-in tools: one JSON request per line in, one JSON `Result` per line out.
fn serve(policy: &Policy) -> Result<(), Box<dyn Error>> {
    let mut stdout = io::stdout().lock();
    for line in io::stdin().lock().lines() {
        let answer = match serde_json::from_str(&line?)? {
            Request::Probe(path) => {
                let mut head = Vec::new();
                let probed = File::open(&path)
                    .and_then(|file| file.take(1 << 20).read_to_end(&mut head))
                    .map_err(|e| Failure::Transient(format!("cannot read {}: {e}", path.display())))
                    .and_then(|_| probe(&head, policy.limits.pixels));
                serde_json::to_string(&probed)
            }
            Request::Render(request) => {
                let out = policy.write.as_deref().unwrap_or(std::path::Path::new("."));
                serde_json::to_string(&render::render(&request, out, &policy.limits))
            }
        };
        writeln!(stdout, "{}", answer?)?;
        stdout.flush()?;
    }
    Ok(())
}

fn rlimits(limits: &Limits) -> nix::Result<()> {
    setrlimit(Resource::RLIMIT_AS, limits.memory, limits.memory)?;
    // SIGXCPU at the soft limit, so that it reads as a timeout rather than a kill.
    setrlimit(Resource::RLIMIT_CPU, limits.cpu_secs, limits.cpu_secs + 1)?;
    setrlimit(Resource::RLIMIT_FSIZE, limits.file_size, limits.file_size)?;
    setrlimit(Resource::RLIMIT_NOFILE, limits.open_files, limits.open_files)?;
    // A core dump would write decoded photos to disk.
    setrlimit(Resource::RLIMIT_CORE, 0, 0)
}

/// Allows reading `policy.read`, writing (only) in `policy.write` and, for a tool, reading and executing the system
/// directories; denies every other file access, TCP and signals to processes outside the sandbox.
fn landlock(policy: &Policy, tool: Option<&OsString>) -> Result<Sandbox, landlock::RulesetError> {
    let abi = ABI::V6;
    let mut ruleset = Ruleset::default()
        .handle_access(AccessFs::from_all(abi))?
        .handle_access(AccessNet::from_all(abi))?
        .scope(Scope::from_all(abi))?
        .create()?
        .add_rules(path_beneath_rules(&policy.read, AccessFs::ReadFile | AccessFs::ReadDir))?
        .add_rules(path_beneath_rules(&policy.write, AccessFs::from_write(abi)))?;
    if let Some(tool) = tool {
        ruleset = ruleset
            .add_rules(path_beneath_rules(SYSTEM, AccessFs::from_read(abi)))?
            .add_rules(path_beneath_rules([tool], AccessFs::from_read(abi)))?;
    }
    Ok(match ruleset.restrict_self()?.ruleset {
        RulesetStatus::FullyEnforced => Sandbox::Full,
        _ => Sandbox::Partial,
    })
}

/// System calls a decoder never needs, refused with `EPERM`.
const DENIED: [i64; 24] = [
    libc::SYS_socket, // no network (and no local sockets)
    libc::SYS_ptrace,
    libc::SYS_process_vm_readv,
    libc::SYS_process_vm_writev,
    libc::SYS_setsid, // leaving the process group the parent kills
    libc::SYS_setpgid,
    libc::SYS_mount,
    libc::SYS_umount2,
    libc::SYS_pivot_root,
    libc::SYS_chroot,
    libc::SYS_unshare,
    libc::SYS_setns,
    libc::SYS_bpf,
    libc::SYS_perf_event_open,
    libc::SYS_userfaultfd,
    libc::SYS_io_uring_setup, // io_uring opens sockets and files without these system calls
    libc::SYS_keyctl,
    libc::SYS_add_key,
    libc::SYS_request_key,
    libc::SYS_init_module,
    libc::SYS_finit_module,
    libc::SYS_delete_module,
    libc::SYS_kexec_load,
    libc::SYS_open_by_handle_at,
];

fn seccomp() -> Result<(), Box<dyn Error>> {
    let filter = SeccompFilter::new(
        DENIED.into_iter().map(|call| (call, vec![])).collect(),
        SeccompAction::Allow,
        SeccompAction::Errno(libc::EPERM as u32),
        std::env::consts::ARCH.try_into()?,
    )?;
    let program: seccompiler::BpfProgram = filter.try_into()?;
    seccompiler::apply_filter(&program)?;
    Ok(())
}
