// The HEIC spike's measurements (docs/dev/heic-without-system-decoder.md), by hand: in headless Chrome and Firefox,
// what main does with HEIC and HEVC today (the thumbnail worker of app/lib/features/library/timeline/
// browser_thumbnails.dart on every twin, the browser's codec checks, a <video> per codec), then libheif-js, the
// WASM build of libheif and libde265, decoding the corpus' HEIC twins (tools/heic/twins.py) in a worker: its size,
// cold and second load, time per image and memory. Prints the report's tables; HEIC_JSON=<file> keeps every number.
//
//   node tools/heic/bench.mjs [chrome|firefox]...
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { brotliCompressSync, gzipSync } from 'node:zlib';
import { pageErrors } from '../web_probe/errors.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const LIBHEIF = 'libheif-js@1.23.5';
const INTEGRITY = 'sha512-umXZPthnWZtF3iG/5mQG+AZ2V6i0UeYpo3z2CkggTEgL8dKmIIwJT6TDuAMuabXa1yTW8uJ1ZAgR+CxNTklYYw==';
const RUNS = 3;
const which = (name) => spawnSync('sh', ['-c', `command -v ${name}`], { encoding: 'utf8' }).stdout.trim();
const browsers = {
  chrome: process.env.CHROME_EXECUTABLE || which('google-chrome') || which('chromium'),
  firefox: process.env.FIREFOX_EXECUTABLE || which('firefox'),
};
const names = process.argv.length > 2 ? process.argv.slice(2) : Object.keys(browsers);
const run = (command, args, options) =>
  execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options })?.trim();

const dir = mkdtempSync(join(tmpdir(), 'heic-bench-'));
// libheif-js from npm, checked against the integrity pinned above.
run('npm', ['pack', LIBHEIF, '--pack-destination', dir, '--silent']);
const tarball = join(dir, readdirSync(dir).find((f) => f.endsWith('.tgz')));
const integrity = `sha512-${createHash('sha512').update(readFileSync(tarball)).digest('base64')}`;
if (integrity !== INTEGRITY) throw new Error(`${LIBHEIF} is ${integrity}, not ${INTEGRITY}`);
run('tar', ['xzf', tarball, '-C', dir]);
const libheif = join(dir, 'package/libheif-wasm');
const sizes = Object.fromEntries(['libheif.js', 'libheif.wasm'].map((file) => {
  const bytes = readFileSync(join(libheif, file));
  return [file, { raw: bytes.length, gzip: gzipSync(bytes, { level: 9 }).length, brotli: brotliCompressSync(bytes).length }];
}));
// The twins take minutes to code: they are kept per version of their maker, in the cache twins.py keeps its venv in.
const maker = ['twins.py', 'requirements.txt'].map((f) => readFileSync(join(root, 'tools/heic', f))).join('');
const files = join(process.env.PHOTOLIB_CACHE || join(process.env.TMPDIR || '/var/tmp', `photolib-${process.getuid()}`),
  `heic-twins-${createHash('sha256').update(maker).digest('hex').slice(0, 12)}`);
if (!existsSync(join(files, 'twins.json'))) run('python3', [join(root, 'tools/heic/twins.py'), files], { stdio: 'inherit' });
const twins = JSON.parse(readFileSync(join(files, 'twins.json'), 'utf8'));
// One clip per codec for <video>, and the stills of the dual-encoded pair, from the pinned LGPL FFmpeg.
const ffmpeg = join(run('bash', [join(root, 'tools/video/ffmpeg.sh')]), 'ffmpeg');
const clips = { hevc: 'libkvazaar', h264: 'libopenh264', av1: 'libsvtav1' };
for (const [name, encoder] of Object.entries(clips)) {
  run(ffmpeg, ['-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=30', '-t', '2', '-pix_fmt', 'yuv420p',
    '-c:v', encoder, ...(name === 'hevc' ? ['-tag:v', 'hvc1'] : []), '-movflags', '+faststart', join(dir, `${name}.mp4`)]);
}
for (const [file, encoder] of [['still.avif', 'libsvtav1'], ['still.jpg', 'mjpeg']]) {
  run(ffmpeg, ['-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=1280x720', '-frames:v', '1', '-pix_fmt',
    file.endsWith('avif') ? 'yuv420p' : 'yuvj420p', '-c:v', encoder, join(dir, file)]);
}
// The script main's thumbnail worker runs, as the Dart file holds it.
const dart = readFileSync(join(root, 'app/lib/features/library/timeline/browser_thumbnails.dart'), 'utf8');
const mainWorker = /const _script = r'''([\s\S]*?)''';/.exec(dart)[1];

