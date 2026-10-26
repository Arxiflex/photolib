# ADR-0144 — Desktop drag and drop: dropped folders join the library, dropped photos open, cells drag out as files

* **Status**: Accepted — 2026-10-20. The owner confirmed every part: drops, drags out as copies, the runners' own code
  (photolib-design#505,
  roadmap M1-20); the macOS and Windows runners are verified in the test phase. The owner kept the mouse drag in the
  viewer dragging the file out, as amended in #506
  (photolib-design#553).
* **Requirements**: R-MODE-1. **Design**: docs/10 §8.2, DSK-03 of docs/02.

## Context

DSK-03 asks for drag and drop in and out of the desktop app; docs/10 §8.2 says no more. Flutter has no drag and drop
with other apps on desktops (flutter/flutter#30719), and the plugins that add it either take drops only or bring a
Rust build with prebuilt binaries fetched at build time. The desktop library is folders (docs/10 §8.1), and a file
outside them is not in the replica.

## Decision

We will drag files between the file manager and the window through `org.photolib/drag`, written once per desktop in
the runners: GTK's drag and drop (`file_drag.cc`), AppKit's dragging session and destination (`FileDrag.swift`),
`WM_DROPFILES` and `SHDoDragDrop` (`file_drag.cpp`).

* **In**: a folder dropped on the window joins the library as if picked (`addPickedFolder`, a bookmark on macOS);
  photos and videos dropped open in the viewer, over the dropped files alone, in their order; other files are ignored.
  The window ignores its own drags.
* **Out**: a mouse that moves a cell as far as a drag starts in Flutter (2 px) drags its file, or every selected file
  when the cell is selected, as a copy; only files of folders have one. Touch keeps scrolling and selecting. So does
  a mouse drag on the item the viewer shows, unless zoomed in, where it pans; there a mouse no longer swipes the
  viewer away, which touch and Escape still do.
* After a drag out, the runner tells Flutter the mouse button went up: the platform's drag kept the mouse, and Flutter
  would otherwise lose the next click.

## Consequences

* Each desktop's code is its own and small; only Linux is compiled and run here (the smoke test drags both ways with
  another X11 client, `tools/desktop/xdnd.c`); macOS and Windows run in the smoke jobs and on the owner's machines.
* Opening a file with the app (file associations, M10-04 packaging) can reuse the viewer over dropped files. The
  owner's note for later: a dropped file that already lies in a library folder opens that item in its library context
  (its folder as the swipe context) rather than a detached viewer, with file associations (M10-04).
* Dragging out a server-only item needs its download first (M2-24).

## Options considered

* **super_drag_and_drop**: drops and drags on every platform, but builds Rust through cargokit with prebuilt binaries
  downloaded at build time, a new outbound dependency of the build.
* **desktop_drop**: drops only.
* **Copying dropped files into a folder of the library**: the app would write the user's files, which it otherwise
  never does on desktops, and pick a folder for them.
