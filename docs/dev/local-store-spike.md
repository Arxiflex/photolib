# Local store encryption spike (M0-42)

What encrypting every local store costs against the budgets of design 21 §8, and what secure hardware can
bind a passcode on each platform, measured on 2026-10-17. The decisions are
[ADR-0090](../adr/0090-local-store-cipher-and-passcode-binding.md).

## How it is measured

One benchmark, `app/packages/photolib_data/lib/src/store_cost.dart`, runs on every target:

* **Database**: the replica's schema and design 10 §2's `timeline_entry` and `timeline_bucket`, filled with assets
  spread over 15 years, under each page cipher of SQLite3MultipleCiphers the build has, 4 KiB pages. *Bucket* reads the
  bucket table, *window* reads 120 cells at a random date, *fling* 100 windows in a row, each with SQLite's cache
  emptied so that every page is read and decrypted; *snapshot* applies a sync snapshot page (1,000 new assets in one
  transaction), *log* a log batch (1,000 random assets changed). The ciphers take turns, in the opposite order every
  other round, for 7 rounds (up to 28 while AEGIS-256 misses 10 %); a time is the fastest round, an overhead the median
  of the rounds' ratios to plaintext, so that load slows both sides of a ratio (photolib-design#436; the results below
  are ratios of the fastest rounds, with 20 windows a sample where it now takes 100). Natively the thread's CPU time
  on the fastest cores.
* **Thumbnails**: 16 KiB entries read through `Vault.read`, which opens their PLB envelopes, against plaintext files
  in the same store: the 95th percentile of 640 reads one at a time, and the rate of 160 reads 4 at a time, as the
  timeline's queue makes them (ADR-0070); the best of up to 10 rounds while the budget is missed.
* **Store open** (cold start at L1): the vault unlocked with its keystore key, the replica opened and queried.
* **Unlock** (L2, without `HW`): Argon2id timed at the floor (64 MiB, `t = 3`) after a warm-up derivation, `t`
  calibrated as crypto v1 says, then `KEK_pass`, the lockbox, the page key, the keyed database and its first window;
  the fastest of three, natively in the thread's CPU time.

| Run | Command | Assets |
|---|---|---|
| VM (JIT), gate `dart` part, alone (tag `alone`) | `flutter test test/store_cost_test.dart [--dart-define=assets=N]` in `app/packages/photolib_data` | 100k, 1M |
| Browsers, gate `web` part | `web_test.dart` there: database and unlock in dart2js only, thumbnails in dart2js and dart2wasm | 30k |
| App (AOT), devices | `PERF_RESULTS=<file> flutter drive --profile -d <device> --driver test_driver/perf_driver.dart --target benchmark/store_cost_test.dart` in `app/`, after `tools/kernel/build.py` | 100k |

The browsers' database runs in `drift_worker.js`, which `tools/data/web.sh` compiles with dart2js for either build of
the app. In a dart2wasm page, package:sqlite3 3.7.1 copies every page between SQLite's memory and the Dart VFS one byte
at a time: 100 pages took 240–310 ms against 1–2 ms in dart2js, so a dart2wasm run measures that copy, not the cipher.

Machine: Linux x64, Intel Core Ultra 7 356H (AES-NI, VAES, 4.7 GHz), 16 threads shared with other jobs (load 20–50),
no TPM; Chrome for Testing 155 and Firefox 158, headless. No phone was available.

## Results

### Database, ms (median of runs) and overhead over plaintext (range)

