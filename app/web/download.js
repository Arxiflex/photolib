// The page's side of download_sw.js (ADR-0128): save(name) starts a download in the browser's own downloads and
// resolves to a writer whose write() waits until the download asks for the next chunk. Firefox keeps the partial file
// of a stream that fails, and stops a Service Worker idle for 30 s, so there the file is written to the origin's
// private file system first and handed over whole.
const scope = new URL('download/', document.baseURI);
let worker;

function ready() {
  worker ??= navigator.serviceWorker
    .register(new URL('download_sw.js', document.baseURI), { scope: scope.pathname })
    .then(async ({ installing, waiting, active }) => {
      const sw = installing ?? waiting ?? active;
      while (sw.state !== 'activated') await new Promise((done) => sw.addEventListener('statechange', done, { once: true }));
      return sw;
    });
  return worker;
}

export function save(name) {
  // Only Chromium keeps a Service Worker's stream alive for a download; Firefox stages the file in the origin's private
  // file system; Safari, which cannot write to it from the page, holds the bytes until it has them all.
  if (navigator.userAgentData) return streamed(name);
  return navigator.userAgent.includes('Firefox') ? staged(name) : held(name);
}

async function streamed(name) {
  const sw = await ready();
  const id = crypto.randomUUID();
  const { port1, port2 } = new MessageChannel();
  // The worker must know the download before the frame asks for it.
  const known = new Promise((done) => (port1.onmessage = done));
  sw.postMessage({ id, name }, [port2]);
  await known;
  // The download asks for each chunk; a write waits for its request, which may have come first.
  let asked = 0, waiting, cancelled;
  port1.onmessage = ({ data }) => {
    if (data === 'pull') {
      waiting ? waiting.resolve() : asked++;
    } else {
      cancelled = new DOMException('the download was cancelled', 'AbortError');
      waiting?.reject(cancelled);
    }
    waiting = undefined;
  };
  const frame = Object.assign(document.createElement('iframe'), {
    hidden: true,
    src: new URL(`${id}/${encodeURIComponent(name)}`, scope).href,
  });
  document.body.append(frame);
  const ping = setInterval(() => sw.postMessage('ping'), 10000);
  const end = (last) => {
    clearInterval(ping);
    port1.postMessage(last);
    // The download goes on without its frame.
    setTimeout(() => frame.remove(), 60000);
  };
  return {
    async write(chunk) {
      if (cancelled) throw cancelled;
      if (asked) asked--;
      else await new Promise((resolve, reject) => (waiting = { resolve, reject }));
      port1.postMessage(chunk);
    },
    close: () => end(null),
    abort: () => end('abort'),
  };
}

async function staged(name) {
  const folder = await (await navigator.storage.getDirectory()).getDirectoryHandle('downloads', { create: true });
  // What an earlier page left: it has been handed over, or the page closed mid-way.
  for await (const old of folder.keys()) await folder.removeEntry(old).catch(() => {});
  const id = crypto.randomUUID();
  const file = await folder.getFileHandle(id, { create: true });
  const writable = await file.createWritable();
  const drop = () => folder.removeEntry(id).catch(() => {});
  return {
    write: (chunk) => writable.write(chunk),
    async close() {
      await writable.close();
      const url = URL.createObjectURL(await file.getFile());
      Object.assign(document.createElement('a'), { href: url, download: name }).click();
      setTimeout(() => (URL.revokeObjectURL(url), drop()), 600000);
    },
    async abort() {
      await writable.abort();
      await drop();
    },
  };
}

async function held(name) {
  const chunks = [];
  return {
    write: async (chunk) => void chunks.push(chunk),
    async close() {
      const url = URL.createObjectURL(new Blob(chunks));
      chunks.length = 0;
      Object.assign(document.createElement('a'), { href: url, download: name }).click();
      setTimeout(() => URL.revokeObjectURL(url), 600000);
    },
    abort: async () => void (chunks.length = 0),
  };
}
