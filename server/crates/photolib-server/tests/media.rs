//! The sandboxed media children as a worker sees them: what a hostile decoder can and cannot do.

use std::{
    ffi::OsString,
    path::{Path, PathBuf},
    process::Output,
    time::Duration,
};

use photolib_media::{
    ExifTool, Failure, Limits, Policy, Worker, command,
    probe::{Format, Probe},
    run,
};
use photolib_spawn::Running;

const PHOTOLIBD: &str = env!("CARGO_BIN_EXE_photolibd");

/// `script` run by `shell` outside the sandbox.
fn outside(shell: &str, script: &str) -> Output {
    let limit = Duration::from_secs(60);
    photolib_spawn::output(photolib_spawn::tool(shell).args(["-c", script]), limit)
}

fn scratch() -> tempfile::TempDir {
    tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap()
}

fn policy(read: &[&Path]) -> Policy {
    Policy {
        read: read.iter().map(PathBuf::from).collect(),
        write: None,
        limits: Limits::IMAGE,
    }
}

/// Runs `tool` in a sandboxed child; returns the child's sandbox announcement and the rest of its output.
fn sandboxed(policy: &Policy, tool: &[&str]) -> (String, Output) {
    let tool: Vec<OsString> = tool.iter().map(OsString::from).collect();
    let mut output = command(Path::new(PHOTOLIBD), policy, &tool).output().unwrap();
    let stdout = String::from_utf8(output.stdout).unwrap();
    let (hello, rest) = stdout.split_once('\n').unwrap_or((&stdout, ""));
    let hello = hello.to_owned();
    output.stdout = rest.as_bytes().to_vec();
    (hello, output)
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

#[test]
fn a_tool_in_the_sandbox_reads_its_input() {
    let library = scratch();
    let photo = library.path().join("photo.jpg");
    std::fs::write(&photo, "pixels").unwrap();
    let (hello, output) = sandboxed(&policy(&[library.path()]), &["/bin/cat", photo.to_str().unwrap()]);
    assert!(
        [r#"{"sandbox":"full"}"#, r#"{"sandbox":"partial"}"#].contains(&hello.as_str()),
        "{hello:?} {}",
        text(&output.stderr)
    );
    assert_eq!(text(&output.stdout), "pixels");
    assert!(output.status.success());
}

#[test]
fn a_tool_in_the_sandbox_cannot_read_outside_its_input() {
    let (library, elsewhere) = (scratch(), scratch());
    let secret = elsewhere.path().join("secret.jpg");
    std::fs::write(&secret, "another user's photo").unwrap();
    let parent_environment = format!("/proc/{}/environ", std::process::id());
    let outside = [secret.to_str().unwrap(), "/etc/passwd", &parent_environment];
    for path in outside {
        assert!(std::fs::read(path).is_ok(), "{path} is readable outside the sandbox");
        let (_, output) = sandboxed(&policy(&[library.path()]), &["/bin/cat", path]);
        assert!(output.stdout.is_empty(), "{path}: {}", text(&output.stdout));
        assert!(
            text(&output.stderr).contains("Permission denied"),
            "{path}: {}",
            text(&output.stderr)
        );
    }
}

#[test]
fn a_tool_in_the_sandbox_cannot_open_network_sockets() {
    let tcp = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let udp = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
    for (protocol, port) in [
        ("tcp", tcp.local_addr().unwrap().port()),
        ("udp", udp.local_addr().unwrap().port()),
    ] {
        let script = format!("exec 3<>/dev/{protocol}/127.0.0.1/{port} && echo connected");
        let outside = outside("/bin/bash", &script);
        assert_eq!(
            text(&outside.stdout),
            "connected\n",
            "{protocol} works outside the sandbox"
        );
        let (_, inside) = sandboxed(&policy(&[]), &["/bin/bash", "-c", &script]);
        assert!(inside.stdout.is_empty(), "{protocol}: {}", text(&inside.stdout));
        assert!(!inside.status.success());
        assert!(
            text(&inside.stderr).contains("not permitted"),
            "{protocol}: {}",
            text(&inside.stderr)
        );
    }
}

#[test]
fn a_tool_in_the_sandbox_writes_only_to_its_output_directory() {
    let (library, out) = (scratch(), scratch());
    let mut policy = policy(&[library.path()]);
    policy.write = Some(out.path().to_owned());
    let script = "echo rendition > \"$1/thumb.webp\" && echo written; cat \"$1/thumb.webp\"; echo x > \"$2/photo.jpg\"";
    let (_, output) = sandboxed(
        &policy,
        &[
            "/bin/sh",
            "-c",
            script,
            "sh",
            out.path().to_str().unwrap(),
            library.path().to_str().unwrap(),
        ],
    );
    assert_eq!(text(&output.stdout), "written\n", "{}", text(&output.stderr));
    assert_eq!(
        std::fs::read_to_string(out.path().join("thumb.webp")).unwrap(),
        "rendition\n"
    );
    assert_eq!(
        text(&output.stderr).matches("Permission denied").count(),
        2,
        "{}",
        text(&output.stderr)
    );
    assert!(!library.path().join("photo.jpg").exists());
}

#[test]
fn resource_limits_stop_a_runaway_tool() {
    use std::os::unix::process::ExitStatusExt;
    let out = scratch();
    let mut policy = policy(&[]);
    policy.write = Some(out.path().to_owned());
    let grow = ["/bin/sh", "-c", "a=$(yes | head -c 134217728); echo survived"];
    assert_eq!(
        text(&sandboxed(&policy, &grow).1.stdout),
        "survived\n",
        "128 MiB fit in the image limit"
    );
    policy.limits.memory = 64 << 20;
    let (_, output) = sandboxed(&policy, &grow);
    assert!(output.stdout.is_empty() && !output.status.success(), "{output:?}");

    policy.limits.file_size = 1 << 20;
    let big = out.path().join("big");
    let (_, output) = sandboxed(
        &policy,
        &[
            "/bin/sh",
            "-c",
            "yes | head -c 2097152 > \"$1\"",
            "sh",
            big.to_str().unwrap(),
        ],
    );
    assert!(!output.status.success());
    assert_eq!(std::fs::metadata(&big).unwrap().len(), 1 << 20);

    policy.limits.cpu_secs = 1;
    let (_, output) = sandboxed(&policy, &["/bin/sh", "-c", "while :; do :; done"]);
    assert_eq!(output.status.signal(), Some(24), "SIGXCPU: {output:?}");
}

#[test]
fn a_tool_in_the_sandbox_cannot_signal_the_server() {
    let script = format!("kill -0 {} && echo signalled", std::process::id());
    let outside = outside("/bin/sh", &script);
    assert_eq!(text(&outside.stdout), "signalled\n");
    let (hello, inside) = sandboxed(&policy(&[]), &["/bin/sh", "-c", &script]);
    // Kernels before 6.12 cannot scope signals; the child says so and the worker warns.
    if hello == r#"{"sandbox":"full"}"# {
        assert!(inside.stdout.is_empty(), "{}", text(&inside.stdout));
        assert!(
            text(&inside.stderr).contains("not permitted"),
            "{}",
            text(&inside.stderr)
        );
    } else {
        assert_eq!(hello, r#"{"sandbox":"partial"}"#);
    }
}

/// The image limits, with a wall clock that fails a broken test quickly.
const QUICK: Limits = Limits {
    wall: Duration::from_secs(10),
    ..Limits::IMAGE
};

/// A stand-in for a C decoder: answers each line, and misbehaves on request.
fn decoder(limits: Limits) -> Worker {
    let script = r#"while read -r line; do case $line in
        crash) kill -SEGV $$;;
        hang) sleep 1000 & sleep 1000;;
        flood) yes | tr -d '\n';;
        spin) while :; do :; done;;
        *) echo "$line from $$";;
    esac; done"#;
    let policy = Policy {
        read: vec![],
        write: None,
        limits,
    };
    Worker::new(
        PHOTOLIBD.into(),
        policy,
        ["/bin/sh", "-c", script].map(OsString::from).to_vec(),
    )
}

