//! BLAKE3 content hashes: the identity of every original (photolib-design docs/07 §8).

use std::{fmt, path::Path, str::FromStr};

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Hash(pub [u8; 32]);

impl Hash {
    pub fn of(bytes: &[u8]) -> Hash {
        Hash(*blake3::hash(bytes).as_bytes())
    }

    /// Hashes a file in one streaming pass; returns the hash and the size.
    pub fn of_file(path: &Path) -> std::io::Result<(Hash, u64)> {
        let mut hasher = blake3::Hasher::new();
        let size = std::io::copy(&mut std::fs::File::open(path)?, &mut hasher)?;
        Ok((Hash(*hasher.finalize().as_bytes()), size))
    }
}

impl From<blake3::Hash> for Hash {
    fn from(hash: blake3::Hash) -> Hash {
        Hash(*hash.as_bytes())
    }
}

impl fmt::Display for Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.iter().try_for_each(|byte| write!(f, "{byte:02x}"))
    }
}

impl fmt::Debug for Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "blake3:{self}")
    }
}

impl FromStr for Hash {
    type Err = String;

    fn from_str(hex: &str) -> Result<Hash, String> {
        let bad = || format!("not a BLAKE3 hash in lower-case hex: {hex:?}");
        if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
            return Err(bad());
        }
        let mut out = [0u8; 32];
        for (i, byte) in out.iter_mut().enumerate() {
            *byte = u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).map_err(|_| bad())?;
        }
        Ok(Hash(out))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hashes_match_the_blake3_reference_and_round_trip_as_hex() {
        let empty = Hash::of(b"");
        assert_eq!(
            empty.to_string(),
            "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
        );
        assert_eq!(empty.to_string().parse::<Hash>(), Ok(empty));
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("f");
        let bytes = vec![7u8; 3 * 1024 * 1024 + 1];
        std::fs::write(&path, &bytes).unwrap();
        assert_eq!(Hash::of_file(&path).unwrap(), (Hash::of(&bytes), bytes.len() as u64));
    }

    #[test]
    fn malformed_hex_is_refused() {
        for bad in ["", "AF13", &"g".repeat(64), &"A".repeat(64), &"0".repeat(63)] {
            assert!(bad.parse::<Hash>().is_err(), "{bad:?}");
        }
    }
}