const CODECS = {
  'HEVC Main': 'hvc1.1.6.L93.B0', 'HEVC Main 10': 'hvc1.2.4.L93.B0', 'H.264 High': 'avc1.640028',
  'AV1 Main 8-bit': 'av01.0.08M.08', 'AV1 Main 10-bit': 'av01.0.08M.10',
};
const page = `<!doctype html><script src="/errors.js"></script><script type="module">
const twins = ${JSON.stringify(twins.map(({ path, probes }) => ({ path, probes })))};
const codecs = ${JSON.stringify(CODECS)};
const mark = (phase) => fetch('/mark', { method: 'POST', body: phase });
// A worker's answer to a message, or why there is none within a minute.
const ask = (worker, message, transfer = []) => new Promise((done) => {
  const timer = setTimeout(() => done({ id: message.id, error: 'no answer within 60 s' }), 60000);
  worker.onerror = (event) => (clearTimeout(timer), done({ id: message.id, error: event.message || 'worker failed' }));
  worker.addEventListener('message', function on({ data }) {
    if (data.id !== message.id) return;
    worker.removeEventListener('message', on);
    clearTimeout(timer);
    done(data);
  });
  worker.postMessage(message, transfer);
});
const bytes = async (path) => (await fetch(path)).arrayBuffer();
const result = { agent: navigator.userAgent, capabilities: {}, main: [], video: {} };
const caps = result.capabilities;
caps.showDirectoryPicker = 'showDirectoryPicker' in self;
caps.webkitdirectory = 'webkitdirectory' in document.createElement('input');
caps.heic = self.ImageDecoder ? await ImageDecoder.isTypeSupported('image/heic') : null;
for (const [name, codec] of Object.entries(codecs)) {
  caps[name] = {
    mediaSource: MediaSource.isTypeSupported('video/mp4; codecs="' + codec + '"'),
    canPlayType: document.createElement('video').canPlayType('video/mp4; codecs="' + codec + '"'),
    videoDecoder: self.VideoDecoder ? (await VideoDecoder.isConfigSupported({ codec }).catch((e) => ({ supported: String(e) }))).supported : null,
  };
}
// main's thumbnail worker, as a browser folder hands it a file.
const main = new Worker(URL.createObjectURL(new Blob([await (await fetch('/main-worker.js')).text()], { type: 'text/javascript' })));
let id = 0;
for (const [path, type] of [...twins.map((t) => ['/twins/' + t.path, 'image/heic']), ['/clips/still.avif', 'image/avif'], ['/clips/still.jpg', 'image/jpeg']]) {
  const file = new File([await bytes(path)], path.split('/').pop(), { type });
  const answer = await ask(main, { id: id++, file, tier: 512, decoder: true });
  result.main.push({ path, via: answer.via, refused: answer.refused, error: answer.error,
    tile: answer.bitmap ? answer.bitmap.width + 'x' + answer.bitmap.height : null });
  answer.bitmap?.close();
}
main.terminate();
for (const codec of ${JSON.stringify(Object.keys(clips))}) {
  result.video[codec] = await new Promise((done) => {
    const video = document.createElement('video');
    const report = (error) => done({ error, frames: video.getVideoPlaybackQuality().totalVideoFrames });
    const timer = setTimeout(() => report('no playback within 20 s'), 20000);
    video.muted = true;
    video.onerror = () => (clearTimeout(timer), report(video.error.message || 'error ' + video.error.code));
    video.ontimeupdate = () => video.currentTime >= 0.5 && (clearTimeout(timer), video.pause(), report());
    video.src = '/clips/' + codec + '.mp4';
    video.play().catch((e) => (clearTimeout(timer), report('play: ' + e.message)));
  });
}
// libheif-js: a cold load in this fresh profile, then a second one from the HTTP cache.
await mark('loading');
const load = async () => {
  const started = performance.now();
  const worker = new Worker('/heif-worker.js');
  const ready = await ask(worker, { id: 'ready' });
  return { worker, ms: performance.now() - started, version: ready.version };
};
const cold = await load();
cold.worker.terminate();
const second = await load();
result.libheif = { version: second.version, coldMs: cold.ms, secondMs: second.ms, twins: [] };
await mark('decoding');
for (const twin of twins) {
  const runs = [];
  for (let n = 0; n < ${RUNS}; n++) {
    const buffer = await bytes('/twins/' + twin.path);
    runs.push(await ask(second.worker, { id: twin.path + n, buffer, probes: twin.probes, tier: 512 }, [buffer]));
  }
  result.libheif.twins.push({ path: twin.path, runs });
}
await mark('decoded');
await fetch('/done', { method: 'POST', body: JSON.stringify(result) });
</script>`;