async fn ask(worker: &mut Worker, line: &str) -> Result<String, Failure> {
    worker.call(format!("{line}\n").as_bytes(), |_| true).await
}

/// The decoder's process id, which is also its process group.
async fn pid(worker: &mut Worker) -> String {
    let reply = ask(worker, "pid").await.unwrap();
    reply.trim().rsplit(' ').next().unwrap().to_owned()
}

#[tokio::test]
async fn a_crashing_decoder_costs_one_job_and_is_restarted() {
    let mut worker = decoder(QUICK);
    let first = pid(&mut worker).await;
    assert_eq!(
        ask(&mut worker, "crash").await,
        Err(Failure::DecoderCrash("killed by signal 11".into()))
    );
    assert_ne!(pid(&mut worker).await, first, "a new child serves the next job");
}

/// A wall clock that a hung tool runs into, and that a sandboxed child starting on a loaded machine does not.
const HUNG: Duration = Duration::from_secs(2);

#[tokio::test]
async fn a_hanging_decoder_is_killed_with_everything_it_started() {
    let mut worker = decoder(Limits { wall: HUNG, ..QUICK });
    let group = pid(&mut worker).await;
    let started = Running::start();
    assert!(matches!(ask(&mut worker, "hang").await, Err(Failure::Timeout(_))));
    assert!(started.elapsed() < HUNG * 2);
    killed(&group).await;
    assert_ne!(pid(&mut worker).await, group);
}