| Target | Cipher | Bucket table | Window | Fling | Snapshot | Log |
|---|---|---|---|---|---|---|
| VM 100k (5 runs) | plaintext | 1.49 | 0.096 | 9.3 | 3.4 | 29 |
| VM 100k | ChaCha20-Poly1305 | 1.54 (+2–3 %) | 0.119 (+9–28 %) | 10.1 (+1–27 %) | 3.8 (+8–20 %) | 56 (+91–100 %) |
| VM 100k | AES-256-CBC | 1.50 (−1–+1 %) | 0.105 (0–17 %) | 9.6 (−2–+8 %) | 3.9 (+9–26 %) | 51 (+46–91 %) |
| VM 100k | AEGIS-256 | 1.50 (−2–+1 %) | 0.096 (−5–+8 %) | 9.2 (−7–+3 %) | 3.6 (−7–+7 %) | 40 (+24–55 %) |
| VM 1M (3 runs) | plaintext | 1.50 | 0.095 | 8.9 | 3.4 | 32 |
| VM 1M | ChaCha20-Poly1305 | 1.56 (0–4 %) | 0.115 (+16–22 %) | 9.4 (−9–+10 %) | 3.6 (+5–19 %) | 58 (+80–108 %) |
| VM 1M | AEGIS-256 | 1.50 (−4–+6 %) | 0.096 (+1–4 %) | 8.9 (−12–+4 %) | 3.5 (+2–8 %) | 65 (+97–125 %) |
| App, Linux AOT 100k (2 runs) | plaintext | 1.60–1.81 | 0.090–0.093 | 8.8–9.1 | 8.9–12.1 | 47–58 |
| App, Linux AOT | ChaCha20-Poly1305 | 1.76–1.92 (+6–10 %) | 0.115–0.117 (+23–31 %) | 9.7–10.2 (+11–12 %) | 11.4–12.1 (0–29 %) | 84 (+46–80 %) |
| App, Linux AOT | AEGIS-256 | 1.53–1.63 (−16–+2 %) | 0.090–0.093 (−1–0 %) | 8.7–9.5 (−1–+4 %) | 10.5–12.8 (+6–18 %) | 57–78 (+22–36 %) |
| Chrome 155, 30k (5 runs) | plaintext | 1.39 | 0.105 | 10.2 | 4.1 | 21 |
| Chrome 155 | ChaCha20-Poly1305 | 1.65 (+8–25 %) | 0.220 (+96–130 %) | 14.6 (+16–50 %) | 6.0 (+40–50 %) | 68 (+212–254 %) |
| Firefox 158, 30k (4 runs) | plaintext | 1.12 | 0.100 | 10 | 4 | 23 |
| Firefox 158 | ChaCha20-Poly1305 | 1.38 (+21–46 %) | 0.225 (+67–150 %) | 16 (+50–78 %) | 6.5 (+33–75 %) | 73 (+200–240 %) |

The app's times are wall time with no core pinning, and its batches include the commit's `fsync`, so they vary most.
sqlite3mc's WebAssembly build refuses every cipher but ChaCha20 (`aes256cbc` and `aegis` are unknown there). On the
VM at 100k, alternatives in two runs: `sqlcipher` (AES-256-CBC with HMAC-SHA512) window 0.17 ms (+85–94 %) and log
130 ms; AEGIS-128L as AEGIS-256; 16 KiB pages put ChaCha20's window at +43–53 % over plaintext at 16 KiB and about
double the log batch.

### Thumbnails, store open and unlock

| Target | Read p95, ms (plaintext) | Reads/s, 4 in flight (plaintext) | Store open, ms | Argon2id floor, ms | `t` | Unlock, ms |
|---|---|---|---|---|---|---|
| VM | 1.4–4.1 (0.8–3.8) | 1,218–3,272 (2,660–4,923) | 9–20 | 135–185 | 5–6 | 220–397 |
| App, Linux AOT | 10.3–14.4 (11.5–13.4) | 435–708 (494–647) | 15–19 | 158–284 | 3–5 | 208–290 |
| Chrome 155 dart2js | 4.0–4.1 (2.6–5.6) | 768–914 (739–867) | 67–179 | 165–224 | 4–5 | 259–327 |
| Chrome 155 dart2wasm | 3.8–5.9 (2.5–4.3) | 399–823 (657–1,420) | 91–278 | — | — | — |
| Firefox 158 dart2js | 7–11 (5–8) | 333–567 (557–829) | 139–464 | 202–298 | 3–4 | 245–337 |
| Firefox 158 dart2wasm | 3–9 (4–5) | 427–1,053 (661–681) | 111–259 | — | — | — |

A browser's first Argon2id derivation also grows WebAssembly's memory by 64 MiB: it took 230 ms in Chrome against
171–175 ms after it (Firefox 317 against 217–282), so calibration times a second one. In the Linux app under Xvfb
and load 32–45, plaintext reads alone took 11.5–13.4 ms at p95.