// The decoder's worker: libheif-js' own decoder for the image and its thmb item, RGBA into an ImageData, then the
// tile at the tier as browser_thumbnails.dart makes it; the colours at the twin's probes, 9 x 9 pixels averaged.
const heifWorker = `importScripts('/libheif/libheif.js');
let M;
const ready = new Promise((resolve) => (M = libheif({ locateFile: (file) => '/libheif/' + file, onRuntimeInitialized: resolve })));
const rgba = async (handle) => {
  const decoded = await M.heif_js_decode_image2(handle, M.heif_colorspace.heif_colorspace_RGB, M.heif_chroma.heif_chroma_interleaved_RGBA);
  const plane = decoded.channels.find((c) => c.id === M.heif_channel.heif_channel_interleaved);
  const image = new ImageData(plane.width, plane.height);
  for (let y = 0; y < plane.height; y++) image.data.set(plane.data.subarray(y * plane.stride, y * plane.stride + plane.width * 4), y * plane.width * 4);
  M.heif_image_release(decoded.image);
  return image;
};
// The thmb item decoded through the C API, as libheif-js' wrapper has no call for it: a function returning libheif's
// error struct takes a pointer to it first. RGB is colourspace 1, interleaved RGBA chroma 11, its channel 10.
const thumbnail = (handle) => {
  if (!M._heif_image_handle_get_number_of_thumbnails(handle)) return null;
  const [ids, error, out] = [M._malloc(4), M._malloc(16), M._malloc(4)];
  M._heif_image_handle_get_list_of_thumbnail_IDs(handle, ids, 1);
  M._heif_image_handle_get_thumbnail(error, handle, M.HEAPU32[ids >> 2], out);
  const thumb = M.HEAPU32[out >> 2];
  const started = performance.now();
  M._heif_decode_image(error, thumb, out, 1, 11, 0);
  const ms = performance.now() - started, image = M.HEAPU32[out >> 2];
  const size = M.HEAP32[error >> 2] ? null : M._heif_image_get_width(image, 10) + 'x' + M._heif_image_get_height(image, 10);
  M._heif_image_release(image);
  M._heif_image_handle_release(thumb);
  for (const pointer of [ids, error, out]) M._free(pointer);
  return { ms, size };
};
onmessage = async ({ data: { id, buffer, probes, tier } }) => {
  await ready;
  if (id === 'ready') return postMessage({ id, version: M.heif_get_version() });
  const started = performance.now();
  const decoder = new M.HeifDecoder();
  const [image] = decoder.decode(new Uint8Array(buffer));
  const parsed = performance.now();
  const pixels = await rgba(image.handle);
  const decoded = performance.now();
  const scale = Math.min(1, tier / Math.min(pixels.width, pixels.height));
  const tile = await createImageBitmap(pixels, { resizeWidth: Math.round(pixels.width * scale),
    resizeHeight: Math.round(pixels.height * scale), resizeQuality: 'medium' });
  const tiled = performance.now();
  tile.close();
  const thumb = thumbnail(image.handle.$$.ptr);
  const wrong = probes.filter(([x, y, rgb]) => {
    const sum = [0, 0, 0];
    for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) for (let c = 0; c < 3; c++) sum[c] += pixels.data[((y + dy) * pixels.width + x + dx) * 4 + c];
    return sum.some((s, c) => Math.abs(s / 81 - rgb[c]) > 24);
  });
  image.free();
  M.heif_context_free(decoder.decoder);
  postMessage({ id, size: pixels.width + 'x' + pixels.height, parseMs: parsed - started, decodeMs: decoded - parsed,
    tileMs: tiled - decoded, thumb, heap: M.HEAPU8.length, probes: probes.length, wrong: wrong.length });
};`;

