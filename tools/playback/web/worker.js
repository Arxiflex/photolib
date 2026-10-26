// The MSE path's decrypting worker (the role of hls.js's custom loader): reads plaintext ranges of the encrypted
// stream off the page's thread.
import init, { newKeyring } from '/kernel/photolib_kernel_wasm.js';
import { envelope } from '/plb.js';

const ready = init().then(() => newKeyring());
const streams = new Map();

self.onmessage = async ({ data: { id, src, key, start, end } }) => {
  try {
    if (!streams.has(src)) streams.set(src, ready.then((keyring) => envelope(src, key, 6, keyring)));
    const bytes = await (await streams.get(src)).read(start, end);
    self.postMessage({ id, bytes }, [bytes.buffer]);
  } catch (error) {
    self.postMessage({ id, error: String(error) });
  }
};