## Budgets of design 21 §8

| Budget | Result | Verdict |
|---|---|---|
| Unlock ≤ 600 ms, passcode to first timeline frame, mid-range Android | 208–397 ms on desktops and browsers without `HW` | Unverified on phones: the device lab (M10-02) runs the app benchmark on a Pixel 7a-class phone and a 4 GB low-end Android |
| Database overhead ≤ 10 % on bucket and window queries and sync-apply batches | ChaCha20 costs +9–28 % natively on cold windows, +67–150 % in browsers; random log batches +24–125 % under every cipher | Missed; mitigation: AEGIS-256 where the CPU has AES instructions (≤ 8 % of CPU time on reads and snapshot pages at 100k and 1M); log batches and browsers held to absolute budgets (bucket ≤ 50 ms, window ≤ 8 ms, 1,000 assets ≤ 150 ms), which every target meets |
| T2 read with decryption ≤ 12 ms p95, 320 tiles/s | 1.4–11 ms and 333–3,272/s on the VM and in browsers; 10.3–14.4 ms and 435–708/s in the Linux app | Met on the VM and in browsers; in the Linux app in one run of two, where plaintext reads alone missed design 10's 10 ms; phones unverified |
| Cold start at L1, NFR-PERF-2 | The store opens in 9–20 ms natively, 67–464 ms in browsers (2.5 s budget); the `perf` part measures the app's cold start with it | Met on desktops; phones unverified |

## Hardware binding per platform

| Platform | Secure hardware | `HW` key | Present on | Detected by | Without it |
|---|---|---|---|---|---|
| Android | StrongBox | HMAC-SHA256, `setIsStrongBoxBacked(true)` | Android 9+ with `FEATURE_STRONGBOX_KEYSTORE` (Pixel 3 and later, phones with a secure element) | that feature; `KeyInfo.getSecurityLevel()` | the TEE |
| Android | TEE (KeyMint, Keymaster) | HMAC-SHA256 | Nearly every phone | `getSecurityLevel()` = `TRUSTED_ENVIRONMENT`; before API 31 `isInsideSecureHardware()` | none: the software level (emulators, some devices) |
| iOS, iPadOS | Secure Enclave | P-256 key agreement (`SecureEnclave.P256.KeyAgreement`) | Every device iOS 16 supports | `SecureEnclave.isAvailable` | none: simulators only |
| macOS | Secure Enclave | P-256 key agreement | Apple silicon, Intel with a T2 chip | `SecureEnclave.isAvailable` | none: Intel Macs without a T2 that macOS 13 supports |
| Windows | TPM 2.0 | ECDH P-256 in the Microsoft Platform Crypto Provider (CNG) | Every PC Windows 11 supports; many Windows 10 PCs | opening that provider and creating the key | none: DPAPI wraps L1 |
| Linux | TPM 2.0 | HMAC key (keyed hash) through `/dev/tpmrm0` | Most x86 PCs sold since 2016 (firmware TPMs) | opening `/dev/tpmrm0`, usually only for group `tss`; Flatpak needs the device | none, as on this machine |
| Web | none | — | — | — | none: WebAuthn PRF is a separate factor (1.x) |

## Passcode policy per platform

Design 21 §7 holds: a PIN of at least 6 digits where the table finds secure hardware, else a passphrase of at least 10
characters, or a PIN with server-assisted hardening. It holds only if every guess needs the hardware: crypto v1 binds
`HW` to the parameter set's salt, which does not depend on the passcode, so code that once runs as the app can keep
`HW(salt)` and guess offline. ADR-0090 binds `HW` per guess.

| Platform | PIN (≥ 6 digits) | Passphrase (≥ 10 characters) |
|---|---|---|
| Android | StrongBox or TEE | software keystore |
| iOS, iPadOS | always | — |
| macOS | Apple silicon, T2 | Intel without a T2 |
| Windows | TPM 2.0 | no TPM |
| Linux | a TPM 2.0 the user may open | no TPM, or no access to it |
| Web | with server-assisted hardening only | always otherwise |
