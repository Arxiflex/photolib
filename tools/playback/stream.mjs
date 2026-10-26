// The two-hour video of the playback benchmark, built from one encoded 4 s segment and read lazily by byte range
// (2.3 GB files that are never stored): an original and a CMAF stream rendition, and their PLB envelopes.
import { createCipheriv, hkdfSync } from 'node:crypto';

const u8 = (n) => Buffer.from([n]);
const u16 = (n) => Buffer.from([n >> 8, n & 255]);
const u32s = (values) => {
  const b = Buffer.alloc(4 * values.length);
  values.forEach((v, i) => b.writeUInt32BE(v, 4 * i));
  return b;
};
const u32 = (n) => u32s([n]);
const box = (type, ...body) => {
  const payload = Buffer.concat(body.map((b) => (typeof b === 'string' ? Buffer.from(b, 'latin1') : b)));
  return Buffer.concat([u32(8 + payload.length), Buffer.from(type, 'latin1'), payload]);
};
const full = (type, version, flags, ...body) => box(type, u8(version), u32(flags).subarray(1), ...body);
const zeros = (n) => Buffer.alloc(n);
const matrix = Buffer.concat([0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000].map(u32));

const codec = 'vp09.00.30.08';

/// The moov of one VP9 track `total` ms long with these sample tables (empty ones for fragments), then `extra`.
function moov({ width, height }, total, tables, ...extra) {
  const entry = box(
    'vp09',
    zeros(6), u16(1), zeros(16), u16(width), u16(height), u32(0x480000), u32(0x480000), zeros(4), u16(1), zeros(32),
    u16(0x18), u16(0xffff),
    // VP9 profile 0, level 3, 8-bit 4:2:0, BT.709.
    full('vpcC', 1, 0, u8(0), u8(30), u8(0x82), u8(1), u8(1), u8(1), u16(0)),
  );
  return box(
    'moov',
    full('mvhd', 0, 0, zeros(8), u32(1000), u32(total), u32(0x10000), u16(0x100), zeros(10), matrix, zeros(24), u32(2)),
    box(
      'trak',
      full('tkhd', 0, 3, zeros(8), u32(1), zeros(4), u32(total), zeros(16), matrix, u32(width << 16), u32(height << 16)),
      box(
        'mdia',
        full('mdhd', 0, 0, zeros(8), u32(1000), u32(total), u16(0x55c4), u16(0)),
        full('hdlr', 0, 0, zeros(4), 'vide', zeros(12), 'video\0'),
        box(
          'minf',
          full('vmhd', 0, 1, zeros(8)),
          box('dinf', full('dref', 0, 0, u32(1), full('url ', 0, 1))),
          box('stbl', full('stsd', 0, 0, u32(1), entry), ...tables),
        ),
      ),
    ),
    ...extra,
  );
}

/// A file of `head` followed by `count` repeats of `body`, read lazily: `part(k)` is repeat k.
function repeated(head, count, size, part) {
  let cached = [-1];
  return {
    size: head.length + count * size,
    read(start, end) {
      const parts = [];
      for (let at = start; at < end; ) {
        if (at < head.length) {
          parts.push(head.subarray(at, Math.min(end, head.length)));
          at = Math.min(end, head.length);
          continue;
        }
        const k = Math.floor((at - head.length) / size);
        const base = head.length + k * size;
        if (cached[0] !== k) cached = [k, part(k)];
        const to = Math.min(end, base + size);
        parts.push(cached[1].subarray(at - base, to - base));
        at = to;
      }
      return Buffer.concat(parts);
    },
  };
}

/// frames: one 4 s segment's encoded frames, each {key, data}, of `frame` ms, repeated `count` times. An original is
/// what a camera writes: one mdat, its sample tables in a moov ahead of it (faststart), so a progressive player seeks
/// with one request.
export function original(frames, video, { frame = 40, count = 1800 } = {}) {
  const n = frames.length;
  const media = Buffer.concat(frames.map((f) => f.data));
  const each = (f) => Array.from({ length: count }, (_, k) => f(k)).flat();
  const keys = each((k) => frames.flatMap((f, i) => (f.key ? [k * n + i + 1] : [])));
  const tables = (offset) => [
    full('stts', 0, 0, u32s([1, count * n, frame])),
    full('stss', 0, 0, u32s([keys.length, ...keys])),
    full('stsc', 0, 0, u32s([1, 1, n, 1])),
    full('stsz', 0, 0, u32s([0, count * n, ...each(() => frames.map((f) => f.data.length))])),
    full('stco', 0, 0, u32s([count, ...each((k) => [offset + k * media.length])])),
  ];
  const ftyp = box('ftyp', 'isom', u32(0x200), 'isom', 'iso2', 'mp41');
  const size = ftyp.length + moov(video, count * n * frame, tables(0)).length + 8;
  const head = Buffer.concat([ftyp, moov(video, count * n * frame, tables(size)), u32(8 + count * media.length), Buffer.from('mdat')]);
  return repeated(head, count, media.length, () => media);
}

