//! The recovery phrase (docs/dev/crypto-v1.md#recovery-phrase): the BIP-39 English encoding of the 32 bytes of
//! recovery entropy, and `KEK_rec`, which they give.

use crate::keys::{LABEL, fixed, hkdf};
use crate::proto::kernel::v1::{
    CallError, CallErrorCode, KeyResponse, RecoveryKeyRequest, RecoveryPhraseRequest, RecoveryPhraseResponse,
};
use crate::{Keyring, error, reject};
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, Zeroizing};

/// BIP-39's English list, one word a line.
const WORDS: &str = include_str!("bip39-english.txt");
const COUNT: usize = 24;

/// The bits of `n`, its `width` lowest, most significant first.
fn bits(n: usize, width: u32) -> impl Iterator<Item = bool> {
    (0..width).rev().map(move |shift| n.wrapping_shr(shift) & 1 == 1)
}

fn number(bits: &[bool]) -> usize {
    bits.iter().fold(0, |n, &bit| n.wrapping_shl(1) | usize::from(bit))
}

pub(crate) fn phrase(mut r: RecoveryPhraseRequest) -> Result<RecoveryPhraseResponse, CallError> {
    let entropy = Zeroizing::new(fixed::<32>(&r.entropy, "entropy")?);
    r.entropy.zeroize();
    let checksum = Sha256::digest(*entropy);
    let bytes = entropy.iter().chain(checksum.iter().take(1));
    let bits = Zeroizing::new(bytes.flat_map(|&byte| bits(byte.into(), 8)).collect::<Vec<_>>());
    let words: Vec<&str> = WORDS.lines().collect();
    let phrase = bits
        .chunks(11)
        .map(|index| words.get(number(index)).copied().unwrap_or_default());
    Ok(RecoveryPhraseResponse {
        phrase: phrase.collect::<Vec<_>>().join(" "),
    })
}

/// `KEK_rec` of a phrase as typed. Every word is compared with the whole list, so the time taken says nothing of
/// which words it holds.
pub(crate) fn key(keyring: &mut Keyring, mut r: RecoveryKeyRequest) -> Result<KeyResponse, CallError> {
    let phrase = Zeroizing::new(std::mem::take(&mut r.phrase));
    let typed: Vec<&str> = phrase.split_ascii_whitespace().collect();
    if typed.len() != COUNT {
        return Err(reject("bad_length"));
    }
    let mut bits = Zeroizing::new(Vec::with_capacity(11 * COUNT));
    for (position, word) in (1_usize..).zip(&typed) {
        let found = WORDS.lines().zip(0..).fold(None, |found, (listed, index)| {
            if listed.eq_ignore_ascii_case(word) {
                Some(index)
            } else {
                found
            }
        });
        let index = found.ok_or_else(|| {
            let position = position.to_string();
            error(
                CallErrorCode::InvalidInput,
                &[("reason", "unknown_word"), ("word", &position)],
            )
        })?;
        bits.extend(self::bits(index, 11));
    }
    // `to_le_bytes()[0]` is the lowest byte whatever usize's width: 4 bytes on wasm32.
    let bytes = Zeroizing::new(
        bits.chunks(8)
            .map(|byte| number(byte).to_le_bytes()[0])
            .collect::<Vec<u8>>(),
    );
    match bytes.split_at_checked(32) {
        Some((entropy, checksum)) if Sha256::digest(entropy).first() == checksum.first() => {
            Ok(keyring.insert(hkdf(entropy, &[LABEL, b"kek/recovery"])))
        }
        _ => Err(reject("bad_checksum")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_word_list_is_bip39s() {
        let sha256 = [
            0x2f, 0x5e, 0xed, 0x53, 0xa4, 0x72, 0x7b, 0x4b, 0xf8, 0x88, 0x0d, 0x8f, 0x3f, 0x19, 0x9e, 0xfc, 0x90, 0xe5,
            0x85, 0x03, 0x64, 0x6d, 0x9f, 0xf8, 0xef, 0xf3, 0xa2, 0xed, 0x3b, 0x24, 0xdb, 0xda,
        ];
        assert_eq!(Sha256::digest(WORDS)[..], sha256);
        assert_eq!(WORDS.lines().count(), 2048);
    }
}
