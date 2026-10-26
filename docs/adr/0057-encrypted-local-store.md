# ADR-0057 — Encrypted local store: page keys leave the kernel, keystore keys through secure storage

* **Status**: Accepted — 2026-10-17 (roadmap M0-41; implements design ADR-0015 at level L1). The owner answered
  photolib-design#378,
  whose questions named this ADR 0044: page keys, secure storage, Linux without a keyring and the kernel from source
  are kept; a store whose keystore key is gone is rebuilt, and a local recovery code is offered at L1 too. Asked
  whether that answer or ADR-0154's passphrase applies on Linux without a Secret Service, the owner kept both
  (photolib-design#691,
  2026-10-23).
* **Requirements**: R-PRIV-3, NFR-SEC-3. **Design**: 21 §3–§5, §9, 10 §1.3, §2, ADR-0015.

## Context

Every install encrypts what it stores under a device data key (DDK) wrapped in a lockbox under a non-exportable
keystore key. The kernel holds keys only as handles, but SQLite3MultipleCiphers needs a database's page key as bytes;
in WASM it encrypts only through its `multipleciphers-<vfs>` VFS, which drift's stock web worker cannot open; no
kernel release is pinned for apps yet (ADR-0026); and design 10 names a `secure_store` plugin on six targets that does
not exist.

## Decision

* **Page keys** `HKDF(DDK, …/local/db ‖ f)` leave the kernel through one call, `DatabaseKey`; no other response
  carries key material. `f` is the first 16 bytes of SHA-256 of the database's name; its pre-migration backups share
  its key (sqlite3mc salts each file). sqlite3mc uses ChaCha20-Poly1305 with one PBKDF2 round, as the key is already
  uniform.
* **Keying**: every database opens with migrations off in drift, so the first statements on the connection set the
  key; then the schema version is read and drift's migrations run. Natively the data isolate does this; on the web a
  worker of ours opens the database through that VFS, in OPFS, else IndexedDB, one per database and origin (Web
  Locks), and the page sends the key over drift's protocol. `photolib_data` exports only `Vault.openReplica`, and
  `app/tool/single_writer_lint.dart` fails on any other opener and on an opener that does not key.
* **Keystore keys** (`KS_dev` for the lockbox's slot 1, `KS_bg` for class B) are 32 random bytes that the platform
  keystore releases: `flutter_secure_storage` on Android (Keystore-encrypted), iOS and macOS (Keychain, after first
  unlock, this device only), Windows (DPAPI) and Linux (Secret Service). On the web a non-extractable WebCrypto HMAC
  key in IndexedDB computes them, until the hardware-bound keys of M0-42 and M1-24. Without a keystore the store does
  not open: there is no plaintext fallback (with M1-24 a passphrase at launch becomes the factor, design 21 §7; the
  headless node of M6-11 picks its own key source). On Linux a store stays shut, the keyrings named (gnome-keyring,
  KWallet, KeePassXC), while a Secret Service that holds its keys is away; one made without a Secret Service keeps
  them under ADR-0154's passphrase.
* **A keystore that lost its key** (an OEM Keystore wipe, a keychain reset, a changed keyring password, a plugin bug)
  never leaves a dead app. When the keystore answers but has no `KS_dev`, or one that does not open slot 1, a lockbox
  with a local recovery code (slot 4, factor 4) waits for the code (`RecoveryNeeded`) or a reset; any other store is
  erased and made anew (`Vault.rebuilt`): replicas sync again, caches refill, and the library says what was lost. A
  keystore that fails to answer changes nothing.
* **Local recovery code at L1** (design 21 §6): 32 random bytes shown as 24 words of BIP-39's English list;
  `KEK_rec = HKDF(entropy, …/kek/recovery)` wraps the DDK in slot 4. It is optional: the library offers it while
  anything exists only on this device (`localOnlyCount`: unsent changes and rows no server confirmed), *Later* asks
  again in 30 days, and Settings makes one at any time, replacing the last. Entering it opens slot 4 and re-seals
  slot 1 under a new `KS_dev`; `vault_test.dart`'s recovery drill deletes the keystore key and recovers with it.
* **Classes and files**: class C objects are PLB envelopes (kind 11) under `HKDF(CacheKey, …/local/object ‖ o)`,
  class B ones under `HKDF(KS_bg, …/local/object ‖ o)`; `o` is the first 16 bytes of SHA-256 of the object's name.
  Locking drops every handle, class B ones included, and closes every connection; class B work while locked imports
  `KS_bg` for that call only.
* **Alpha stores**: a database whose first bytes are the plaintext SQLite header is copied with `VACUUM INTO`,
  re-keyed, verified (`quick_check` and every table's row count) and moved over the plaintext file; the store's files
  are dropped, as caches are rebuilt.
* **Kernel for the app**: until `kernel-v0.1.0` is pinned, the app's build hook takes the kernel from
  `app/build/kernel/`, which `tools/kernel/build.py` writes (the gate and `tools/smoke.sh` run it), and its web
  build loads the module that `tools/kernel/wasm.sh` writes into `app/web/kernel/`.

## Consequences

* ✅ No plaintext database, cache or file of Photolib's at rest; locking leaves no key handle or open database.
* ⚠️ A page key is in sqlite3mc's memory, and as text in Dart's heap until collected, while its database is open.
* ⚠️ Until a kernel release is pinned (at M10, when distribution starts), building the app needs Rust. Linux without
  a Secret Service keeps the keystore keys under a passphrase instead (ADR-0154).
* ⚠️ Without a recovery code, a lost keystore key loses what existed only on the device; the recovery code is as
  strong as where the user keeps it.
* Follow-ups: hardware-bound keys and the passcode (M0-42, M1-24); large offline copies through the worker pool; the
  macOS Keychain entitlement of signed, sandboxed builds, checked in the test phase.

## Options considered

* **Random page keys sealed as PLB blobs**: no kernel change, but it hides a key export behind a decryption and
  departs from the specified derivation.
* **sqlite3mc linked into the kernel**: the kernel stays pure and does no I/O (ADR-0004).
* **Drift's shared web worker**: tabs would share one database, but it opens it only through the default VFS, which
  sqlite3mc does not encrypt.
* **A key file next to the store on Linux without a keyring**: readable from any copy of the store.
* **A dead store when the keystore key is gone** (the provisional behaviour): the app could not start until erased.
* **A recovery code only with a passcode** (design 21 §6 before the owner's answer): local-only data at L1 would
  have had no way back.
* **Our own `secure_store` plugin now**: five native implementations that this machine cannot test; it can replace
  `flutter_secure_storage` behind the same interface with M1-24's hardware-bound keys.
