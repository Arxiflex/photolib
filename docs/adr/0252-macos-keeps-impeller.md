# ADR-0252 — macOS keeps Impeller; the gate tracks the upstream fix of its foreground crash

* **Status**: Accepted (owner answered photolib-design#584, 2026-10-21). Supersedes
  [ADR-0220](0220-macos-skia-until-185394.md).
* **Requirements**: R-APP-5. **Design**: client app §1.1, [ADR-0146](0146-panoramas-and-360-video.md).

## Context

The pinned engine's back-buffer cache can hand Impeller a surface of the wrong size when the macOS app comes back to
the foreground, and the raster thread crashes (flutter/flutter#185394; the fix, flutter/flutter#192522, is in no
stable release). ADR-0220 rendered macOS with Skia meanwhile, which costs Display P3 and 360° video, as
`ImageFilter.shader` is Impeller's. The owner chose Impeller and its known crash over that cost.

## Decision

We will leave Impeller on for macOS (no `FLTEnableImpeller` key in `app/macos/Runner/Info.plist`) and list the crash
as a known issue in the macOS release notes (`docs/user/release-notes.md`) with its workaround: quit rather than hide
the app, and reopen it. `tools/tests/test_macos_impeller.sh`, in the gate's `repo` part, names the pinned Flutter and
whether it carries flutter/flutter#192522: read from the engine's `FlutterSurfaceManager.mm` where that Flutter's
source is installed, else from the record the test keeps (the last pin checked and the upstream status then). It fails
when `app/.fvmrc` moves until the record follows, with the upstream status while the new pin lacks the fix; when the
pin carries it, it asks for the macOS smoke (20 hide/show cycles, a 360° video plays) and for the known issue to go.

## Consequences

* Display P3 and 360° video work on macOS again; a user who hides and shows the app can meet the crash until the bump.
* No Flutter upgrade can pass the gate without saying where the fix stands.
* No upstream status is fetched: the gate stays offline, and the record is as fresh as the last pin checked.

## Options considered

* Keep ADR-0220's Skia opt-out: no crash, but no P3 and no 360° video on macOS, and the owner declined it.
* Fail the gate while the pin lacks the fix: every merge would fail until upstream ships it.
* Ask GitHub for the pull request's state in the gate: a network call, rate limits and a flaky gate.
