# iOS backup spike report (M0-32)

What PhotoKit and iOS's background mechanisms give a backup of a 100k-asset library, for the decision in
[ADR-0049](../adr/0049-ios-backup-strategy.md). Written on 2026-10-16 at commit `c8f3006` on Linux: there was no Mac
and no iPhone, so every measurement below is still open. The API facts are from Apple's documentation of that day.

## How it is measured

`bash tools/ios/photokit_probe.sh` on a Mac with Xcode and Flutter runs one XCTest,
`app/ios/RunnerTests/PhotoKitProbe.swift`, on the first iPhone simulator after seeding its library to 100k small JPEGs
dated over 15 years (`--seed <assets>` changes the size). `--device <udid> -- DEVELOPMENT_TEAM=<team>
-allowProvisioningUpdates` runs it on a phone's own library instead: it never seeds a phone and restores the favourites
it toggles. The test uploads to `tools/ios/probe.py sink` on the Mac, which discards the bytes and logs the `Upload-*`
headers iOS sends (M2-07 must speak the same draft). The probe prints this table's numbers and those headers. The gate
runs it with stubbed Apple tools. On this machine the sink takes 1.1–1.2 GB/s over loopback on one connection, far
above any phone's link.

| Metric | Counts | Budget (design 10 §13) | iPhone 13-class | Simulator |
|---|---|---|---|---|
| `seed` | assets added, 500 per change block | — | never seeded | open |
| `enumerate` | assets fetched newest first, burst frames included, reading the index fields of 10 §6.1 | 100k without stalls | open | open |
| `cloud_ids` | cloud identifiers mapped, 1,000 per call | — | open | open |
| `thumb_fast` | 256 px thumbnails of the newest 2,000, `fastFormat`, no network, all requested at once | grid at 60 fps | open | open |
| `thumb_quality` | the same in `highQualityFormat` | — | open | open |
| `observe` | seconds from a favourite change on 20 assets to the change observer | within seconds | open | open |
| `persistent_changes` | assets in the persistent history since the change | — | open | open |
| `live_resources` | Live Photos (the first 500) whose resources include the paired video | — | open | none seeded |
| `burst_frames` | frames of up to 100 bursts, fetched by burst identifier | — | open | none seeded |
| `icloud_download` | originals kept in iCloud (up to 20 of the oldest 500), downloaded one at a time; MB/s | — | open | none |
| `upload_background_8m` | four 8 MiB appends at once through a background `URLSession`; MB/s | — | open | open |
| `upload_foreground_8m` | the same through an in-process session | — | open | open |
| `upload_background_32m` | four 32 MiB appends at once through a background session | — | open | open |
| `upload_foreground_32m` | the same through an in-process session | — | open | open |

*Open*: Xcode and the simulators run only on macOS, and no phone was available. The phone column is for M0-27's
device lab. Not measurable by a test at all: how often and how long `BGProcessingTask`s run, and how a suspended app's
chained uploads slow down; M2-20's soak (a 10k-item backup across suspensions) measures them.

## What iOS gives

* **Background `URLSession`** ([docs][bg-session]): transfers run in a system process while the app is suspended or
  was terminated by the system, which relaunches it when they finish. Only uploads from a file survive. A task created
  while the app is in the background waits for a delay that grows with each background relaunch and resets when the
  user opens the app. When the user closes the app in the app switcher, the system cancels its transfers and does not
  relaunch it. Since iOS 17 uploads follow draft-ietf-httpbis-resumable-upload-01 when the server does
  ([docs][resumable]), and background sessions resume interrupted uploads themselves.
* **`BGProcessingTask`**: minutes of work, only while the device is idle, optionally only with network and external
  power. It ends as soon as the user picks up the device.
* **`BGContinuedProcessingTask`** (iOS 26, [docs][continued]): starts in the foreground, only on a user's action, and
  keeps running in the background behind a system progress Live Activity that the user can cancel. Under pressure the
  system ends the tasks showing the least progress first. Closing the app in the app switcher cancels it without notice.
* **System photo-upload extension** ([docs][extension]): `PHBackgroundResourceUploadExtension` (iOS 26.1), deprecated
  in iOS 27 by the async `PHBackgroundResourceUploadJobExtension`, which macOS 27 also has. The system calls the app
  extension (`com.apple.photos.background-upload`) when network, power and use allow. The extension creates one
  `PHAssetResourceUploadJob` per resource with a destination `URLRequest`, up to `jobLimit` unacknowledged jobs, and
  the system fetches iCloud originals itself. The extension acknowledges finished jobs, reading the server's response
  headers, and may retry a failed job once, with a new destination if it likes. It needs full library access, the
  app's `setUploadJobExtensionEnabled(true)`, a `BackgroundUploadURLBase` in its `Info.plist` and a server that answers
  `OPTIONS` with `200` and `Upload-Limit` and sends `104` with the upload's `Location`. It is not available in the
  Simulator. It uploads the bytes as stored, so it cannot encrypt.

## Findings

* `BackgroundUploadURLBase` is fixed at build time and "required for network access validation". Third-party
  uploaders report that the extension does not register without it and that, today, jobs may upload to other hosts
  ([YAIIU #56][yaiiu], [SnapSync #248][snapsync]); nothing in Apple's documentation promises the latter. A self-hosted
  server is on the user's own host, so the extension is an accelerator that can disappear with an iOS update, never
  the only path.
* A destination is a plain `URLRequest`: the extension has no `URLSession` delegate to accept a private CA or present
  a client certificate (design 10 §14.2, question 3), so such servers stay on the app's path. Not yet tried on a phone.
* Background sessions need files, so the app's path writes each append before it is sent: ciphertext for private
  libraries, exported originals otherwise, in the bounded temp area of 10 §6.2. Appends of one upload go in order, and
  each next append queued from the background waits for the growing relaunch delay, so photos that fit one append
  finish first and long videos move fastest while the app runs.
* Only a user-started continued-processing task keeps the app running for a long backup, and only until the user
  closes it.

[bg-session]: https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
[resumable]: https://developer.apple.com/documentation/foundation/pausing-and-resuming-uploads
[continued]: https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados
[extension]: https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background
[yaiiu]: https://github.com/FawenYo/YAIIU/issues/56
[snapsync]: https://github.com/stefanhoelzl/SnapSync/pull/248