/// The stream rendition of the same frames: CMAF, 2 s closed GOPs in 4 s fragments (design 08 §5). Players find
/// fragments in the stream index, so it has no `sidx`.
export function stream(frames, video, { frame = 40, count = 1800 } = {}) {
  const duration = frames.length * frame;
  const total = count * duration;
  const sample = (i) => (frames[i].key ? 0x02000000 : 0x01010000);
  const empty = [...['stts', 'stsc', 'stco'].map((type) => full(type, 0, 0, u32(0))), full('stsz', 0, 0, u32(0), u32(0))];
  const mvex = box('mvex', full('mehd', 0, 0, u32(total)), full('trex', 0, 0, u32(1), u32(1), u32(frame), u32(0), u32(0)));
  const init = Buffer.concat([box('ftyp', 'iso6', u32(0), 'iso6', 'cmfc', 'mp41'), moov(video, total, empty, mvex)]);
  const media = Buffer.concat(frames.map((f) => f.data));
  const moof = (k, offset) =>
    box(
      'moof',
      full('mfhd', 0, 0, u32(k + 1)),
      box(
        'traf',
        full('tfhd', 0, 0x020000, u32(1)),
        full('tfdt', 1, 0, u32(0), u32(k * duration)),
        full('trun', 0, 0x000701, u32s([frames.length, offset, ...frames.flatMap((f, i) => [frame, f.data.length, sample(i)])])),
      ),
    );
  const moofSize = moof(0, 0).length;
  const segmentSize = moofSize + 8 + media.length;
  return {
    ...repeated(init, count, segmentSize, (k) => Buffer.concat([moof(k, moofSize + 8), u32(8 + media.length), Buffer.from('mdat'), media])),
    // What the encrypted stream index carries (design 08 §6.2): codec, duration, init range and segment table.
    index: { codec, duration: total / 1000, init: init.length, segment: segmentSize, seconds: duration / 1000, count },
  };
}

const HEADER = 88;
const CHUNK = 1 << 16;

/// The PLB envelope of `plain` (docs/dev/crypto-v1.md; content kind 1 original, 6 stream) under `key`, unpadded and
/// sealed chunk by chunk as it is read.
export function seal(plain, key, kind) {
  const salt = Buffer.alloc(32, 0x5a);
  const derive = (salt, label, n = 32) => Buffer.from(hkdfSync('sha256', key, salt, `photolib/v1/${label}`, n));
  const header = Buffer.concat([Buffer.from('PLB'), Buffer.from([1, 1, kind, 16, 0]), derive('', 'key-id', 16), salt, derive(salt, 'plb/commit')]);
  const payload = derive(salt, 'plb/payload');
  const chunks = Math.max(1, Math.ceil(plain.size / CHUNK));
  const sealed = (i) => {
    const nonce = zeros(12);
    nonce.writeBigUInt64BE(BigInt(i), 3);
    nonce[11] = i === chunks - 1 ? 1 : 0;
    const text = plain.read(i * CHUNK, Math.min((i + 1) * CHUNK, plain.size));
    const cipher = createCipheriv('chacha20-poly1305', payload, nonce, { authTagLength: 16 });
    cipher.setAAD(header, { plaintextLength: text.length });
    return Buffer.concat([cipher.update(text), cipher.final(), cipher.getAuthTag()]);
  };
  return {
    size: HEADER + plain.size + 16 * chunks,
    read(start, end) {
      const parts = [header.subarray(Math.min(start, HEADER), Math.min(end, HEADER))];
      for (let i = Math.max(0, Math.floor((start - HEADER) / (CHUNK + 16))); HEADER + i * (CHUNK + 16) < end; i++) {
        const base = HEADER + i * (CHUNK + 16);
        parts.push(sealed(i).subarray(Math.max(0, start - base), end - base));
      }
      return Buffer.concat(parts);
    },
  };
}
