//! TOTP (RFC 6238) and recovery codes, the second factors besides passkeys (M2-05, ADR-0088).

use ring::hmac::{HMAC_SHA1_FOR_LEGACY_USE_ONLY, Key, sign};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

/// The six-digit code of `secret` at time step `step` (30 seconds since the epoch): HMAC-SHA1, as authenticator apps
/// compute it.
pub fn code(secret: &[u8], step: u64) -> String {
    let mac = sign(&Key::new(HMAC_SHA1_FOR_LEGACY_USE_ONLY, secret), &step.to_be_bytes());
    let mac = mac.as_ref();
    let at = usize::from(mac[19] & 15);
    let value = u32::from_be_bytes(mac[at..at + 4].try_into().unwrap()) & 0x7fff_ffff;
    format!("{:06}", value % 1_000_000)
}

/// `bytes` in RFC 4648 base32 without padding, as authenticator apps take a secret.
pub fn base32(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let bits = bytes.len() * 8;
    (0..bits.div_ceil(5))
        .map(|chunk| {
            let value = (0..5).fold(0, |value, bit| {
                let at = chunk * 5 + bit;
                let set = at < bits && bytes[at / 8] & (0x80 >> (at % 8)) != 0;
                value << 1 | usize::from(set)
            });
            char::from(ALPHABET[value])
        })
        .collect()
}

/// The step within one of `now` whose code `typed` is, spaces aside.
pub fn matching_step(secret: &[u8], typed: &str, now: u64) -> Option<u64> {
    let typed: String = typed.chars().filter(|c| *c != ' ').collect();
    if typed.len() != 6 || !typed.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    [now.saturating_sub(1), now, now + 1]
        .into_iter()
        .find(|&step| bool::from(code(secret, step).as_bytes().ct_eq(typed.as_bytes())))
}

/// RFC 3986 percent-encoding of all but the unreserved characters.
fn escape(text: &str) -> String {
    text.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => char::from(b).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// The otpauth URI an authenticator app reads from a QR code.
pub fn uri(issuer: &str, account: &str, secret: &[u8]) -> String {
    let (issuer, account) = (escape(issuer), escape(account));
    format!(
        "otpauth://totp/{issuer}:{account}?secret={}&issuer={issuer}&algorithm=SHA1&digits=6&period=30",
        base32(secret)
    )
}

/// Ten new recovery codes of 80 random bits each, as `abcd-efgh-ijkl-mnop`.
pub fn recovery_codes() -> Vec<String> {
    (0..10)
        .map(|_| {
            let mut bytes = [0; 10];
            getrandom::fill(&mut bytes).expect("the operating system provides random numbers");
            let code = base32(&bytes).to_lowercase();
            [&code[..4], &code[4..8], &code[8..12], &code[12..]].join("-")
        })
        .collect()
}

/// What the database keeps of a recovery code, however it was typed; none for what cannot be one.
pub fn recovery_hash(code: &str) -> Option<Vec<u8>> {
    let code: String = code
        .chars()
        .filter(|c| !matches!(c, '-' | ' '))
        .collect::<String>()
        .to_lowercase();
    let valid = code.len() == 16
        && code
            .bytes()
            .all(|b| b.is_ascii_lowercase() || (b'2'..=b'7').contains(&b));
    valid.then(|| Sha256::digest(code.as_bytes()).to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_match_the_sha1_vectors_of_rfc_6238_appendix_b() {
        let secret = b"12345678901234567890";
        // The vectors' eight digits, of which authenticator apps show the last six.
        for (time, code8) in [
            (59, "94287082"),
            (1_111_111_109, "07081804"),
            (1_111_111_111, "14050471"),
            (1_234_567_890, "89005924"),
            (2_000_000_000, "69279037"),
            (20_000_000_000, "65353130"),
        ] {
            assert_eq!(code(secret, time / 30), code8[2..], "at {time}");
        }
        assert_eq!(base32(secret), "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
        assert_eq!(base32(b"f"), "MY");
        assert_eq!(base32(b"fooba"), "MZXW6YTB");
        assert_eq!(base32(b"foobar"), "MZXW6YTBOI");
    }

    #[test]
    fn a_code_counts_for_its_step_and_one_either_side_and_nothing_else_does() {
        let secret = b"12345678901234567890";
        let now = 1_111_111_111 / 30;
        for step in [now - 1, now, now + 1] {
            assert_eq!(matching_step(secret, &code(secret, step), now), Some(step));
        }
        for step in [now - 2, now + 2, 0] {
            assert_eq!(matching_step(secret, &code(secret, step), now), None);
        }
        assert_eq!(matching_step(secret, " 050 471 ", now), Some(now), "as apps show it");
        for wrong in ["", "50471", "0504710", "05047a", "０５０４７１", "-50471"] {
            assert_eq!(matching_step(secret, wrong, now), None, "{wrong}");
        }
    }

    #[test]
    fn the_uri_names_the_issuer_and_the_account_for_authenticator_apps() {
        assert_eq!(
            uri("Photolib", "ann@photos.example.com", b"12345678901234567890"),
            "otpauth://totp/Photolib:ann%40photos.example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ\
             &issuer=Photolib&algorithm=SHA1&digits=6&period=30"
        );
        assert!(uri("Photo lib", "a:b", b"x").starts_with("otpauth://totp/Photo%20lib:a%3Ab?"));
    }

    #[test]
    fn recovery_codes_are_ten_distinct_80_bit_codes_that_count_however_they_are_typed() {
        let codes = recovery_codes();
        assert_eq!(codes.len(), 10);
        assert_eq!(codes.iter().collect::<std::collections::HashSet<_>>().len(), 10);
        for code in &codes {
            let groups: Vec<&str> = code.split('-').collect();
            assert!(
                groups.len() == 4
                    && groups.iter().all(|group| group.len() == 4
                        && group
                            .bytes()
                            .all(|b| b.is_ascii_lowercase() || (b'2'..=b'7').contains(&b))),
                "{code}"
            );
        }
        let hash = recovery_hash(&codes[0]).unwrap();
        assert_eq!(hash.len(), 32);
        assert_eq!(
            recovery_hash(&codes[0].to_uppercase().replace('-', " ")),
            Some(hash.clone())
        );
        assert_ne!(recovery_hash(&codes[1]), Some(hash));
        for wrong in ["", "abcd-efgh-ijkl", "abcd-efgh-ijkl-mno1", "abcd-efgh-ijkl-mnop-q"] {
            assert_eq!(recovery_hash(wrong), None, "{wrong}");
        }
    }
}
