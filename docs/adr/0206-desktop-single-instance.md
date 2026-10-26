# ADR-0206 — One Photolib over the store on Linux and Windows

* **Status**: Accepted — 2026-10-21. The owner kept both decisions
  (photolib-design#596,
  photolib-design#554): starts by the flutter tool are not single-instance, and Windows hands files over with
  `WM_COPYDATA` after the session mutex.
* **Requirements**: R-MODE-1. **Design**: docs/10 §8.2.

## Context

Opening a file with Photolib (ADR-0154) started the Linux and Windows apps with its path. While Photolib ran, that
started a second process over the same store, its data isolate a second writer (ADR-0057), and a second window. macOS
already sends a running app the files Finder opens with it. The flutter tool starts the app for runs, integration
tests, drives and benchmarks, several at once on a shared machine and beside an installed Photolib.

## Decision

* **Linux**: the app is a unique `GApplication` that opens files (`G_APPLICATION_HANDLES_OPEN`, its application ID on
  the session bus). A later start hands the running app its arguments as absolute files (`g_application_open`), or
  without files activates it, and ends; the running app takes them as a drop and presents its window.
* **Windows**: the app holds the session's mutex `Local\org.photolib.photolib`. A later start finds it, sends the
  running app's window its arguments as absolute paths in one `WM_COPYDATA`, lets it come to the front and ends,
  waiting up to 10 s for a window still on its way; the window takes them as a drop.
* On both, a `photolib:` link among the arguments (ADR-0243) goes as it is, not as a path, and the running app opens
  it as a link it was started with.
* On both, files that come before Dart asks wait, as on macOS (`opened` of `org.photolib/drag`).
* A start by the flutter tool (`FLUTTER_ENGINE_SWITCHES` set) stays a process of its own and owns nothing.
* `tools/desktop/single_instance.sh` starts a profile build, whose log is plain where a release build's is sealed, on
  a session bus of its own with an unlocked keyring, then the app again with a photo and again with a setup link,
  each of which must end at once while the first logs the drop; `tools/package.sh` runs it with the AppImage's build
  as the later start, then starts the AppImage alone.

## Consequences

* One process writes the store, and opening a file shows it in the window already open.
* Any process of the user's session can hand the app paths, as a drop from any window can, and setup links, as any
  app can open `photolib:`; it takes only paths and links that fill in what the person confirms (ADR-0243).
* A development build beside an installed Photolib shares its store's directory as before, and never forwards.
* Windows' path is not run here: the Windows smoke job builds it, and a person checks the hand-over on a PC.

## Options considered

* **A named pipe on Windows**: a listening thread in the app and its own protocol, where a window message suffices.
* **A lock file in the store with a socket beside it**: no session bus needed, but the same on Linux as D-Bus already
  gives, and a stale lock after a crash.
* **Unique even for the flutter tool**: gates and benchmarks running at once on one bus, or beside an installed app,
  would end each other's starts.
