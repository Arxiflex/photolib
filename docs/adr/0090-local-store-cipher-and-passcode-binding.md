# ADR-0090 — Local store cipher, Argon2id floor and hardware binding per guess

* **Status**: **Proposed — owner to confirm** (roadmap M0-42; settles what design ADR-0015 left to this spike: the
  cipher, the Argon2id floor and calibration, and the hardware-binding coverage).
* **Requirements**: R-PRIV-3, NFR-PERF-1, NFR-PERF-2. **Design**: 21 §4, §7, §8, ADR-0015, 10 §2.

## Context

Every store is encrypted at L1 with ChaCha20-Poly1305 pages ([ADR-0057](0057-encrypted-local-store.md)). Design 21 §8
allows it 10 % on bucket and window queries and sync-apply batches, 12 ms at p95 and 320 per second for a cached
thumbnail, and 600 ms from passcode to the first timeline frame; it names sqlite3mc's AES-256 as the fallback if
ChaCha20 misses on CPUs with AES instructions. The [spike report](../dev/local-store-spike.md) measured the VM, the
Linux app and Chrome and Firefox; no phone was available. It found:

* On x86 with AES-NI, ChaCha20 costs +9–28 % on a window read with nothing cached, and +67–150 % in browsers.
  AEGIS-256 stays within 8 % of CPU time on reads and snapshot pages at 100k and 1M assets. A batch of 1,000 changes to random
  assets costs +24–125 % under every cipher, as nearly every changed row is on a page of its own, yet takes at most
  90 ms.
* sqlite3mc's `aes256cbc` cipher does not authenticate pages and costs more than AEGIS-256; its `sqlcipher` cipher
  (AES-256-CBC with HMAC-SHA512) costs about 3.5 times ChaCha20's overhead. Its WebAssembly build has ChaCha20 only.
* Thumbnails read with decryption in 1.4–11 ms at p95 and 333–3,272 per second; the store opens in 9–20 ms natively.
* Argon2id at the floor (64 MiB, `t = 3`) takes 135–298 ms on this machine; a browser's first derivation is slower, as
  it grows WebAssembly's memory. An unlock without `HW` takes 208–397 ms.
* Crypto v1 computes `HW` over the parameter set's salt, which does not depend on the passcode: code that once runs as
  the app, on a rooted phone or as malware, can keep `HW(salt)` with the lockbox and guess offline on GPUs.

## Decision

1. **Cipher per database file.** We will use AEGIS-256 (sqlite3mc's `aegis`, `algorithm = aegis-256`, its KDF at the
   minimum `tcost = 1, mcost = 8`, as the page key is uniform) where the CPU reports AES instructions: AES-NI on
   x86-64, the `aes` feature of arm64 (Apple silicon, every iPhone, most Android phones). ChaCha20-Poly1305 stays
   elsewhere: the web, 32-bit Android and ARMv8 without the Crypto Extensions. Each file records its cipher; changing
   it re-keys a copy as design 21 §9 does.
2. **Budgets.** The 10 % budget holds for reads and snapshot pages under AEGIS-256. Random-change batches under every
   cipher and the browsers under ChaCha20 are held to absolute budgets instead: design 10 §2's bucket table in 50 ms and
   window in 8 ms, and 1,000 assets in 150 ms, so that 100k apply within NFR-PERF-5's 15 s. They run in the data
   isolate or the web worker, never on the UI's. `store_cost_test.dart` and `web_test.dart` enforce both. The web
   worker stays dart2js: under dart2wasm, package:sqlite3 copies each page byte by byte.
3. **Argon2id floor.** `m = 64 MiB, t = 3, p = 1` stays crypto v1's device floor. Calibration times a derivation after
   a warm-up one and keeps `t` for at least 250 ms. The floor is not lowered for slow phones.
4. **Hardware binding per guess.** `HW` takes a challenge derived from the Argon2id output instead of the salt, so every
   guess needs the device's secure hardware; on the Secure Enclave and a TPM's ECDH the challenge is hashed to a P-256
   point. M1-24 changes crypto v1's `KEK_pass` and its vectors before any lockbox gets a passcode slot, and calibration
   counts `HW`'s time towards the 250 ms.
5. **Coverage and passcode policy** are the report's tables: StrongBox, else the TEE on Android; the Secure Enclave on
   Apple devices; TPM 2.0 on Windows and, where the user may open `/dev/tpmrm0`, on Linux. A PIN of at least 6 digits
   needs one of them; without (a software keystore, an Intel Mac without a T2, no usable TPM, the web) the passcode is
   a passphrase of at least 10 characters unless server-assisted hardening is on.

## Consequences

* ✅ Reads and snapshot pages stay within 10 % wherever AES instructions exist; every cipher kept authenticates pages.
* ✅ A leaked `HW` output no longer allows offline guessing.
* ⚠️ Two page ciphers to test, and a re-key when a store moves to a device with the other one.
* ⚠️ Phones are unmeasured: the device lab (M10-02) runs `app/benchmark/store_cost_test.dart` on the reference phone and
  a low-end Android. If ChaCha20 beats AEGIS-256 on ARMv8 there, decision 1 changes for phones only; if an unlock
  misses 600 ms, the calibration target, not the floor, moves.
* ⚠️ StrongBox and TPM operations take tens of milliseconds, which decision 4 adds to every unlock.
* Follow-ups: the per-file cipher in the vault; the `HW` challenge and the platform bindings (M1-24); the unlock
  budget in the performance harness once the passcode exists; design ADR-0015 and design 21 §4, §8 to record this.

## Options considered

* **ChaCha20 everywhere**: one cipher, but cold windows miss 10 % on every desktop measured.
* **sqlite3mc's `aes256cbc`**, the AES-256 design 21 names: unauthenticated, and slower than AEGIS-256.
* **`sqlcipher`**: authenticated, but the costliest.
* **AEGIS-128L**: no faster here, and a 128-bit key where crypto v1 uses 256-bit keys.
* **16 KiB pages**: fewer pages, but each cold page decrypts four times the bytes (+43–53 % on a window under ChaCha20)
  and random-change batches double.
* **A lower floor for slow phones** (32 MiB): halves the cost of guessing wherever hardware binding is missing.
* **`HW` over the salt**, as crypto v1 has it: runs beside Argon2id and hides its latency, but leaks as above.
