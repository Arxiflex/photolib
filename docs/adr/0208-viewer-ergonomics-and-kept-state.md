# ADR-0208 — Viewer ergonomics behind settings, and what the user looked at kept in the vault

* **Status**: Accepted — 2026-10-21. The owner answered
  (photolib-design#606,
  the provisional choices of photolib-design#468): videos with a sound track pause other audio by default, which the
  toggle can still play over; the defaults of resume, loop and auto-next, the player's volume and window's brightness,
  and dating downloads and shares are kept.
* **Requirements**: R-APP-5, R-COMP-1. **Design**:
  client app §3.6, §4,
  feature catalogue VIEW-36, VIEW-39,
  Play reviews §2.2–2.3,
  [ADR-0106](0106-photo-viewer.md), [ADR-0112](0112-video-and-motion-photo-playback.md).

## Context

The gallery apps win reviews on small ergonomics and lose them when an update drops one or forgets where the user was
(M1-32). The design names the behaviours but not their defaults, the screen areas they use, or where the state lives.

## Decision

We will:

* put each behaviour behind a setting (`Toggle` in `settings.dart`), on by default where it changes nothing a user
  would not expect: edge taps (the outer fifth of each side), one-finger zoom (a double tap held and dragged past the
  platform's touch slop; 100 px down doubles the zoom), and brightness and volume swipes on a flat video (its left and
  right thirds, so the middle third still swipes the viewer away). Full brightness, auto-rotate, loop, auto-next,
  resume, animated grid tiles and play-over are off: videos with a sound track pause other audio, the platform norm;
  a silent one plays over it, as nothing of it is heard. Play-over plays every video over other audio, as Simple
  Gallery's praised default does. A player learns its tracks as it opens; Android's takes audio focus as it was made,
  so a silent video's is made again, while iOS's audio session is the app's, set as each video plays;
* set the app window's brightness (Android's window attribute, iOS's screen, given back when the viewer closes) and
  the player's volume, not the system's, which needs no permission and works on every platform;
* compose the viewer's bar from the actions that exist (info, filmstrip, share, download, copy, reveal); later
  actions join `ViewerAction`, the others stay in its menu;
* badge GIFs by their type: the timeline knows no other animated file until extraction records it (ADR-0261 badges
  by the `animated` facet);
* keep what the user looked at sealed in the vault as `state` (`KeptNotifier`): the item at the top, the selection
  and the item the viewer shows, the search's query and selection, restored only while the library or search has as
  many items, since positions mean nothing in another; the library's view options stay with the settings;
* date downloads and shared copies by the capture time; a browser dates a single file itself.

## Consequences

Each behaviour can be turned off; the defaults are one setting each to change. A restart lands where the user was;
an edit to the library in between drops the selection and the viewer rather than pointing at other items. Android
shares the MediaStore item, whose date is the file's own.

## Options considered

* Every video over other audio by default, Simple Gallery's: the owner chose pausing it for videos with sound.
* System volume and brightness: Android's needs `WRITE_SETTINGS` for brightness, and both leak past the app.
* State in memory or `SharedPreferences`: memory is gone after a restart; preferences would keep search text and
  folder names unencrypted, against ADR-0057.
* Selections kept as item ids: exact across library changes, but a selection of a million items would be a million
  ids; ranges with a count stay a few bytes.