/// Waits up to 2 s for a killed process group to exit: a SIGKILLed process may still be running its exit.
async fn killed(group: &str) {
    let since = Running::start();
    while !alive_in_group(group).is_empty() {
        assert!(
            since.elapsed() < Duration::from_secs(2),
            "{:?} survived",
            alive_in_group(group)
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// Processes of a process group that have not exited.
fn alive_in_group(group: &str) -> Vec<String> {
    std::fs::read_dir("/proc")
        .unwrap()
        .filter_map(|entry| std::fs::read_to_string(entry.ok()?.path().join("stat")).ok())
        .filter(|stat| {
            let fields: Vec<&str> = stat.rsplit_once(") ").unwrap().1.split(' ').collect();
            fields[2] == group && fields[0] != "Z"
        })
        .collect()
}

#[tokio::test]
async fn a_pooled_decoder_is_recycled_after_its_job_limit() {
    let mut worker = decoder(QUICK);
    worker.max_jobs = 2;
    let first = pid(&mut worker).await;
    assert_eq!(pid(&mut worker).await, first);
    assert_ne!(pid(&mut worker).await, first);
}

#[tokio::test]
async fn a_flooding_decoder_cannot_exhaust_the_servers_memory() {
    let mut worker = decoder(QUICK);
    worker.max_reply = 1000;
    let first = pid(&mut worker).await;
    assert_eq!(
        ask(&mut worker, "flood").await,
        Err(Failure::LimitExceeded("an answer above 1000 bytes".into()))
    );
    assert_ne!(pid(&mut worker).await, first);
}

#[tokio::test]
async fn the_cpu_limit_reads_as_a_timeout() {
    let mut worker = decoder(Limits { cpu_secs: 1, ..QUICK });
    assert_eq!(
        ask(&mut worker, "spin").await,
        Err(Failure::Timeout("the CPU limit ran out".into()))
    );
}

/// One run of a tool that renders into its output directory, as FFmpeg does: its output, or why it failed.
async fn once(script: &str, wall: Duration) -> (Result<Vec<u8>, Failure>, tempfile::TempDir) {
    let out = scratch();
    let policy = Policy {
        read: vec![],
        write: Some(out.path().to_owned()),
        limits: Limits { wall, ..QUICK },
    };
    let tool = ["/bin/sh", "-c", script, "sh", out.path().to_str().unwrap()].map(OsString::from);
    (run(Path::new(PHOTOLIBD), &policy, &tool).await, out)
}

#[tokio::test]
async fn a_one_shot_tool_renders_or_says_why_it_failed() {
    let (printed, out) = once("echo frame > \"$1/poster.jpg\"; echo '{}'", QUICK.wall).await;
    assert_eq!(printed, Ok(b"{}\n".to_vec()));
    assert_eq!(std::fs::read(out.path().join("poster.jpg")).unwrap(), b"frame\n");
    let broken = "echo 'reading input' >&2; echo 'Invalid data found when processing input' >&2; exit 1";
    assert_eq!(
        once(broken, QUICK.wall).await.0,
        Err(Failure::DecoderCrash(
            "reading input\nInvalid data found when processing input".into()
        ))
    );
    assert_eq!(
        once("yes", QUICK.wall).await.0,
        Err(Failure::LimitExceeded("an answer above 1048576 bytes".into()))
    );
    // Out of threads for a moment, as on a loaded machine: that says nothing about the file, so its job tries again.
    let starved = "[in#0/avi @ 0x5f4710a67200] pthread_create() failed: Resource temporarily unavailable";
    assert_eq!(
        once(&format!("echo '{starved}' >&2; exit 1"), QUICK.wall).await.0,
        Err(Failure::Transient(starved.into()))
    );
    let started = Running::start();
    let (hung, out) = once("sleep 1000 & echo $$ > \"$1/pid\"; sleep 1000", HUNG).await;
    assert!(matches!(hung, Err(Failure::Timeout(_))), "{hung:?}");
    assert!(started.elapsed() < HUNG * 2);
    killed(std::fs::read_to_string(out.path().join("pid")).unwrap().trim()).await;
}

fn png(width: u32, height: u32) -> Vec<u8> {
    let mut file = b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR".to_vec();
    file.extend(width.to_be_bytes());
    file.extend(height.to_be_bytes());
    file.extend([1, 0, 0, 0, 0]);
    file
}

#[tokio::test]
async fn a_decompression_bomb_is_refused_before_decoding() {
    let (library, elsewhere) = (scratch(), scratch());
    // A pixel flood: a few bytes that declare 10 gigapixels.
    let (bomb, photo, secret) = (
        library.path().join("bomb.png"),
        library.path().join("photo.png"),
        elsewhere.path().join("photo.png"),
    );
    std::fs::write(&bomb, png(100_000, 100_000)).unwrap();
    std::fs::write(&photo, png(640, 480)).unwrap();
    std::fs::write(&secret, png(640, 480)).unwrap();
    let mut worker = Worker::prober(PHOTOLIBD.into(), library.path().into());
    assert_eq!(
        worker.probe(&bomb).await,
        Err(Failure::LimitExceeded(
            "100000×100000 is 10000000000 pixels, more than the limit of 300000000".into()
        ))
    );
    assert_eq!(
        worker.probe(&photo).await,
        Ok(Probe {
            format: Format::Png,
            width: 640,
            height: 480
        })
    );
    let Err(Failure::Transient(denied)) = worker.probe(&secret).await else {
        panic!("read outside the library")
    };
    assert!(denied.contains("Permission denied"), "{denied}");
}

/// ExifTool's `-stay_open` protocol: arguments one per line, `-execute` runs them, `{ready}` ends the answer. This
/// stand-in answers with what it was given: its arguments, the file name and the file's content.
const FAKE_EXIFTOOL: &str = r#"
args="$*"
while IFS= read -r line; do
    case $line in
        -execute) printf '[{"SourceFile":"%s","Args":"%s","Content":"%s"}]\n{ready}\n' "$file" "$args" "$(cat "$file")";;
        *) file=$line;;
    esac
done
"#;

#[tokio::test]
async fn exiftool_gets_fixed_arguments_and_a_random_name_never_the_users() {
    let (library, scratch_dir, bin) = (scratch(), scratch(), scratch());
    let fake = bin.path().join("exiftool");
    std::fs::write(&fake, FAKE_EXIFTOOL).unwrap();
    let hostile = library.path().join("-if system('touch pwned')\n-execute\n-o x.JPG");
    std::fs::write(&hostile, "metadata").unwrap();
    let mut exiftool = ExifTool::new(
        PHOTOLIBD.into(),
        vec!["/bin/sh".into(), fake],
        library.path().into(),
        scratch_dir.path().into(),
    );
    for _ in 0..2 {
        let dump = exiftool.dump(&hostile).await.unwrap();
        assert_eq!(
            dump["Args"],
            "-stay_open True -@ - -common_args -j -G1 -a -n -struct -api LargeFileSupport=1"
        );
        assert_eq!(dump["Content"], "metadata", "the link leads to the file");
        let name = Path::new(dump["SourceFile"].as_str().unwrap());
        assert_eq!(name.parent(), Some(scratch_dir.path()));
        let name = name.file_name().unwrap().to_str().unwrap();
        assert!(name.ends_with(".JPG") && name.len() > 10, "{name}");
        assert!(name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.'), "{name}");
    }
    assert_eq!(
        std::fs::read_dir(scratch_dir.path()).unwrap().count(),
        0,
        "the links are removed"
    );
}

/// Needs ExifTool: `TEST_EXIFTOOL=/path/to/exiftool cargo test -- --ignored`.
#[tokio::test]
#[ignore = "needs TEST_EXIFTOOL"]
async fn the_real_exiftool_reads_metadata_in_the_sandbox() {
    let exiftool = PathBuf::from(std::env::var("TEST_EXIFTOOL").expect("TEST_EXIFTOOL"));
    let (library, elsewhere, scratch_dir) = (scratch(), scratch(), scratch());
    let corpus = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../testdata/corpus/files/stills/baseline.jpg");
    let photo = library.path().join("-o pwned\n-execute\n.jpg");
    std::fs::copy(&corpus, &photo).unwrap();
    std::fs::copy(&corpus, elsewhere.path().join("photo.jpg")).unwrap();
    let mut exiftool = ExifTool::new(
        PHOTOLIBD.into(),
        vec![exiftool],
        library.path().into(),
        scratch_dir.path().into(),
    );
    let dump = exiftool.dump(&photo).await.unwrap();
    assert_eq!(
        (dump["IFD0:Make"].as_str(), dump["File:ImageWidth"].as_u64()),
        (Some("Canon"), Some(640))
    );
    assert_eq!(
        exiftool.dump(&elsewhere.path().join("photo.jpg")).await,
        Err(Failure::Unsupported("Error opening file".into()))
    );
    assert_eq!(exiftool.dump(&photo).await.unwrap()["IFD0:Make"], "Canon");
}
