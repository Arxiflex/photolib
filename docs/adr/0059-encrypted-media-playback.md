# ADR-0059 — Encrypted playback: a decrypting loopback proxy on native, MSE and a Service Worker on the web

* **Status**: Accepted (owner answered, 2026-10-17) in
  photolib-design#363
  (roadmap M0-33): no AES-128 HLS and the loopback relay on Windows and Linux stand, the benchmark runs unless a
  diff provably touches no playback code (kept on 2026-10-21 in
  photolib-design#560),
  and the end-to-end invariant below is the owner's.
* **Requirements**: R-PRIV-1, F-12. **Design**:
  media pipeline §6,
  security and E2EE §3.1, §4.

## Context

Design 08 §6 fixes the format (every private rendition and original is one PLB envelope of 64 KiB chunks, so any
byte range decrypts alone), and the players per platform, and leaves three questions to M0-33: whether AES-128 HLS is
needed at all, whether Windows and Linux use the loopback proxy or the player backend's custom-stream callbacks, and
whether seeking in a 2-hour private video starts within 1 s. The spike built random-access decryption in the kernel,
a decrypting session in the loopback `MediaProxy` and a benchmark of every path a Linux machine can run; the numbers
are in the [encrypted playback report](../dev/encrypted-playback.md). Every measured path seeks in a few hundred
milliseconds at most. The report also has two findings that shape the decision: progressive players seek a
*fragmented* MP4 by reading its fragments in order (Firefox needed 3.7–5.7 s per encrypted seek), and a proxy that
streams an open-ended range whole decrypts ahead into socket buffers that each seek throws away.

## How it works

Playback of a private library is end to end encrypted: the "proxy" is no server but a small relay inside the app, on
the device itself.

1. Before upload, the device encrypts the video in 64 KiB chunks; the server stores only ciphertext and never has a
   key.
2. To play or seek, the app fetches the encrypted 1 MiB window around that point and decrypts it on the device with
   the kernel.
3. It hands the decrypted bytes to the device's own player: through the in-app relay on 127.0.0.1 on Apple, Windows and
   Linux, an in-app data source on Android, and a Service Worker or MSE inside the browser tab on the web.

Every chunk is authenticated, so a hostile server cannot feed crafted bytes to a decoder; windows are aligned, so the
server learns only roughly where a seek lands; the relay answers only 127.0.0.1, with a per-session token, and refuses
other `Host` headers. **In private mode, media is decrypted only on the device, and decrypted bytes never leave it;
any later path that would (casting) asks the user first.**

## Decision

We will play private media as follows.

* **Random access in the kernel.** `DecryptBlob` opens any run of an unpadded envelope's chunks given the header, the
  index of the first chunk (`first_chunk`) and whether more follow (`more`); the index and the last flag stay bound by
  the nonce. A padded envelope opens only whole, as its padding may span the chunks before the last. Readers fetch
  ciphertext in aligned 1 MiB windows, so the server never learns where a range starts.
* **Native targets read through `MediaProxy.decrypted`** (iOS, iPadOS, macOS, Windows, Linux): one implementation in
  Dart with the kernel through its C ABI, behind a per-session token on 127.0.0.1, refusing any other `Host`. It
  answers a closed range (an HLS segment) whole and an open-ended one (a progressive player reading on) to the end of
  its window; the player asks again. Each window is fetched only once the player has taken the previous one, and one
  that fails to open ends the response short, so no unauthenticated byte reaches a decoder. Windows and Linux use it
  rather than the player backend's stream callbacks, which would be native code per backend. Android keeps the
  in-process ExoPlayer `DataSource` of design 08 §6.3 and can fall back on the same proxy.
* **The web** plays stream renditions through MSE (ManagedMediaSource where it exists, with remote playback off) fed
  by a worker that decrypts with the kernel's WebAssembly, and originals through a Service Worker that answers the
  `<video>` element's range requests one window at a time.
* **Stream renditions are never played progressively**: through MSE on the web and, on native targets, an HLS
  playlist the client writes from the stream index, whose `EXT-X-MAP` and `EXT-X-BYTERANGE` segments point into the
  proxy's session. Progressive playback is for originals, which keep their sample index in `moov`.
* **No AES-128 HLS**: it puts the key in a playlist and authenticates nothing, and no measured path needs it.
  Casting private videos is decided with casting (M11-03): screen mirroring, or a short-lived local-network stream from
  the device that asks the user first.
* **The budget is a check**: `node tools/playback/bench.mjs`, in the gate's `web` part only when the diff touches
  playback code (`MediaProxy`, the kernel's blob decryption, `tools/playback/`; `PLAYBACK` in `tools/check.sh`), fails
  when the median seek of any path in Chrome or Firefox exceeds 1 s. Without a diff to tell (no `origin/main`, a
  shallow clone) it runs: only a diff that provably touches no playback code skips it (`playback_changed`), as the
  owner kept in photolib-design#560.

## Consequences

* Every change is measured on Linux in Chrome and Firefox. AVPlayer with HLS (Apple), libmpv (Windows, Linux),
  ExoPlayer (Android) and Safari with ManagedMediaSource (iOS 17.1+) are unmeasured: they need M0-27's device lab or
  a macOS and Windows run of the benchmark. Chrome 155's built-in HLS player refused the benchmark's playlist even
  unencrypted, so no browser here stands in for AVPlayer.
* Writing the m3u8 from the stream index, the hls.js loader and the `DataSource` remain M6-04 and M6-06 work; the
  benchmark's pieces in `tools/playback/` are a measurement, not product code.
* An original that is itself a fragmented MP4 seeks slowly in Gecko-based players; the app should prefer the stream
  rendition for such files once it exists.
* A gate that measures playback takes about a minute longer and needs both browsers; others skip it, as seek timings
  on the loaded shared machine would make the only merge gate flaky.

## Options considered

* **Answer every range whole, streaming windows**: seeks through the proxy took 227 ms instead of 90 ms in Chrome,
  with 5.7 instead of 1.5 server requests per seek, as decrypted read-ahead was thrown away.
* **Cut every response at its window**: HLS players need the byte range they asked for.
* **Progressive playback of stream renditions with a `sidx`**: Gecko does not use it; Firefox took 0.8 s per seek
  unencrypted and 5.7 s through the proxy.
* **The player backend's custom-stream callbacks on Windows and Linux**: native code per backend for what the proxy,
  needed on Apple targets anyway, already does within budget.
* **AES-128 HLS**: unauthenticated CBC with the key in the playlist, so a server could feed crafted input to the
  decoder (design 08 §6.2).
