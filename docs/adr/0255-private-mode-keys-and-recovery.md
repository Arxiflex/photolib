# ADR-0255 — Private-mode keys: the recovery kit, two unlock paths and the upload gate

* **Status**: Accepted — 2026-10-23. The owner kept all five choices of M6-02 (photolib-design#167): three words
  typed again at setup, the whole phrase in a drill every six months, a reset that removes the password path, the
  uploader's own keys at the gate, owner or contributor, and BIP-39's English list in every language
  (photolib-design#724).
* **Requirements**: R-PRIV-1, PRIV-06. **Design**:
  06 §4 and §6,
  research §9.6,
  [crypto spec](../dev/crypto-v1.md#recovery-phrase).

## Context

Key loss is the first support problem of end-to-end encrypted photo apps. Design 06 §6 makes recovery a product
feature: no private upload before two unlock paths exist and the recovery kit was verified, drills every six months,
and copy that says lost keys mean lost photos. The crypto spec fixed the wraps (`KEK_pw`, `KEK_rec` over the AMK) but
not the recovery phrase, where the server keeps the keys, how the kit is proven, or how the password path relates to
OPAQUE sign-in. Device approval, passkeys, trusted contacts and Shamir kits are M6-03's.

## Decision

* **Recovery phrase**: the 32 bytes of recovery entropy as their BIP-39 English encoding, 24 words; the kernel writes
  it (`RecoveryPhrase`) and reads it as typed, in any case and whitespace (`RecoveryKey` gives `KEK_rec`), naming an
  unknown word's position. One word list in every language, as wallets do.
* **The server keeps, never opens**: `KeyService` stores the identity log's genesis (`user_keys`), the identity
  seeds wrapped under the AMK, and one AMK wrap per unlock path (`account_keys`, `unlock_paths`). It checks what the
  headers say: wrapped types, one AMK for every wrap, the caller's own identity log, Argon2id parameters within the
  account policy.
* **Two paths now**: the account's password, an OPAQUE credential (the vault passphrase of an account that signs in
  with OIDC, set with `StartPasswordSetup` from its session), and the recovery kit. A password path needs that
  password; the app checks it with OPAQUE before wrapping, so a typo makes no dead path.
* **The password path's wrap is released only by a password sign-in** (`FinishLogin`, `FinishSecondFactor`): a
  stolen session cannot fetch it to guess offline. A new password replaces the wrap with the one its client sends or
  removes it; a reset with a setup token removes it and says so first.
* **Verification**: at setup the person types three random words of the kit again, which the app checks against the
  phrase it still holds; then `VerifyRecoveryKit` names the kit by `key_id(KEK_rec)`. A drill, due six months after
  the last verification, takes the whole phrase, opens the recovery wrap with it and verifies again. A new kit is
  unverified.
* **The gate**: `/upload` refuses a private library's upload (`keys.recovery_incomplete`) unless the uploader, owner or
  contributor, has two unlock paths and a verified kit.

## Consequences

* No client can upload privately before the account is recoverable, whatever it does; M6-04 builds on `ready`.
* The server cannot tell a client that skipped the typing from one that did: the check protects people from
  themselves, not from a modified app.
* A reset makes the account unready until it unlocks with the kit and wraps the AMK under the new password again.
* Later: a printable kit with a QR code and scanning it, drills after crypto-touching updates, replacing a lost kit and
  "is this your last way in?" checks (M6-03 adds the paths whose removal they guard).

## Options considered

* **Retyping the whole phrase at setup**: proves more, but most people stop there; three words match research §9.6.
* **Drills of two words**: the app would have to keep the phrase, which outlives an AMK rotation; the whole phrase
  also proves the kit still opens the AMK.
* **Any session reads every wrap**: simpler, but turns a stolen session into offline guessing of the password.
* **Keeping the password wrap after a reset**: the new password does not open it, so it would count as a path that
  is not one.
