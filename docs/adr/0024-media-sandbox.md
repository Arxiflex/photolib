# ADR-0024 — Media sandbox: a self-confining `photolibd media-child`

* **Status**: Accepted — 2026-10-15. The owner confirmed the three choices M0-19 made: the seccomp deny-list, tools
  that may execute system programs, and failing an oversized metadata dump
  (photolib-design#281).
* **Requirements**: R-SEC-1, NFR-SEC-1. **Design**: 08 §8, ADR-0012.

## Context

ADR-0012 decides that untrusted media is parsed only in sandboxed child processes, and 08 §8 lists the controls. The
server forbids `unsafe`, so it cannot set up a sandbox between `fork` and `exec`, and the decoders that will run in it
(ExifTool now; libvips and FFmpeg later) make different system calls on every version and architecture.

## Decision

* A worker starts `photolibd media-child --policy <json> -- <tool>` with an empty environment, in its own process
  group. The child confines itself while it still has one thread, prints `{"sandbox":"full"}` (or `"partial"`), then
  executes the tool, or runs the built-in header prober when there is none.
* **rlimits**: address space, CPU seconds over the child's life, file size, open files, and no core dumps.
* **Landlock** (ABI 6, best effort): read the policy's paths; write, but not read, the output directory; a tool may also
  read and execute `/usr`, `/bin`, `/lib`, `/lib64` and `/etc/ld.so.cache`. No TCP, and no signals or abstract
  sockets outside the sandbox.
* **seccomp** is a deny-list answering `EPERM`: `socket`, `ptrace`, `process_vm_*`, `setsid`/`setpgid`, mounts,
  namespaces, `bpf`, `perf_event_open`, `userfaultfd`, `io_uring_setup`, keyrings, kernel modules, `kexec_load` and
  `open_by_handle_at`.
* The worker kills the whole process group after a crash, a wall-clock timeout or an answer above 1 MiB, reports
  `decoder_crash`, `timeout` or `limit_exceeded`, and starts a new child for the next job. Children are recycled after
  500 jobs (ExifTool 1,000) or 10 minutes. A partial sandbox logs `sandbox: partial`.
* The pixel limit is checked on the header (PNG, JPEG and GIF so far) before anything decodes the image.
* ExifTool gets one fixed argument list; each file is a random-named link in a scratch directory, keeping only an
  alphanumeric extension. An `ExifTool:Error` is a failure, not a dump.

## Consequences

* ✅ No `unsafe` code and no extra binary; a crashing or hanging decoder costs one job, not the server.
* ⚠️ A deny-list, not the allow-list 08 §8.1 first asked for: it cannot break a tool that makes an unexpected call,
  but it lets through calls nobody listed. Revisit with the pinned media base image.
* ⚠️ A tool may execute any program under `/usr`, inside the same sandbox; "execve only to start the tool" holds only
  for the built-in prober.
* ⚠️ `RLIMIT_CPU` counts a pooled child's whole life; the wall clock is what bounds one job.
* ⚠️ A metadata dump above 1 MiB fails with `limit_exceeded` instead of being truncated and flagged, as 08 §8.2
  first asked.
* ⚠️ Not built yet: cgroup v2 memory and pids limits, dropping to another user when photolibd runs as root, FFmpeg and
  libvips children, duration and frame limits, and showing a partial sandbox outside the log.
* ⚠️ Linux only. Landlock needs Linux 5.13; the full sandbox (signal scoping) needs 6.12.

## Options considered

* **Sandbox set up by the parent** (`pre_exec`): needs `unsafe`, which the workspace forbids.
* **A seccomp allow-list now**: what 08 §8.1 asks for, but an unlisted call in a new libvips, FFmpeg or Perl breaks
  ingest on some architecture; better written against the pinned media image.
* **bubblewrap, nsjail or minijail**: another binary to ship, and the user namespaces they rely on are often disabled
  in containers.