const TYPES = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.mp4': 'video/mp4' };

/// The resident memory of the processes in the process group `group`, in bytes, from /proc.
function resident(group) {
  let bytes = 0;
  for (const pid of readdirSync('/proc').filter((p) => /^\d+$/.test(p))) {
    try {
      const stat = readFileSync(`/proc/${pid}/stat`, 'utf8');
      const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
      if (Number(fields[2]) === group) bytes += Number(fields[21]) * 4096;
    } catch {}
  }
  return bytes;
}

async function measure(name) {
  let done, browser, phase = 'probing';
  const peaks = {};
  const finished = new Promise((resolve) => (done = resolve));
  const logged = [];
  const server = createServer(async (request, response) => {
    if (await pageErrors(request, response, (text) => logged.push(text))) return;
    const path = decodeURIComponent(request.url);
    const body = Buffer.concat(await Array.fromAsync(request)).toString();
    if (path === '/mark') phase = body;
    if (path === '/done') done(JSON.parse(body));
    const [, folder, rest] = /^\/(libheif|twins|clips)\/(.+)$/.exec(path) ?? [];
    const file = folder && join({ libheif, twins: files, clips: dir }[folder], rest);
    const text = { '/': page, '/main-worker.js': mainWorker, '/heif-worker.js': heifWorker }[path];
    if (text !== undefined) response.writeHead(200, { 'content-type': path === '/' ? 'text/html' : 'text/javascript', 'cache-control': 'no-store' }).end(text);
    else if (file && existsSync(file)) {
      // libheif-js may be cached, as a page's script would be; the rest is fetched anew.
      const cache = folder === 'libheif' ? 'max-age=3600' : 'no-store';
      const type = TYPES[extname(file)] ?? 'application/octet-stream';
      response.writeHead(200, { 'content-type': type, 'cache-control': cache }).end(readFileSync(file));
    } else response.writeHead(path === '/mark' || path === '/done' ? 200 : 404).end();
  }).listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const url = `http://127.0.0.1:${server.address().port}/`;
  const profile = mkdtempSync(join(tmpdir(), `heic-${name}-`));
  const args = name === 'firefox'
    ? ['--headless', '--no-remote', '--profile', profile, url]
    : ['--headless=new', `--user-data-dir=${profile}`, '--no-first-run', '--autoplay-policy=no-user-gesture-required', url];
  if (name === 'firefox') writeFileSync(join(profile, 'user.js'), 'user_pref("media.autoplay.default", 0);\n');
  // Firefox on Linux decodes video with the system's FFmpeg, as desktops have it (tools/video/play.mjs).
  const libs = name === 'firefox' ? run('bash', [join(root, 'tools/video/ffmpeg.sh'), '--libs']) : '';
  browser = spawn(browsers[name], args, { stdio: 'ignore', detached: true, env: libs ? { ...process.env, LD_LIBRARY_PATH: libs } : process.env });
  const sampler = setInterval(() => (peaks[phase] = Math.max(peaks[phase] ?? 0, resident(browser.pid))), 100);
  const timeout = setTimeout(() => done({ error: `${name} reported nothing within 10 minutes` }), 600000);
  try {
    const result = await finished;
    return { ...result, browserResidentPeaks: peaks, logged };
  } finally {
    clearTimeout(timeout);
    clearInterval(sampler);
    try {
      process.kill(-browser.pid, 'SIGKILL');
    } catch {}
    server.close();
    rmSync(profile, { recursive: true, force: true });
  }
}

