//! The servers and tools that tests start, which never outlive them (ADR-0113). Each runs in a process group of its
//! own that gets a signal when the test process dies (`PR_SET_PDEATHSIG`, set by util-linux's `setpriv`: the
//! workspace forbids the `unsafe` of `pre_exec`). A server's group is stopped on drop; a tool's is killed when it runs
//! out of time.
// Test support: a child that does not start, or a tool that hangs, fails the test that called it by panicking.
#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]

use std::{
    ffi::OsStr,
    io::{self, Read},
    net::{SocketAddr, TcpListener},
    ops::{Deref, DerefMut},
    os::unix::process::CommandExt,
    path::PathBuf,
    process::{Child, Command, Output, Stdio},
    sync::{
        Mutex, OnceLock,
        mpsc::{self, RecvTimeoutError},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

pub use nix::sys::signal::Signal;
use nix::{
    sys::signal::{kill, killpg},
    unistd::Pid,
};
use socket2::{Domain, Socket, Type};

/// How long a group has after its stop signal before SIGKILL, and then to die.
const GRACE: Duration = Duration::from_secs(5);
/// How often the clock of [`Running`] time looks at the time.
const TICK: Duration = Duration::from_millis(100);
/// The most [`Running`] time counts between two looks: a longer gap is time the process was stopped.
const GAP: Duration = Duration::from_secs(1);

/// Time against a limit: wall time, less what passes while this process is stopped (SIGSTOP), as the merge train
/// stops other runs for up to 25 minutes while it measures time. A thread looks at the time every 100 ms, and a gap of
/// over a second between two looks counts as one second, so the time of a call that never looks counts too.
#[derive(Clone, Copy)]
pub struct Running(Duration);

impl Running {
    /// Counts from now.
    pub fn start() -> Self {
        Self(counted())
    }

    /// The time counted so far.
    pub fn elapsed(self) -> Duration {
        counted().saturating_sub(self.0)
    }
}

/// The [`Running`] time of this process since it first asked.
fn counted() -> Duration {
    static CLOCK: OnceLock<Mutex<(Instant, Duration)>> = OnceLock::new();
    let clock = CLOCK.get_or_init(|| {
        thread::spawn(|| {
            loop {
                thread::sleep(TICK);
                counted();
            }
        });
        Mutex::new((Instant::now(), Duration::ZERO))
    });
    let mut clock = clock.lock().unwrap();
    let now = Instant::now();
    clock.1 = clock.1.saturating_add(now.duration_since(clock.0).min(GAP));
    clock.0 = now;
    clock.1
}

/// `future`'s output, as `tokio::time::timeout` gives it, or `None` once it has run for `limit` of [`Running`] time.
pub async fn within<F: Future>(limit: Duration, future: F) -> Option<F::Output> {
    let running = Running::start();
    let mut future = std::pin::pin!(future);
    loop {
        if let Ok(output) = tokio::time::timeout(TICK, &mut future).await {
            return Some(output);
        }
        if running.elapsed() >= limit {
            return None;
        }
    }
}

/// `program` in a process group of its own, which gets `death` when this process dies.
pub fn command(program: impl AsRef<OsStr>, death: Signal) -> Command {
    static SETPRIV: OnceLock<PathBuf> = OnceLock::new();
    let setpriv = SETPRIV.get_or_init(|| {
        let path = std::env::var_os("PATH").unwrap_or_default();
        let mut found = std::env::split_paths(&path).map(|dir| dir.join("setpriv"));
        found
            .find(|file| file.is_file())
            .expect("tests start their children with setpriv (util-linux), which is not on PATH")
    });
    let mut command = Command::new(setpriv);
    command
        .arg(format!("--pdeathsig={}", death.as_str()))
        .arg("--")
        .arg(program)
        .process_group(0);
    command
}

/// A tool: `program`, killed when this process dies.
pub fn tool(program: impl AsRef<OsStr>) -> Command {
    command(program, Signal::SIGKILL)
}

/// A running process group: on drop it gets its stop signal, then SIGKILL after a grace of 5 s.
pub struct Group {
    child: Child,
    stop: Signal,
    deadline: Option<(mpsc::Sender<()>, JoinHandle<bool>)>,
}

impl Group {
    /// Starts `command`, made by [`command`] with `stop`. `PR_SET_PDEATHSIG` fires when the thread that forked ends,
    /// so it forks on a thread that lives as long as this process.
    pub fn start(command: Command, stop: Signal) -> Self {
        type Fork = (Command, mpsc::SyncSender<io::Result<Child>>);
        static FORKER: OnceLock<mpsc::Sender<Fork>> = OnceLock::new();
        let forker = FORKER.get_or_init(|| {
            let (send, receive) = mpsc::channel::<Fork>();
            thread::spawn(move || {
                for (mut command, reply) in receive {
                    // The caller waits for the reply, unless it panicked meanwhile.
                    reply.send(command.spawn()).ok();
                }
            });
            send
        });
        let (reply, child) = mpsc::sync_channel(1);
        let program = format!("{command:?}");
        forker.send((command, reply)).unwrap();
        let child = child.recv().unwrap();
        Self::of(
            child.unwrap_or_else(|error| panic!("{program} did not start: {error}")),
            stop,
        )
    }

    const fn of(child: Child, stop: Signal) -> Self {
        Self {
            child,
            stop,
            deadline: None,
        }
    }

    /// Sends `signal` to the group's leader.
    pub fn signal(&self, signal: Signal) {
        // A leader that is gone has nothing to receive.
        kill(Pid::from_raw(self.child.id().cast_signed()), signal).ok();
    }

    /// Kills the group unless it is dropped within `limit` of [`Running`] time.
    pub fn deadline(&mut self, limit: Duration) {
        let (send, receive) = mpsc::channel();
        let group = self.child.id();
        let watch = thread::spawn(move || {
            let running = Running::start();
            while receive.recv_timeout(TICK) == Err(RecvTimeoutError::Timeout) {
                if running.elapsed() >= limit {
                    stop(group, Signal::SIGKILL);
                    return true;
                }
            }
            false
        });
        self.deadline = Some((send, watch));
    }

    /// Whether this group listens on TCP `port`; an error saying the address is in use when another process listens
    /// there too, as a child that sets `SO_REUSEPORT` (Caddy) can, so that [`on_fresh_ports`] starts it again.
    pub fn listens(&self, port: u16) -> Result<bool, String> {
        let suffix = format!(":{port:04X}");
        let tables =
            ["/proc/net/tcp", "/proc/net/tcp6"].map(|table| std::fs::read_to_string(table).unwrap_or_default());
        // local_address, st (0A: LISTEN) and inode of each socket
        let sockets: Vec<String> = (tables.iter().flat_map(|table| table.lines()))
            .map(|line| line.split_whitespace().collect::<Vec<_>>())
            .filter(|fields| {
                fields.get(1).is_some_and(|local| local.ends_with(&suffix)) && fields.get(3) == Some(&"0A")
            })
            .filter_map(|fields| Some(format!("socket:[{}]", fields.get(9)?)))
            .collect();
        let members = members(self.child.id()).into_iter();
        let links: Vec<PathBuf> = (members.flat_map(|pid| std::fs::read_dir(format!("/proc/{pid}/fd")).into_iter()))
            .flatten()
            .flatten()
            .filter_map(|fd| std::fs::read_link(fd.path()).ok())
            .collect();
        let ours = (sockets.iter())
            .filter(|socket| links.iter().any(|link| link.as_os_str() == socket.as_str()))
            .count();
        match ours {
            0 => Ok(false),
            ours if ours == sockets.len() => Ok(true),
            _ => Err(format!(
                "another process listens on port {port} too: address already in use"
            )),
        }
    }

    /// Whether the deadline passed and killed the group.
    fn expired(&mut self) -> bool {
        let deadline = self.deadline.take();
        deadline.is_some_and(|(send, watch)| {
            drop(send);
            watch.join().unwrap()
        })
    }
}

impl Deref for Group {
    type Target = Child;

    fn deref(&self) -> &Child {
        &self.child
    }
}

impl DerefMut for Group {
    fn deref_mut(&mut self) -> &mut Child {
        &mut self.child
    }
}

impl Drop for Group {
    fn drop(&mut self) {
        self.expired();
        let group = self.child.id();
        if !stop(group, self.stop) {
            stop(group, Signal::SIGKILL);
        }
        // Reaps the leader, which stop() saw die.
        self.child.wait().ok();
    }
}

/// Sends `signal` to `group` unless none of it is left; whether it is gone within the grace. The leader is reaped only
/// after this, so that its id cannot name another group meanwhile.
fn stop(group: u32, signal: Signal) -> bool {
    let started = Running::start();
    if !members(group).is_empty() {
        // Members that die meanwhile are what the loop below waits for.
        killpg(Pid::from_raw(group.cast_signed()), signal).ok();
    }
    while !members(group).is_empty() {
        if started.elapsed() > GRACE {
            return false;
        }
        thread::sleep(Duration::from_millis(10));
    }
    true
}

/// Runs `command`, made by [`tool`], to its end as [`Command::output`] does; panics when it takes longer than
/// `limit` of [`Running`] time, after killing its group.
pub fn output(command: &mut Command, limit: Duration) -> Output {
    let child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap_or_else(|error| panic!("{command:?} did not start: {error}"));
    let mut group = Group::of(child, Signal::SIGKILL);
    group.deadline(limit);
    let (mut stdout, mut stderr) = (group.stdout.take().unwrap(), group.stderr.take().unwrap());
    let said = thread::spawn(move || {
        // A pipe that breaks when the group is killed ends what it said.
        let mut bytes = vec![];
        stderr.read_to_end(&mut bytes).ok();
        bytes
    });
    let mut printed = vec![];
    stdout.read_to_end(&mut printed).ok();
    let said = said.join().unwrap();
    let status = group.wait().unwrap();
    assert!(
        !group.expired(),
        "{command:?} timed out after {limit:?}: {}",
        String::from_utf8_lossy(&said)
    );
    Output {
        status,
        stdout: printed,
        stderr: said,
    }
}

/// A port of 127.0.0.1 held for a child to bind: bound, never listening, with `SO_REUSEADDR`, so that no bind of port
/// 0 takes it until it is dropped, while a child that sets `SO_REUSEADDR` too (Go, nginx, Apache httpd, tokio) binds
/// it (photolib-design#501). Drop it once the child [`Group::listens`] on it.
pub struct Port {
    /// What the child is to bind.
    pub number: u16,
    _held: Socket,
}

/// A [`Port`] of its own; a child that is to bind it starts through [`on_fresh_ports`].
pub fn free_port() -> Port {
    let held = Socket::new(Domain::IPV4, Type::STREAM, None).unwrap();
    held.set_reuse_address(true).unwrap();
    held.bind(&SocketAddr::from(([127, 0, 0, 1], 0)).into()).unwrap();
    let number = held.local_addr().unwrap().as_socket().unwrap().port();
    Port { number, _held: held }
}

/// A listener on `port` of 127.0.0.1 that lets another listen there too (`SO_REUSEPORT`), as Caddy's do.
pub fn listen_beside(port: u16) -> TcpListener {
    let socket = Socket::new(Domain::IPV4, Type::STREAM, None).unwrap();
    socket.set_reuse_address(true).unwrap();
    socket.set_reuse_port(true).unwrap();
    socket.bind(&SocketAddr::from(([127, 0, 0, 1], port)).into()).unwrap();
    socket.listen(16).unwrap();
    socket.into()
}

/// What `start` started on ports it took from [`free_port`]. Another process may still bind one by its number, or
/// listen beside the child (photolib-design#501), so a start that fails saying so (`address already in use`, or musl's
/// `Address in use`) runs again on fresh ports, five times at most; any other failure panics with what `start`
/// returned.
pub fn on_fresh_ports<T>(mut start: impl FnMut() -> Result<T, String>) -> T {
    for _ in 1..5 {
        match start() {
            Ok(started) => return started,
            Err(said) if port_taken(&said) => eprintln!("a port was taken; on fresh ones: {said}"),
            Err(said) => panic!("{said}"),
        }
    }
    start().unwrap_or_else(|said| panic!("{said}"))
}

/// Whether a child's output says a port it was to bind was taken.
pub fn port_taken(said: &str) -> bool {
    let said = said.to_lowercase();
    said.contains("address already in use") || said.contains("address in use")
}

/// The live processes of process group `group`: its members but zombies.
pub fn members(group: u32) -> Vec<u32> {
    let group = group.to_string();
    let entries = std::fs::read_dir("/proc").unwrap();
    let live = entries.filter_map(|entry| {
        let pid: u32 = entry.ok()?.file_name().to_str()?.parse().ok()?;
        let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
        let fields: Vec<&str> = stat.rsplit_once(')')?.1.split_whitespace().collect();
        (!matches!(fields.first(), Some(&("Z" | "X"))) && fields.get(2) == Some(&group.as_str())).then_some(pid)
    });
    live.collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The members of `group` once there are `n` of them, or after 5 s.
    fn settled(group: u32, n: usize) -> Vec<u32> {
        let started = Running::start();
        while members(group).len() != n && started.elapsed() < Duration::from_secs(5) {
            thread::sleep(Duration::from_millis(10));
        }
        members(group)
    }

    #[test]
    fn a_dropped_group_stops_whole_and_is_killed_when_it_ignores_its_signal() {
        for (script, ignores) in [("sleep 600 & wait", false), ("trap '' TERM; sleep 600 & wait", true)] {
            let mut sh = command("sh", Signal::SIGTERM);
            sh.args(["-c", script]);
            // From a thread that ends at once, which the group outlives.
            let started = thread::spawn(move || Group::start(sh, Signal::SIGTERM));
            let group = started.join().unwrap();
            let id = group.id();
            assert_eq!(settled(id, 2).len(), 2, "{script}: sh and sleep");
            let stopping = Running::start();
            drop(group);
            assert_eq!(members(id), [], "{script}");
            assert_eq!(stopping.elapsed() >= GRACE, ignores, "{script}");
        }
    }

    #[test]
    fn a_tool_returns_its_output_or_fails_with_its_group_killed_when_it_hangs() {
        let done = output(
            tool("sh").args(["-c", "echo out; echo err >&2; exit 3"]),
            Duration::from_secs(10),
        );
        assert_eq!(
            (done.status.code(), &done.stdout[..], &done.stderr[..]),
            (Some(3), &b"out\n"[..], &b"err\n"[..])
        );

        let pid = tempfile::NamedTempFile::new().unwrap();
        let file = pid.path().to_owned();
        let (send, receive) = mpsc::channel();
        // Named after this test, which checks its panic: tools/lint/panics.py fails a test on any other thread's.
        let name = thread::current().name().unwrap().to_owned();
        let hung = thread::Builder::new().name(name).spawn(move || {
            let script = "echo $$ > \"$0\"; sleep 600 & wait";
            output(tool("sh").args(["-c", script]).arg(file), Duration::from_millis(500));
            send.send(()).unwrap();
        });
        hung.unwrap();
        let waiting = Running::start();
        let ended = loop {
            match receive.recv_timeout(TICK) {
                Err(RecvTimeoutError::Timeout) => assert!(waiting.elapsed() < Duration::from_secs(10)),
                ended => break ended,
            }
        };
        assert_eq!(
            ended,
            Err(RecvTimeoutError::Disconnected),
            "a hung tool panics within its limit"
        );
        let group = std::fs::read_to_string(pid.path()).unwrap();
        assert_eq!(members(group.trim().parse().unwrap()), []);
    }

    /// A limit over a call that blocks (a tool, a query, a whole test body) counts the call's time, less a second at
    /// most should a loaded machine starve the clock's thread once.
    #[test]
    fn running_time_counts_a_call_that_never_looks_at_it() {
        let running = Running::start();
        thread::sleep(Duration::from_secs(3));
        let counted = running.elapsed();
        assert!(counted >= Duration::from_secs(2), "{counted:?}");
    }

    #[tokio::test]
    async fn within_gives_the_output_or_none_once_its_limit_has_run() {
        assert_eq!(within(Duration::from_secs(5), async { 7 }).await, Some(7));
        let running = Running::start();
        assert_eq!(
            within(Duration::from_millis(500), std::future::pending::<()>()).await,
            None
        );
        let took = running.elapsed();
        assert!(
            took >= Duration::from_millis(500) && took < Duration::from_secs(5),
            "{took:?}"
        );
    }

    /// Set in the run of `a_tool_waits_for_its_go` that `a_limit_never_counts_the_time_its_test_was_stopped` starts.
    const STOPPED: &str = "PHOTOLIB_SPAWN_STOPPED";

    /// Run only as that child: a tool within a 5 s limit that writes its pid to the file `STOPPED` names, then waits
    /// for that file's `.go`; the stop that call waits through is no [`Running`] time either.
    #[test]
    fn a_tool_waits_for_its_go() {
        let Some(file) = std::env::var_os(STOPPED) else {
            return;
        };
        let script = "echo $$ > \"$0.pid\"; mv \"$0.pid\" \"$0\"; until [ -e \"$0.go\" ]; do sleep 0.1; done";
        let running = Running::start();
        let done = output(tool("sh").args(["-c", script]).arg(file), Duration::from_secs(5));
        assert!(done.status.success());
        assert!(running.elapsed() < Duration::from_secs(5), "{:?}", running.elapsed());
    }

    /// The merge train stops every process of other runs (SIGSTOP) for up to 25 minutes while it measures time: a
    /// test and its tool stopped for longer than the tool's limit go on where they were once continued.
    #[test]
    fn a_limit_never_counts_the_time_its_test_was_stopped() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("tool");
        let mut test = tool(std::env::current_exe().unwrap());
        test.args(["--exact", "tests::a_tool_waits_for_its_go"])
            .env(STOPPED, &file)
            .stdout(Stdio::piped());
        let mut test = Group::start(test, Signal::SIGKILL);
        test.deadline(Duration::from_secs(60));
        let started = Running::start();
        while !file.exists() && started.elapsed() < Duration::from_secs(30) {
            thread::sleep(Duration::from_millis(10));
        }
        let sh = Pid::from_raw(std::fs::read_to_string(&file).unwrap().trim().parse().unwrap());
        let run = [Pid::from_raw(test.id().cast_signed()), sh];
        let signal = |signal| run.iter().for_each(|&pid| kill(pid, signal).unwrap());
        signal(Signal::SIGSTOP);
        thread::sleep(Duration::from_secs(7));
        signal(Signal::SIGCONT);
        thread::sleep(Duration::from_millis(300));
        std::fs::write(dir.path().join("tool.go"), "").unwrap();
        let mut said = String::new();
        test.stdout.take().unwrap().read_to_string(&mut said).unwrap();
        assert!(test.wait().unwrap().success(), "{said}");
    }

    #[test]
    fn a_child_whose_port_was_taken_starts_again_on_a_fresh_one() {
        // Taken by a listener, or by one that lets the child listen beside it, as another Caddy does.
        for listener in [TcpListener::bind("127.0.0.1:0").unwrap(), listen_beside(0)] {
            let taken = listener.local_addr().unwrap().port();
            let mut tries = 0;
            let (group, port) = on_fresh_ports(|| {
                tries += 1;
                let fresh = (tries > 1).then(free_port);
                let port = fresh.as_ref().map_or(taken, |fresh| fresh.number);
                // As Caddy binds its ports.
                let bind = "import socket, sys, time; s = socket.socket(); \
                            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); \
                            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1); \
                            s.bind(('127.0.0.1', int(sys.argv[1]))); s.listen(); time.sleep(600)";
                let mut python = command("python3", Signal::SIGTERM);
                python.args(["-c", bind, &port.to_string()]).stderr(Stdio::piped());
                let mut group = Group::start(python, Signal::SIGTERM);
                while !group.listens(port)? {
                    if group.try_wait().unwrap().is_some() {
                        let mut said = String::new();
                        group.stderr.take().unwrap().read_to_string(&mut said).unwrap();
                        return Err(said);
                    }
                    thread::sleep(Duration::from_millis(10));
                }
                Ok((group, port))
            });
            assert_eq!((tries, port == taken), (2, false), "{taken}");
            assert_eq!(
                group.listens(taken),
                Ok(false),
                "the port this test holds is not the child's"
            );
        }
    }

    #[test]
    fn no_bind_of_port_0_takes_a_free_port_until_it_is_dropped() {
        let port = free_port();
        // A bind of port 0 that may pick only `port` (IP_LOCAL_PORT_RANGE, Linux 6.3).
        let probe = |port: u16| {
            let bind = "import socket, struct, sys; n = int(sys.argv[1]); s = socket.socket(); \
                        s.setsockopt(socket.IPPROTO_IP, 51, struct.pack('I', n | n << 16)); s.bind(('127.0.0.1', 0))";
            let bound = output(
                tool("python3").args(["-c", bind, &port.to_string()]),
                Duration::from_secs(60),
            );
            (
                bound.status.success(),
                String::from_utf8_lossy(&bound.stderr).into_owned(),
            )
        };
        let number = port.number;
        let (bound, said) = probe(number);
        assert!(
            !bound && port_taken(&said),
            "a bind of port 0 took the free port {number}: {said}"
        );
        drop(port);
        assert_eq!(probe(number), (true, String::new()), "{number} once dropped");
    }

    #[test]
    fn only_a_taken_port_is_tried_again_and_five_times_at_most() {
        for (said, tries) in [
            ("listen tcp 127.0.0.1:80: bind: address already in use", 5),
            ("IO error: Address in use (os error 98)", 5),
            ("no such file", 1),
        ] {
            let mut n = 0;
            let started = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                on_fresh_ports(|| {
                    n += 1;
                    Err::<(), _>(said.to_string())
                });
            }));
            assert!(started.is_err(), "{said}");
            assert_eq!(n, tries, "{said}");
        }
    }
}
