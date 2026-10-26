//! PLB blob envelopes and PLX manifests (docs/dev/crypto-v1.md#plb-blob-envelope): an 88-byte header, then chunks of
//! 2^chunk_log2 plaintext bytes, each ChaCha20-Poly1305 under the payload key with the header as associated data and
//! `index ‖ last` as the nonce, so that tampered, reordered, dropped and appended chunks all fail. Chunk `i` sits at
//! `88 + i·(2^chunk_log2 + 16)`, so a reader holding the header opens any run of chunks alone (seeking in a video).

use crate::keys::{fixed, key_id, prefix};
use crate::proto::kernel::v1::{CallError, DecryptBlobRequest, EncryptBlobRequest};
use crate::{Frame, Keyring, Secret, invalid_request, message_frame, reject};
use chacha20poly1305::{AeadInOut, ChaCha20Poly1305, KeyInit, Nonce, Tag};
use hkdf::Hkdf;
use sha2::Sha256;
use std::mem::take;
use subtle::ConstantTimeEq;
use zeroize::{Zeroize, Zeroizing};

const HEADER: usize = 88;
const TAG: usize = 16;
/// Writers emit 64 KiB chunks.
const CHUNK_LOG2: u8 = 16;

/// The `CallResponse` carrying the `EncryptBlobResponse`.
pub fn encrypt(keyring: &Keyring, r: EncryptBlobRequest) -> Result<Vec<u8>, CallError> {
    Encryptor::new(keyring, r)?.finish(message_frame)
}

/// The `CallResponse` carrying the `DecryptBlobResponse`.
pub fn decrypt(keyring: &Keyring, r: DecryptBlobRequest) -> Result<Vec<u8>, CallError> {
    Decryptor::new(keyring, r)?.finish(message_frame)
}

/// The payload cipher and the commitment: `PRK = HKDF-Extract(salt, object_key)`.
fn keys(key: &[u8; 32], salt: &[u8]) -> (ChaCha20Poly1305, [u8; 32]) {
    let hkdf = Hkdf::<Sha256>::new(Some(salt), key);
    let (mut payload, mut commitment) = (Zeroizing::new([0; 32]), [0; 32]);
    let ok = "HKDF-SHA256 expands 32 bytes";
    hkdf.expand(b"photolib/v1/plb/payload", &mut payload[..]).expect(ok);
    hkdf.expand(b"photolib/v1/plb/commit", &mut commitment).expect(ok);
    (ChaCha20Poly1305::new(&(*payload).into()), commitment)
}

fn nonce(index: u64, last: bool) -> Nonce {
    let mut nonce = [0; 12];
    nonce[3..11].copy_from_slice(&index.to_be_bytes());
    nonce[11] = u8::from(last);
    Nonce::from(nonce)
}

/// Padmé(L): `L` rounded up so that the length leaks only O(log log L) bits.
fn padme(length: u64) -> u64 {
    let e = length.ilog2();
    let mask = (1 << (e - (u32::BITS - e.leading_zeros()))) - 1;
    (length + mask) & !mask
}

/// Seals plaintext that arrives in pieces. It holds back up to one chunk, since only finishing says which is the last.
pub struct Encryptor {
    cipher: ChaCha20Poly1305,
    header: Vec<u8>,
    header_sent: bool,
    buffer: Vec<u8>,
    sealed: u64,
    index: u64,
    padded: bool,
}

impl Encryptor {
    pub fn new(keyring: &Keyring, r: EncryptBlobRequest) -> Result<Self, CallError> {
        let key = keyring.key(r.key, "key")?;
        let kind = u8::try_from(r.kind)
            .ok()
            .filter(|&kind| r.manifest == (kind == 10))
            .ok_or_else(|| invalid_request("kind"))?;
        let salt = fixed::<32>(&r.salt, "salt")?;
        let (cipher, commitment) = keys(key, &salt);
        let typ = if r.manifest { b'X' } else { b'B' };
        let mut header = vec![b'P', b'L', typ, 1, 1, kind, CHUNK_LOG2, u8::from(r.padded)];
        for part in [&key_id(key)[..], &salt, &commitment] {
            header.extend_from_slice(part);
        }
        Ok(Self {
            cipher,
            header,
            header_sent: false,
            buffer: r.plaintext,
            sealed: 0,
            index: 0,
            padded: r.padded,
        })
    }

    pub fn push(&mut self, input: &[u8], frame: Frame) -> Result<Vec<u8>, CallError> {
        self.buffer.extend_from_slice(input);
        Ok(self.seal(false, frame))
    }

