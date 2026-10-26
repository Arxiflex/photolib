# Android default-gallery matrix (M0-31)

What each Android version from the app's `minSdk` and the Pixel, Samsung and Xiaomi phones do for the behaviours a
default gallery depends on (design 10 §5). The decision built on it is
[ADR-0039](../adr/0039-android-default-gallery.md).

Sources, 2026-10-16: the [MediaStore reference][mediastore] for API 30–37, AOSP's MediaProvider
([`PermissionActivity`][permission-activity]), the [Android 16 behaviour changes][android16] and the trackers of Aves,
Fossify Gallery, Immich and Ente (research). No phone was available, so no cell comes from our own run.

## Behaviour × Android version × OEM

✓ as documented; — not available; *open*: no evidence yet, filled by a device run (below).

| Behaviour | 11 (API 30) | 12 (API 31–32) | 13 (API 33) | 14 (API 34) | 15 (API 35) | 16 (API 36) | 17 (API 37) | Pixel | Samsung | Xiaomi |
|---|---|---|---|---|---|---|---|---|---|---|
| `VIEW` (open with) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | *open* | *open* | Camera: explicit `VIEW`, no MIME type, refused as not matching Aves' filter ([Aves #727][a727]) |
| `EDIT` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | *open* | *open* | *open* |
| `PICK` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | *open* | *open* | *open* |
| `GET_CONTENT` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | *open* | *open* | *open* |
| `SEND`, `SEND_MULTIPLE` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | *open* | *open* | *open* |
| `REVIEW`, legacy `com.android.camera.action.REVIEW` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Camera: Google Photos only ([Aves #1058][a1058]) | Camera: Samsung Gallery only, no fallback ([Aves D817][ad817], [Fossify #411][f411]) | *open* |
| `REVIEW_SECURE` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | *open* | *open* | *open* |
| Generation sync | ✓; deletions not reported | ✓; deletions with S extension 23 | ✓; as 12 | ✓; as 12 | ✓; as 12 | ✓; `getVersion()` differs per app | ✓; deletions from 37.1 | *open* | *open* | *open* |
| Trash request | A dialog per request | No dialog with `MANAGE_MEDIA` | as 12 | as 12 | as 12 | as 12 | as 12 | *open* | *open* | *open* |
| Favourite request | No dialog (AOSP) | No dialog | No dialog | No dialog | No dialog | No dialog; `markIsFavoriteStatus` | as 16 | *open* | *open* | *open* |
| Delete request | A dialog per request | No dialog with `MANAGE_MEDIA` | as 12 | as 12 | as 12 | as 12 | as 12 | *open* | *open* | *open* |
| `MANAGE_MEDIA` | — | Special access | ✓ | ✓ | ✓ | ✓ | ✓ | Granted from the app (Pixel 7, [Aves #925][a925]) | One UI 6 closed the app on the request screen; Settings › Special access worked ([Aves #925][a925]) | *open* |
| Partial access | — | — | — | `READ_MEDIA_VISUAL_USER_SELECTED` | + `QUERY_ARG_LATEST_SELECTION_ONLY` | ✓ | ✓ | *open* | *open* | *open* |
| SD cards | One MediaStore volume per card | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | No card slot | Card `0000-0000`: moves and renames failed (Android 12, [Aves D2288][ad2288]) | Card `FE38BD1638BCCF41`: copies failed (API 30, [Aves #506][a506]) |

## Which cameras hand off

| Camera | The thumbnail sends | Third-party gallery | Evidence |
|---|---|---|---|
| Pixel Camera | An intent for Google Photos only | No, except through the Gcam-Services-Provider shim | [Aves #1058][a1058], [#2248][a2248] |
| Samsung Camera | An intent for Samsung Gallery only; "Unable to find application" when it is disabled | No | [Aves D817][ad817], [Fossify #411][f411] |
| Xiaomi Camera | A chooser of galleries, then an explicit `VIEW` with no MIME type | Refused for Aves ("Access blocked"); *open* | [Aves #727][a727] |
| Motorola Camera | An intent for Google Photos only | No | [Fossify #971][f971], [Ente #11742][e11742] |
| Aperture (LineageOS) | `REVIEW`, `VIEW` when nothing handles it; `REVIEW_SECURE` with `ClipData` when locked | Yes | [Aves #1052][a1052], [Fossify #411][f411], [Aves #1539][a1539] |
| Open Camera | Legacy `REVIEW`, no MIME type, one URI | Yes | [Aves #1539][a1539], [Immich D31684][i31684] |
| Fossify Camera | `VIEW image/jpeg`, also from the lock screen | Yes | [Aves #1539][a1539] |
| GrapheneOS Camera | Nothing: it has its own viewer | No | [Aves #1539][a1539] |

## Findings

* **Defaults**: a default set for `REVIEW` survives installing another gallery, while one for `VIEW image/*` is
  dropped whenever its set of handlers changes ([Immich D31684][i31684]).
* **Intents without a MIME type**: Xiaomi's `VIEW` and Open Camera's `REVIEW` carry none, so entry filters also accept
  `content:` URIs without a type.
* **Lock screen**: only Aperture sends `REVIEW_SECURE`; Fossify Camera sends a plain `VIEW` over the keyguard.
* **Requests**: `MANAGE_MEDIA` removes only the dialogs of trash, delete and write requests; writes also need
  `ACCESS_MEDIA_LOCATION`, and all three need the full read permission (`READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` from
  API 33), so partial access brings the dialogs back. AOSP grants favourite requests without a dialog, and
  `markIsFavoriteStatus` needs no `PendingIntent` (API 36, or API 30 with R extension 16). Targeting API 36, each
  request takes at most 2,000 URIs.
* **The `MANAGE_MEDIA` flow**: the request screen closed Aves on One UI 6 and on an LG ([Aves #925][a925],
  [#1036][a1036]); save state before opening it, re-check `canManageMedia` on resume and offer the path through Settings.
* **Sync**: generations exist from API 30; targeting API 36, `getVersion()` is unique per app and still means "rescan"
  when it changes. Deletions carry no generation until `queryDeletedFiles` (API 37.1, or API 31 with S extension 23),
  which forgets removed cards.
* **No all-files access**: API 37's `trashFile` and `restoreFileFromTrash` need `MANAGE_EXTERNAL_STORAGE`.
* **SD cards**: volume ids vary (`0000-0000`, 16 hex digits), and moves between volumes are copies.

## Filling the open cells

With one phone connected over adb (`ANDROID_SERIAL` picks one of several):

```sh
bash tools/android/gallery_probe.sh [package]
```

It prints the phone's section: handlers and default per intent, the default camera, `MANAGE_MEDIA` for the package and
the camera's last intents in the log (tap its thumbnail first). The sync, request and SD card rows come from the
instrumented tests of M1-01, M1-16 and M1-18 on the same phones (design 10 §5.7).

[mediastore]: https://developer.android.com/reference/android/provider/MediaStore
[permission-activity]: https://android.googlesource.com/platform/packages/providers/MediaProvider/+/refs/heads/main/src/com/android/providers/media/PermissionActivity.java
[android16]: https://developer.android.com/about/versions/16/behavior-changes-16
[a506]: https://github.com/deckerst/aves/issues/506
[a727]: https://github.com/deckerst/aves/issues/727
[a925]: https://github.com/deckerst/aves/issues/925
[a1036]: https://github.com/deckerst/aves/issues/1036
[a1052]: https://github.com/deckerst/aves/issues/1052
[a1058]: https://github.com/deckerst/aves/issues/1058
[a1539]: https://github.com/deckerst/aves/issues/1539
[a2248]: https://github.com/deckerst/aves/issues/2248
[ad817]: https://github.com/deckerst/aves/discussions/817
[ad2288]: https://github.com/deckerst/aves/discussions/2288
[f411]: https://github.com/FossifyOrg/Gallery/issues/411
[f971]: https://github.com/FossifyOrg/Gallery/issues/971
[e11742]: https://github.com/ente/ente/issues/11742
[i31684]: https://github.com/immich-app/immich/discussions/31684