const results = {};
for (const name of names) results[name] = await measure(name);
rmSync(dir, { recursive: true, force: true });
if (process.env.HEIC_JSON) writeFileSync(process.env.HEIC_JSON, JSON.stringify({ sizes, twins, results }, null, 1));

// The report's tables (docs/dev/heic-without-system-decoder.md): times are the fastest of the runs, memory the peaks.
const MB = (bytes) => (bytes / 1e6).toFixed(2);
const fastest = (runs, key) => Math.round(Math.min(...runs.map(key)));
const label = (r) => /(Chrome|Firefox)\/(\d+)/.exec(r.agent).slice(1).join(' ');
const total = (key) => sizes['libheif.js'][key] + sizes['libheif.wasm'][key];
const header = (...cells) => console.log(`| ${cells.join(' | ')} |\n|${cells.map(() => '---').join('|')}|`);
header('Browser', 'Module (raw / gzip / brotli)', 'Cold load', 'Second load', 'Browser memory growth');
for (const r of Object.values(results)) {
  const growth = Math.max(r.browserResidentPeaks.decoding, r.browserResidentPeaks.decoded ?? 0) - r.browserResidentPeaks.probing;
  console.log(`| ${label(r)} | ${MB(total('raw'))} / ${MB(total('gzip'))} / ${MB(total('brotli'))} MB | ${Math.round(r.libheif.coldMs)} ms | ${Math.round(r.libheif.secondMs)} ms | ${Math.round(growth / 1e6)} MB |`);
}
for (const r of Object.values(results)) {
  console.log(`\n${label(r)}, libheif ${r.libheif.version}:\n`);
  header('Twin', 'Bytes', 'Shown', '512 tile', 'thmb', 'Wasm heap', 'Upright');
  for (const { path, runs } of r.libheif.twins) {
    const twin = twins.find((t) => t.path === path), wrong = Math.max(...runs.map((x) => x.wrong));
    if (runs.some((x) => x.error)) {
      console.log(`| \`${path}\` | ${runs.map((x) => x.error).join('; ')} |`);
      continue;
    }
    console.log(`| \`${path}\` | ${MB(twin.bytes)} MB | ${twin.shown.join(' × ')} | ${fastest(runs, (x) => x.parseMs + x.decodeMs + x.tileMs)} ms | ${runs[0].thumb ? `${fastest(runs, (x) => x.thumb.ms)} ms` : 'none'} | ${Math.round(Math.max(...runs.map((x) => x.heap)) / 2 ** 20)} MB | ${wrong ? `no (${wrong} of ${runs[0].probes} probes)` : 'yes'} |`);
  }
}
const rows = [['ImageDecoder takes image/heic', (r) => r.capabilities.heic],
  ['main\'s worker on the HEIC twins', (r) => [...new Set(r.main.filter((m) => m.path.startsWith('/twins/')).map((m) => m.refused?.replace(/^[^:]*: /, '') ?? m.tile))].join('; ')],
  ['main\'s worker on AVIF and JPEG', (r) => r.main.filter((m) => m.path.startsWith('/clips/')).map((m) => `${m.via} ${m.tile ?? m.refused}`).join('; ')],
  ...Object.keys(CODECS).map((codec) => [`${codec}: MSE / canPlayType / VideoDecoder`, (r) => {
    const c = r.capabilities[codec];
    return `${c.mediaSource} / ${c.canPlayType || '""'} / ${c.videoDecoder}`;
  }]),
  ...Object.keys(clips).map((codec) => [`\`<video>\` plays ${codec}`, (r) => r.video[codec].error ?? `${r.video[codec].frames} frames`]),
  ['showDirectoryPicker / webkitdirectory', (r) => `${r.capabilities.showDirectoryPicker} / ${r.capabilities.webkitdirectory}`]];
console.log();
header('Check', ...Object.values(results).map(label));
for (const [name, value] of rows) console.log(`| ${name} | ${Object.values(results).map(value).join(' | ')} |`);
