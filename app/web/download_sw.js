// Streams the downloads the app writes through download.js (ADR-0128, docs/10 §7.3): the page posts {id, name} with a
// port, then opens download/<id>/<name> in a frame; the answer is a stream that asks the port for each chunk, so
// neither side holds more than one and the browser's download writes them to disk as they come.
const waiting = new Map();

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('message', (event) => {
  // A ping only wakes the worker: an idle one is stopped even mid-download (in Firefox after 30 s).
  if (event.data === 'ping') return;
  waiting.set(event.data.id, { name: event.data.name, port: event.ports[0] });
  event.ports[0].postMessage('known');
});

self.addEventListener('fetch', (event) => {
  const id = new URL(event.request.url).pathname.split('/').at(-2);
  const download = waiting.get(id);
  if (!download) return;
  waiting.delete(id);
  const { name, port } = download;
  let controller;
  let pulled = () => {};
  port.onmessage = ({ data }) => {
    if (data === null) controller.close();
    else if (data === 'abort') controller.error(new Error('aborted'));
    else controller.enqueue(data);
    pulled();
  };
  const body = new ReadableStream({
    start: (c) => void (controller = c),
    pull: () => new Promise((done) => ((pulled = done), port.postMessage('pull'))),
    cancel: () => port.postMessage('cancel'),
  });
  event.respondWith(
    new Response(body, {
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(name)}`,
      },
    }),
  );
});