    pub fn finish(mut self, frame: Frame) -> Result<Vec<u8>, CallError> {
        if self.padded {
            let length = self.sealed + self.buffer.len() as u64;
            let padded = usize::try_from(padme(length + 1) - self.sealed).map_err(|_| invalid_request("plaintext"))?;
            self.buffer.push(0x80);
            self.buffer.resize(padded, 0);
        }
        Ok(self.seal(true, frame))
    }

    /// The header, if not yet returned, and every chunk known not to be the last; when finishing, the last too.
    fn seal(&mut self, finish: bool, frame: Frame) -> Vec<u8> {
        let (size, rest) = (1 << CHUNK_LOG2, self.buffer.len());
        let full = rest.saturating_sub(1) / size;
        let last = if finish { rest - full * size + TAG } else { 0 };
        let header = if self.header_sent { 0 } else { HEADER };
        let mut out = frame(header + full * (size + TAG) + last);
        if !self.header_sent {
            out.extend_from_slice(&self.header);
            self.header_sent = true;
        }
        let mut start = 0;
        for i in 0..full + usize::from(finish) {
            let last = finish && i == full;
            let end = if last { rest } else { start + size };
            let at = out.len();
            out.extend_from_slice(&self.buffer[start..end]);
            let tag = self
                .cipher
                .encrypt_inout_detached(&nonce(self.index, last), &self.header, (&mut out[at..]).into())
                .expect("a chunk is within ChaCha20-Poly1305's limits");
            out.extend_from_slice(&tag);
            self.index += 1;
            start = end;
        }
        self.sealed += start as u64;
        self.buffer.drain(..start);
        out
    }
}

/// Opens an envelope that arrives in pieces: the request's envelope bytes, then each push.
pub struct Decryptor {
    key: Secret,
    kind: u32,
    typ: u8,
    buffer: Vec<u8>,
    /// The bytes at the start of the buffer already read: the header, once opened.
    read: usize,
    opened: Option<Opened>,
    /// A padded envelope's trailing `0x80 ‖ Z(n)`, which may yet turn out to be its padding: n, while held back.
    held: Option<u64>,
    released: u64,
    /// Random access: the index of the first chunk given, and whether chunks follow the last one given.
    first_chunk: u64,
    more: bool,
}

struct Opened {
    cipher: ChaCha20Poly1305,
    header: Vec<u8>,
    sealed_chunk: usize,
    index: u64,
}

impl Decryptor {
    pub fn new(keyring: &Keyring, r: DecryptBlobRequest) -> Result<Self, CallError> {
        Ok(Self {
            key: Box::new(Zeroizing::new(*keyring.key(r.key, "key")?)),
            kind: r.kind,
            typ: if r.manifest { b'X' } else { b'B' },
            buffer: r.envelope,
            read: 0,
            opened: None,
            held: None,
            released: 0,
            first_chunk: r.first_chunk,
            more: r.more,
        })
    }

    /// Takes more of the envelope and returns the plaintext of every chunk now known not to be the last one.
    pub fn push(&mut self, input: &[u8], frame: Frame) -> Result<Vec<u8>, CallError> {
        self.buffer.extend_from_slice(input);
        if self.opened.is_none() && self.buffer.len() >= HEADER {
            self.open(None)?;
        }
        self.step(false, frame)
    }

    /// Ends the envelope: what is left is its last chunk.
    pub fn finish(mut self, frame: Frame) -> Result<Vec<u8>, CallError> {
        if self.opened.is_none() {
            self.open(Some(self.buffer.len()))?;
        }
        self.step(true, frame)
    }

    /// Checks the header and the commitment; with the whole envelope at hand, its length before the commitment.
    fn open(&mut self, length: Option<usize>) -> Result<(), CallError> {
        let header = &self.buffer;
        prefix(header, self.typ)?;
        if header.len() < HEADER {
            return Err(reject("bad_length"));
        }
        let (kind, chunk_log2, flags) = (header[5], header[6], header[7]);
        if !(16..=22).contains(&chunk_log2) || flags > 1 || (self.typ == b'X') != (kind == 10) {
            return Err(reject("bad_header"));
        }
        if flags == 1 && (self.first_chunk > 0 || self.more) {
            // Padding may span the chunks before the last, so only a whole envelope tells it from data.
            return Err(invalid_request("first_chunk"));
        }
        let sealed_chunk = (1 << chunk_log2) + TAG;
        if let Some(length) = length.filter(|_| !self.more) {
            let body = length - HEADER;
            let (full, rest) = (body / sealed_chunk, body % sealed_chunk);
            let after = full > 0 || self.first_chunk > 0;
            if body == 0 || (1..TAG).contains(&rest) || rest == TAG && after {
                return Err(reject("bad_length"));
            }
        }
        let (cipher, commitment) = keys(&self.key, &header[24..56]);
        self.key.zeroize();
        if !bool::from(commitment.ct_eq(&header[56..HEADER])) {
            return Err(reject("commitment_mismatch"));
        }
        self.opened = Some(Opened {
            cipher,
            header: header[..HEADER].to_vec(),
            sealed_chunk,
            index: self.first_chunk,
        });
        self.read = HEADER;
        Ok(())
    }

