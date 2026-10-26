// The Service Worker path: answers the player's range requests for a registered stream with plaintext, one window at
// most per response, so each fetch event stays short (browsers stop long-running Service Worker work).
import init, { newKeyring } from '/kernel/photolib_kernel_wasm.js';
import { envelope } from '/plb.js';

const ready = init().then(() => newKeyring());
const streams = new Map();

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

// The page hands over a stream: the path players ask for, the encrypted object and its key.
self.addEventListener('message', (event) => {
  const { path, src, key } = event.data;
  const opened = ready.then((keyring) => envelope(src, key, 1, keyring));
  streams.set(path, opened);
  opened.then(() => event.ports[0].postMessage('ready'));
});

self.addEventListener('fetch', (event) => {
  const stream = streams.get(new URL(event.request.url).pathname);
  if (stream) event.respondWith(serve(event.request, stream));
});

async function serve(request, stream) {
  const plain = await stream;
  const [, from, to] = /^bytes=(\d+)-(\d*)$/.exec(request.headers.get('range') ?? 'bytes=0-') ?? [];
  const start = Number(from ?? plain.size);
  if (start >= plain.size) return new Response(null, { status: 416, headers: { 'content-range': `bytes */${plain.size}` } });
  const end = Math.min(to ? Number(to) + 1 : plain.size, (Math.floor(start / plain.window) + 1) * plain.window, plain.size);
  return new Response(await plain.read(start, end), {
    status: 206,
    headers: { 'content-type': 'video/mp4', 'accept-ranges': 'bytes', 'content-range': `bytes ${start}-${end - 1}/${plain.size}` },
  });
}
