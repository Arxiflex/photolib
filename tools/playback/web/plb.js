// PLB envelopes read by plaintext byte range over HTTP Range requests (design 08 §6.2–§6.4), for the Service Worker
// and the MSE worker. Ciphertext is fetched in whole 1 MiB windows, so the server never learns where a range or a
// segment starts, and every chunk is authenticated by the kernel before a byte of it is returned.
const HEADER = 88;
const IMPORT_KEY = 5;
const DECRYPT_BLOB = 11;

/// Opens the envelope at `url`, of content kind `kind` (1 original, 6 stream), under the 32 bytes of `secret` with a
/// keyring of the kernel's WebAssembly build.
export async function envelope(url, secret, kind, keyring) {
  // KeyResponse {key = 1, key_id = 2}: the handle requests name the key by.
  const key = varint(call(keyring, IMPORT_KEY, [[0x0a], encode(secret.length), secret]).subarray(1))[0];
  const head = await fetch(url, { headers: { range: `bytes=0-${HEADER - 1}` } });
  const header = new Uint8Array(await head.arrayBuffer());
  const total = Number(head.headers.get('content-range').split('/')[1]);
  const chunk = 2 ** header[6];
  const sealed = chunk + 16;
  const chunks = Math.ceil((total - HEADER) / sealed);
  const size = total - HEADER - 16 * chunks;
  const span = Math.max(1 << 20, chunk);
  const windows = new Map();

  async function load(w) {
    const first = (w * span) / chunk;
    const last = Math.ceil(Math.min((w + 1) * span, size) / chunk) - 1;
    const from = HEADER + first * sealed;
    const to = Math.min(HEADER + (last + 1) * sealed, total);
    const response = await fetch(url, { headers: { range: `bytes=${from}-${to - 1}` } });
    const bytes = new Uint8Array(await response.arrayBuffer());
    // DecryptBlobRequest {key = 1, kind = 2, envelope = 4, first_chunk = 5, more = 6}.
    const parts = [[0x08], encode(key), [0x10], encode(kind), [0x22], encode(HEADER + bytes.length), header, bytes];
    parts.push([0x28], encode(first), last < chunks - 1 ? [0x30, 1] : []);
    return field1(call(keyring, DECRYPT_BLOB, parts)) ?? new Uint8Array();
  }

  return {
    size,
    window: span,
    /// The plaintext bytes [start, end).
    async read(start, end) {
      const out = new Uint8Array(end - start);
      for (let w = Math.floor(start / span); w * span < end; w++) {
        if (!windows.has(w)) windows.set(w, load(w));
        // The last few windows stay: neighbouring reads share them.
        if (windows.size > 4) windows.delete(windows.keys().next().value);
        const plain = await windows.get(w);
        const from = Math.max(start, w * span);
        out.set(plain.subarray(from - w * span, Math.min(end, (w + 1) * span) - w * span), from - start);
      }
      return out;
    },
  };
}

/// The response of the kernel function `method` to the request made of `parts`. Messages are encoded by hand: no
/// protobuf runtime in workers, which cannot use the page's import map.
function call(keyring, method, parts) {
  const request = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((at, p) => (request.set(p, at), at + p.length), 0);
  const response = field1(keyring.call(method, request));
  if (!response) throw new Error(`kernel method ${method} failed`);
  return response;
}

function encode(n) {
  const out = [];
  for (; n >= 0x80; n = Math.floor(n / 0x80)) out.push((n % 0x80) | 0x80);
  return [...out, n];
}

/// The varint at the start of `bytes` and the bytes after it.
function varint(bytes) {
  let [at, n] = [0, 0];
  for (let scale = 1; ; scale *= 0x80) {
    const byte = bytes[at++];
    n += (byte & 0x7f) * scale;
    if (byte < 0x80) return [n, bytes.subarray(at)];
  }
}

/// The bytes of field 1 when a message starts with it: CallResponse.response, DecryptBlobResponse.plaintext.
function field1(message) {
  if (message[0] !== 0x0a) return null;
  const [length, rest] = varint(message.subarray(1));
  return rest.subarray(0, length);
}
