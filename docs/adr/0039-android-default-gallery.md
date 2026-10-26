# ADR-0039 — Android default gallery: API 30 and what is supported

* **Status**: Accepted — 2026-10-16 (roadmap M0-31; answers design 10 §14.2 question 1 and open decision 14). The
  owner confirmed both choices: API 30 as the minimum, and no promise of the stock cameras' hand-off
  (photolib-design#332).
* **Requirements**: R-APP-4. **Design**: 10 §1.1 and §5, 18 §8.

## Context

Design 10 makes Photolib Android's default gallery and left two questions to this spike: API 30 or 29 as the minimum,
and what the OEM cameras and Android versions let a third-party gallery do. The [matrix](../dev/android-gallery.md)
answers them from Android's reference, AOSP's MediaProvider and other galleries' trackers, as no phone was available:

* MediaStore generations and the trash, favourite, delete and write requests all arrive in API 30; API 29 has none.
* The stock cameras of Pixel, Samsung and Motorola open only their own gallery, and Xiaomi's refused the only
  third-party gallery tried. AOSP-style cameras (Aperture, Open Camera, Fossify Camera) hand off.
* `MANAGE_MEDIA` (API 31) removes the batch dialogs, but its request screen has closed apps on some phones.
* Android 16 and 17 add `markIsFavoriteStatus`, a 2,000-URI limit per request and a deletion feed
  (`queryDeletedFiles`), and API 37's file trash needs `MANAGE_EXTERNAL_STORAGE`.

## Decision

We will keep API 30 (Android 11) as the minimum, with one sync path (generations, plus `queryDeletedFiles` where it
exists and id diffs elsewhere) and one trash path (MediaStore requests, one dialog per batch of at most 2,000 URIs,
none with `MANAGE_MEDIA` from API 31).

We will support on every version: `VIEW`, `REVIEW` and legacy `REVIEW` (also without a MIME type), `REVIEW_SECURE`
read-only, `PICK`, `GET_CONTENT`, `SEND`, `SEND_MULTIPLE`, `EDIT`, `ATTACH_DATA` and `APP_GALLERY`; trash, favourite
and delete requests; `MANAGE_MEDIA` as an onboarding step that also works through Settings; partial access as a
limited mode; and every MediaStore volume, SD cards included.

We will not promise that the camera thumbnail opens Photolib on the stock cameras of Pixel, Samsung, Xiaomi or
Motorola: onboarding names the default camera and the cameras that hand off. We will never request
`MANAGE_EXTERNAL_STORAGE`.

## Consequences

* M1-01 indexes with generations and detects deletions with `queryDeletedFiles` when available, id diffs otherwise.
* M1-16 splits requests at 2,000 URIs and survives the app closing on the `MANAGE_MEDIA` screen.
* M1-18 fills the matrix's open cells on Pixel, Samsung and Xiaomi phones with `tools/android/gallery_probe.sh`, and
  a new ADR supersedes this one if they contradict it.
* Users who keep a stock camera review captures in the OEM gallery.

## Options considered

* **API 29**: a second sync path (no generations) and a second trash path (no trash or batch requests, one
  `RecoverableSecurityException` per item) for one Android version.
* **API 31**: drops Android 11 only to avoid its batch dialogs, which Photolib can live with.
* **All-files access**: Play treats it as invalid for galleries, and MediaStore covers what a gallery needs.
* **Camera shims or Google Photos' private intents**: they depend on unpublished behaviour that changes without notice.
