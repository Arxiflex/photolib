# ADR-0049 — iOS backup: the app's own path for every library, the system upload extension to speed up standard ones

* **Status**: Accepted (owner answered, 2026-10-17) in
  photolib-design#362
  (roadmap M0-32): both paths stand, with the `104` fix below before M2-20, and the placeholder domain stays. The
  throughput numbers are still open: the [spike report](../dev/ios-backup-spike.md) and its probe measure them on a Mac
  and a phone.
* **Requirements**: R-APP-4, R-MODE-2, ING-02, MOB-09. **Design**: 10 §6.2–6.4, 05 §6,
  06 §11, [ADR-0032](0032-one-network-stack.md).

## Context

Design 10 §6.3 lists what iOS offers a backup and leaves the strategy to this spike; the
[report](../dev/ios-backup-spike.md) records what Apple documents. Private libraries must be encrypted on the phone, so
only the app can send them. The system photo-upload extension (iOS 26.1) is the only path that runs without the app,
but it uploads the bytes as stored, needs full library access and the IETF resumable-upload draft, and checks a
build-time `BackgroundUploadURLBase` that self-hosted servers cannot match. A force-quit stops every other path until
the user opens the app. The per-asset state machine of design 05 §6 stays the one source of truth.

## Decision

We will back up iOS libraries along two paths that share that state machine and the server's deduplication by hash.

* **The app's path backs up every library.** It is the only path for private ones and works for standard ones
  wherever the extension does not run.
  * *Change detection*: `PHPhotoLibraryChangeObserver` while the app runs and `fetchPersistentChanges(since:)` at
    every wake; an expired token re-indexes the library.
  * *Preparation*, in the foreground, in `BGProcessingTask`s (network and external power required) and in a
    `BGContinuedProcessingTask` that "Back up now" or "Encrypt and back up library" starts: hash and match first
    (05 §6), export originals with `PHAssetResourceManager` (iCloud downloads happen only here, into the bounded temp
    area of 10 §6.2), encrypt private ones, and write each append (ADR-0032) as a file.
  * *Upload*: background `URLSession` upload tasks from those files. The OS holds at most 32 files or 2 GiB at a time,
    one append per upload, the smallest uploads first, so most photos finish without waking the app. Each wake
    (`handleEventsForBackgroundURLSession`, a background task, the app opening) commits finished uploads, checks
    failed ones against the server's offset and queues the next appends.
* **Standard libraries also use the system upload extension**, where iOS 26.1 or later, full library access and a
  server that passes the extension's preflight (`OPTIONS` with `Upload-Limit`, then `104`) and has an OS-trusted
  certificate and no client certificate allow it. The app enables it with `setUploadJobExtensionEnabled`, and disables
  it on sign-out, when the library turns private, or when the server stops passing.
  * The extension is native Swift with no Flutter engine and no replica. The app's data isolate registers *upload
    intents* with the server for planned resources (a capability URL each, scoped to the user, library, device and
    PhotoKit identity, expiring after 7 days) and lists them in a snapshot in the App Group container. The extension
    creates jobs from the snapshot up to `jobLimit`, holds no session token, acknowledges finished jobs into a journal the
    data isolate merges (the server's asset id comes back in a response header), and retries a transient failure once.
    An expired or used intent fails for good and sends the resource back to planning. The server commits an asset
    when every resource of its intents has arrived: a Live Photo's still and video, an edit's original and rendition.
  * Each planned resource belongs to one path at a time: with the extension on, it takes a standard library's planned
    resources, and "Back up now" moves those it has not taken yet to the app's path. A resource that both paths send
    is still stored once.
  * `BackgroundUploadURLBase` names the project's site, a placeholder until the owner sets the product's name and
    domain during testing, together with the application ID of [ADR-0023](0023-flutter-app-shell.md); intents point at
    the user's server. If an iOS update rejects other hosts, standard libraries fall back to the app's path; a relay
    through a project server is not an option (no new outbound service without an ADR).
  * The extension expects a `104` interim response with the upload's `Location`, and photolibd sends no `104`
    ([ADR-0061](0061-resumable-uploads.md): hyper cannot). Before M2-20, a phone test shows whether jobs run without
    it; if they do not, `/upload` learns to send `104`, through a patched hyper or an HTTP server for `/upload` that
    can send `1xx` responses.
* **Private libraries never use the extension**, whatever the user switches: it uploads plaintext (06 §11).
  Onboarding says that private backup on iOS is slower.
* **Honest status**: the backup screen shows which path each item is on and what stopped it. A force-quit cancels
  background transfers and continued processing and prevents relaunches until the user opens the app, and the screen
  says so.

## Consequences

* M2-07's upload endpoint answers the extension's preflight, speaks the draft versions iOS sends (the probe logs
  them) and accepts upload intents. M2-19 builds the app's path first, with `BGTaskSchedulerPermittedIdentifiers` and
  the `processing` background mode; M2-20 builds the extension target and its App Group only once a phone proves that
  its jobs reach photolibd, with or without `104`.
* The numbers decide the defaults, not the design: appends of 8 or 32 MiB, how many files the OS holds, and whether
  long videos wait for the foreground. M0-27's device lab runs the probe; M2-20's soak measures relaunch delays and
  processing windows.
* The extension's hold on self-hosted servers rests on behaviour Apple does not document; losing it costs speed, not
  backups.
* macOS 27 has the job extension too; the macOS Photos-library source can adopt it later.

## Options considered

* **The app's path only**: works everywhere, but nothing new is backed up until the app or one of its background
  tasks runs to prepare files, and every iCloud original passes through the app's temp area.
* **The extension for every standard library, no fallback**: excludes iOS 16–26.0, limited access, private CAs and
  client certificates, and depends on the undocumented host behaviour.
* **A project-run upload relay matching `BackgroundUploadURLBase`**: routes every user's photos through one operator,
  against the self-hosting promise, and needs an ADR and a privacy review.
* **Whole files per background task instead of appends**: fewer wakes, but a reverse proxy's 100 MB request cap fails
  large videos (ADR-0032).
