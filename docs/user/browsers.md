# Browsers

The web app is for signed-in users, in the latest two major versions of the browsers below; shared links open in the
lighter viewer instead. The choice is [ADR-0056](../adr/0056-web-support-tiers.md), and the measurements behind it are
in the [web media path report](../dev/web-media-path.md).

| Tier | Browsers | Build | Scope | Checked on every change |
|---|---|---|---|---|
| 1 — first-class | Chrome and Edge on computers; Chrome on Android | dart2wasm with skwasm | Everything the web allows, including folder libraries on computers | In Chrome: WasmGC, ImageDecoder, OPFS, SharedWorker, Web Locks, File System Access, MSE and Trusted Types |
| 2 — functional | Firefox and Firefox ESR; Safari on macOS | dart2js with CanvasKit | Every signed-in feature, with slower rendering; no folder library, as these browsers lack File System Access | In Firefox: WasmGC, createImageBitmap in workers, OPFS, Web Locks and MSE; in WebKit, Safari's engine, and in Firefox: the whole journey of the web app (set-up, upload, viewer, video, downloads, offline); Safari itself on a Mac |
| 3 — basic | Every browser on iPhone and iPad (all use WebKit) | dart2js with CanvasKit | Browsing, viewing, uploading from the photo picker and managing shares; a banner recommends the app | Not yet |
| Unsupported | Older versions | — | A notice asks to update the browser | — |

## Installing and offline

Chrome, Edge and Safari can add the web app to the home screen or the dock (Install in the address bar, Add to Home
Screen). An installed or an ordinary tab opens without a network too: a service worker keeps the app's files from the
last visit, so the library kept in the browser shows, and what needs the server (new photos, video, downloads,
uploads) waits until it answers again. Nothing the server sends as data, such as photos, is kept by that worker.

## Known limitations

* Safari holds a download in memory until it has all of it, as it cannot write a file while it streams: a very large
  zip needs that much memory there.
* Nothing runs while the tab is closed: uploads and sync pause until the app is open again.
* The web app shows no HDR and cannot read the device's photo library.
* Safari decodes HEIC, and Chrome and Edge on macOS and Windows decode it through the system's HEVC decoder (on
  Windows with Microsoft's HEVC Video Extension); elsewhere a HEIC photo shows a mark that says so, and the web app
  shows the JPEG or WebP renditions that the server, or for a private library the uploading device, makes.
* Firefox on Linux plays H.264 video only with the system's FFmpeg libraries.
* A Firefox private window has no OPFS, so the local database lives in memory and is fetched again on every visit.
* Encrypting uploads to a private library in the browser takes up to 1 GB of extra memory while they run.
* The first visit downloads about 2.6 MB in Chrome and 4 MB in Firefox (compressed); later visits use the cache.