    /// Decrypts every chunk known not to be the last and, when finishing, the last one, then checks the content kind.
    /// With more chunks after those given, none is the last. Unpadded, the plaintext goes straight into the step's
    /// output; padded, through [`Self::unpad`].
    fn step(&mut self, finish: bool, frame: Frame) -> Result<Vec<u8>, CallError> {
        let Some(opened) = &mut self.opened else {
            return Ok(frame(0));
        };
        let (start, sealed_chunk) = (take(&mut self.read), opened.sealed_chunk);
        let rest = self.buffer.len() - start;
        let full = rest.saturating_sub(usize::from(!self.more)) / sealed_chunk;
        let ends = finish && !self.more;
        let last = if ends { rest - full * sealed_chunk } else { 0 };
        let short = if ends {
            last < TAG || last == TAG && (opened.index > 0 || full > 0)
        } else {
            finish && rest > full * sealed_chunk
        };
        if short {
            return Err(reject("bad_length"));
        }
        let length = full * (sealed_chunk - TAG) + last.saturating_sub(TAG);
        let padded = opened.header[7] & 1 == 1;
        let mut out = if padded {
            Vec::with_capacity(length)
        } else {
            frame(length)
        };
        for i in 0..full + usize::from(ends) {
            let at = start + i * sealed_chunk;
            let end = (at + sealed_chunk).min(self.buffer.len());
            opened.decrypt(&self.buffer[at..end], ends && i == full, &mut out)?;
        }
        self.buffer.drain(..start + full * sealed_chunk + last);
        if opened.index > self.first_chunk && u32::from(opened.header[5]) != self.kind {
            return Err(reject("wrong_kind"));
        }
        if !padded {
            return Ok(out);
        }
        let plaintext = self.unpad(out, finish)?;
        let mut out = frame(plaintext.len());
        out.extend_from_slice(&plaintext);
        Ok(out)
    }

    /// A padded envelope's plaintext without its padding: all but a trailing `0x80 ‖ 0*`, which is held back, as its
    /// count of zeros, until data shows it is not the padding; at the end it must be, with the Padmé length.
    fn unpad(&mut self, plaintext: Vec<u8>, finish: bool) -> Result<Vec<u8>, CallError> {
        let out = match plaintext.iter().rposition(|&b| b != 0) {
            // Only zeros: they lengthen a held run, or without one are data, the marker being still to come.
            None => match &mut self.held {
                Some(zeros) => {
                    *zeros += plaintext.len() as u64;
                    Vec::new()
                }
                None => plaintext,
            },
            Some(i) => {
                let marker = plaintext[i] == 0x80;
                let end = if marker { i } else { plaintext.len() };
                let zeros = (plaintext.len() - i - 1) as u64;
                let out = match self.held.take() {
                    // Data follows the held run, so the run was data too.
                    Some(run) => {
                        let mut out = vec![0; 1 + usize::try_from(run).map_err(|_| reject("bad_padding"))?];
                        out[0] = 0x80;
                        out.extend_from_slice(&plaintext[..end]);
                        out
                    }
                    None => {
                        let mut out = plaintext;
                        out.truncate(end);
                        out
                    }
                };
                self.held = marker.then_some(zeros);
                out
            }
        };
        self.released += out.len() as u64;
        match self.held {
            Some(zeros) if finish && padme(self.released + 1) != self.released + 1 + zeros => {
                Err(reject("bad_padding"))
            }
            None if finish => Err(reject("bad_padding")),
            _ => Ok(out),
        }
    }
}

impl Opened {
    fn decrypt(&mut self, sealed: &[u8], last: bool, plaintext: &mut Vec<u8>) -> Result<(), CallError> {
        let (ciphertext, tag) = sealed.split_at(sealed.len() - TAG);
        let tag = Tag::from(fixed::<TAG>(tag, "envelope")?);
        let start = plaintext.len();
        plaintext.extend_from_slice(ciphertext);
        self.cipher
            .decrypt_inout_detached(
                &nonce(self.index, last),
                &self.header,
                (&mut plaintext[start..]).into(),
                &tag,
            )
            .map_err(|_| reject("auth_failed"))?;
        self.index += 1;
        Ok(())
    }
}
