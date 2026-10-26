// The benchmark page: with ?encode, encodes the 4 s segment the video repeats; with ?run, plays the video on each path
// in turn, seeks and reports to bench.mjs.
const CODEC = 'vp09.00.30.08';
const post = (path, body) => fetch(path, { method: 'POST', body: body instanceof Uint8Array ? body : JSON.stringify(body) });
const once = (target, event) => new Promise((resolve) => target.addEventListener(event, resolve, { once: true }));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/// Noise fills the bitrate budget; frames show their number. Records: key flag, length (u32), bytes.
async function encode() {
  const frames = [];
  let failure;
  const encoder = new VideoEncoder({
    output(chunk) {
      const frame = new Uint8Array(5 + chunk.byteLength);
      new DataView(frame.buffer).setUint32(1, chunk.byteLength);
      frame[0] = chunk.type === 'key' ? 1 : 0;
      chunk.copyTo(frame.subarray(5));
      frames.push(frame);
    },
    error: (error) => (failure = error),
  });
  encoder.configure({ codec: CODEC, width: 854, height: 480, bitrate: 2_500_000, bitrateMode: 'constant', framerate: 25 });
  const canvas = new OffscreenCanvas(854, 480);
  const context = canvas.getContext('2d');
  const image = context.createImageData(854, 480);
  const pixels = new Uint32Array(image.data.buffer);
  let seed = 1;
  for (let i = 0; i < 100; i++) {
    for (let p = 0; p < pixels.length; p++) {
      seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
      pixels[p] = 0xff000000 | (0x10101 * (96 + (seed >>> 26)));
    }
    context.putImageData(image, 0, 0);
    context.font = '160px sans-serif';
    context.fillText(String(i), 300, 300);
    const frame = new VideoFrame(canvas, { timestamp: i * 40000, duration: 40000 });
    encoder.encode(frame, { keyFrame: i % 50 === 0 });
    frame.close();
  }
  await encoder.flush();
  if (failure) throw failure;
  const out = new Uint8Array(frames.reduce((n, f) => n + f.length, 0));
  frames.reduce((at, f) => (out.set(f, at), at + f.length), 0);
  return out;
}

/// Points a video at the stream for each path; returns what to stop afterwards.
const sources = {
  plain(video) {
    video.src = '/media/plain';
  },
  proxy(video, config) {
    video.src = config.proxy;
  },
  async sw(video, config) {
    await navigator.serviceWorker.register('/sw.js', { type: 'module' });
    await navigator.serviceWorker.ready;
    if (!navigator.serviceWorker.controller) await once(navigator.serviceWorker, 'controllerchange');
    const channel = new MessageChannel();
    const ready = once(channel.port1, 'message');
    channel.port1.start();
    navigator.serviceWorker.controller.postMessage({ path: '/sw/original', src: '/media/original', key: config.key }, [channel.port2]);
    await ready;
    video.src = '/sw/original';
  },
  async mse(video, config) {
    const { index } = config;
    const worker = new Worker('/worker.js', { type: 'module' });
    const waiting = new Map();
    worker.onmessage = ({ data }) => waiting.get(data.id)(data);
    const read = (start, end) =>
      new Promise((resolve, reject) => {
        const id = waiting.size + Math.random();
        waiting.set(id, (data) => (waiting.delete(id), data.error ? reject(new Error(data.error)) : resolve(data.bytes)));
        worker.postMessage({ id, src: '/media/stream', key: config.key, start, end });
      });
    // ManagedMediaSource is the one iOS Safari has; it needs remote playback off or an AirPlay alternative.
    const source = new (self.ManagedMediaSource ?? MediaSource)();
    video.disableRemotePlayback = true;
    video.src = URL.createObjectURL(source);
    await once(source, 'sourceopen');
    const buffer = source.addSourceBuffer(`video/mp4; codecs="${index.codec}"`);
    source.duration = index.duration;
    const append = async (bytes) => {
      buffer.appendBuffer(bytes);
      await once(buffer, 'updateend');
    };
    await append(await read(0, index.init));
    // Keeps the segment playing and the next one appended; a seek moves both (the segment table is the stream index).
    const loaded = new Set();
    let busy = false;
    const pump = async () => {
      if (busy) return;
      busy = true;
      try {
        for (;;) {
          const k = Math.floor(video.currentTime / index.seconds);
          const next = [k, k + 1].find((s) => s < index.count && !loaded.has(s));
          if (next === undefined) break;
          loaded.add(next);
          const start = index.init + next * index.segment;
          await append(await read(start, start + index.segment));
        }
      } finally {
        busy = false;
      }
    };
    video.addEventListener('seeking', pump);
    video.addEventListener('timeupdate', pump);
    pump();
    return () => worker.terminate();
  },
};

/// Resolves with the media time of the first frame presented within 0.5 s of `t`.
function presented(video, t) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`no frame at ${t} s within 10 s`)), 10000);
    video.onerror = () => reject(new Error(`media error ${video.error.code}: ${video.error.message}`));
    const next = () =>
      video.requestVideoFrameCallback((_, frame) => {
        if (Math.abs(frame.mediaTime - t) >= 0.5) return next();
        clearTimeout(timer);
        resolve(frame.mediaTime);
      });
    next();
  });
}

async function measure(mode, config) {
  const video = document.body.appendChild(document.createElement('video'));
  video.muted = true;
  const stop = await sources[mode](video, config);
  try {
    await video.play();
    const requests = async () => Number(await (await fetch('/stats')).text());
    const seeks = [];
    for (const t of config.seeks) {
      const before = await requests();
      const start = performance.now();
      video.currentTime = t;
      const mediaTime = await presented(video, t);
      seeks.push({ t, ms: performance.now() - start, mediaTime, requests: (await requests()) - before });
      await sleep(300);
    }
    const quality = video.getVideoPlaybackQuality();
    await post('/mark', { mode, phase: 'start' });
    await sleep(config.play * 1000);
    await post('/mark', { mode, phase: 'end' });
    const after = video.getVideoPlaybackQuality();
    return {
      seeks,
      frames: after.totalVideoFrames - quality.totalVideoFrames,
      dropped: after.droppedVideoFrames - quality.droppedVideoFrames,
    };
  } finally {
    video.removeAttribute('src');
    video.load();
    video.remove();
    stop?.();
  }
}

async function run() {
  const config = await (await fetch('/config')).json();
  config.key = Uint8Array.from(config.key.match(/../g), (h) => parseInt(h, 16));
  const version = /(?:Chrome|Firefox)\/[\d.]+/.exec(navigator.userAgent)?.[0];
  for (const mode of config.modes) {
    let result;
    try {
      result = await measure(mode, config);
    } catch (error) {
      result = { error: String(error) };
      await post('/log', `${mode}: ${error.stack ?? error}`);
    }
    await post('/result', { mode, version, ...result });
  }
  await post('/done', {});
}

if (location.search === '?encode') {
  encode().then(
    (bytes) => post('/fixture', bytes),
    (error) => post('/log', String(error.stack ?? error)),
  );
} else {
  run();
}
