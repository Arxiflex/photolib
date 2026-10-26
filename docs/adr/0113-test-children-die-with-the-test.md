# ADR-0113 — Test children die with the test

* **Status**: Accepted — 2026-10-20 (photolib-design#432). The owner kept `setpriv --pdeathsig`, with no `unsafe`
  outside `kernel/ffi`
  (photolib-design#464).
* **Requirements**: none directly; the quality gate of 19. **Design**: [ADR-0024](0024-media-sandbox.md).

## Context

The server's tests start servers (the proxies, photolibd, PostgreSQL, Garage, the chaos workers) and tools (FFmpeg,
ffprobe, openssl, curl, the OIDC browser). The proxy suite killed only each proxy's own process on drop, so every
nginx test left its workers behind, and a killed test process (a timeout, an interrupted gate) orphaned every server:
on 2026-10-17 the shared gate machine reached its process cap with about 1,000 threads of orphaned Apaches and nginx
workers. On 2026-10-18 two FFmpeg fixture encodes hung for 74 minutes and held the merge train. Linux stops a child
when its parent dies only if the child asks first, with `PR_SET_PDEATHSIG` between `fork` and `exec`, and the
workspace forbids the `unsafe` that `pre_exec` needs.

## Decision

We will start every server and tool of the server's tests through the `photolib-spawn` crate:

* Each runs in a process group of its own under util-linux's `setpriv --pdeathsig`, which sets `PR_SET_PDEATHSIG` and
  then runs the program. The signal fires when the thread that forked ends, so servers are forked by a thread that
  lives as long as the test process.
* A server's group gets its stop signal on drop and when the test process dies: SIGQUIT for nginx (whose master then
  stops its workers) and PostgreSQL (an immediate shutdown), SIGKILL for the chaos workers, SIGTERM otherwise. On drop,
  SIGKILL follows after 5 s.
* A tool runs to its end within a limit, after which its group is killed and its test fails.

## Consequences

* A test, or a gate, that is killed leaves no server behind; a hung tool costs its test, not the gate.
* The server's tests need `setpriv` on `PATH` (util-linux, in every Linux distribution the gate runs on).
* A server that ignores its stop signal when the test process dies is not killed later: a killed test process can
  send nothing more.
* PostgreSQL runs as `postgres` rather than through `pg_ctl`, which would detach it.

## Options considered

* **`pre_exec` with `prctl`**: needs `unsafe`, which the workspace forbids (ADR-0024).
* **SIGKILL as the death signal**: kills nginx's master but not its workers.
* **Watchdog processes that poll for the test process** (as PostgreSQL and Garage had): one process per server, a
  second of delay, and still none for the proxies.
