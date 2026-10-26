// Plays what the server renders of every corpus video, the original or R1, in headless Chrome and Firefox: each must
// decode frames of the picture as shown (design 08 §5.1). The server's video test renders them
// (server/crates/photolib-server/tests/video.rs). On Linux, Firefox decodes H.264 and AAC only with the system's
// FFmpeg, as desktops have it; here that is the pinned LGPL build's libraries (tools/video/ffmpeg.sh --libs).
import { spawn, spawnSync } from 'node:child_process';
import { createReadStream, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pageErrors } from '../web_probe/errors.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const which = (name) => spawnSync('sh', ['-c', `command -v ${name}`], { encoding: 'utf8' }).stdout.trim();
const browsers = {
  chrome: process.env.CHROME_EXECUTABLE || which('google-chrome') || which('chromium'),
  firefox: process.env.FIREFOX_EXECUTABLE || which('firefox'),
};

function run(command, args, env = process.env) {
  const result = spawnSync(command, args, { encoding: 'utf8', env, stdio: ['ignore', 'pipe', 'inherit'] });
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')} failed`);
  return result.stdout.trim();
}

const dir = mkdtempSync(join(tmpdir(), 'playable-'));
const manifest = join(root, 'server/Cargo.toml');
run('cargo', ['test', '--locked', '-q', '--manifest-path', manifest, '-p', 'photolib-server', '--test', 'video', 'every_corpus_video'], {
  ...process.env,
  PHOTOLIB_PLAYABLE: dir,
});
const playable = JSON.parse(readFileSync(join(dir, 'playable.json'), 'utf8'));
const libs = run('bash', [join(root, 'tools/video/ffmpeg.sh'), '--libs']);

// Plays every file a few at a time until half a second has played, then reports what the element decoded; what the
// page logs as an error it posts to /errors.
const page = `<!doctype html><script src="/errors.js"></script><script>
const files = ${JSON.stringify(playable.map((p) => p.file))};
const play = (file) => new Promise((done) => {
  const video = document.createElement('video');
  const report = (error) => done({ file, error, width: video.videoWidth, height: video.videoHeight,
    frames: video.getVideoPlaybackQuality().totalVideoFrames });
  const timer = setTimeout(() => report('no playback within 20 s'), 20000);
  video.muted = true;
  video.onerror = () => { clearTimeout(timer); report(video.error.message || 'error ' + video.error.code); };
  video.ontimeupdate = () => { if (video.currentTime >= 0.5) { clearTimeout(timer); video.pause(); report(); } };
  video.onended = () => { clearTimeout(timer); report(); };
  video.src = '/media/' + file;
  video.play().catch((e) => { clearTimeout(timer); report('play: ' + e.message); });
});
(async () => {
  const results = [], queue = [...files];
  await Promise.all([0, 1, 2, 3].map(async () => { while (queue.length) results.push(await play(queue.shift())); }));
  await fetch('/done', { method: 'POST', body: JSON.stringify(results) });
})();
</script>`;

/// Answers the page, the media with byte ranges, and the results, which it resolves; what the page logs as an error
/// goes to `logged`.
function serve(resolve, logged) {
  return createServer(async (request, response) => {
    if (await pageErrors(request, response, (text) => logged.push(text))) return;
    if (request.url === '/') return response.end(page);
    if (request.url.startsWith('/media/')) {
      const file = join(dir, decodeURIComponent(request.url.slice(7)));
      const size = statSync(file).size;
      const [, from, to] = /^bytes=(\d+)-(\d*)$/.exec(request.headers.range ?? '') ?? [];
      const start = Number(from ?? 0), end = to ? Number(to) : size - 1;
      const headers = { 'content-type': 'video/mp4', 'accept-ranges': 'bytes', 'content-length': end - start + 1 };
      if (from !== undefined) headers['content-range'] = `bytes ${start}-${end}/${size}`;
      response.writeHead(from === undefined ? 200 : 206, headers);
      return createReadStream(file, { start, end }).pipe(response);
    }
    if (request.url !== '/done') return response.writeHead(404).end();
    let body = '';
    request.on('data', (chunk) => (body += chunk));
    request.on('end', () => (response.end(), resolve(JSON.parse(body))));
  });
}

async function results(name, logged) {
  let resolve;
  const done = new Promise((r) => (resolve = r));
  const server = serve(resolve, logged).listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  const url = `http://127.0.0.1:${server.address().port}/`;
  const profile = mkdtempSync(join(tmpdir(), `play-${name}-`));
  const args =
    name === 'firefox'
      ? ['--headless', '--no-remote', '--profile', profile, url]
      : ['--headless=new', `--user-data-dir=${profile}`, '--no-first-run', '--autoplay-policy=no-user-gesture-required', url];
  if (name === 'firefox') writeFileSync(join(profile, 'user.js'), 'user_pref("media.autoplay.default", 0);\n');
  const env = libs && name === 'firefox' ? { ...process.env, LD_LIBRARY_PATH: libs } : process.env;
  const browser = spawn(browsers[name], args, { stdio: 'ignore', detached: true, env });
  const timeout = setTimeout(() => resolve([{ file: '*', error: `${name} reported nothing within 5 minutes` }]), 300000);
  try {
    return await done;
  } finally {
    clearTimeout(timeout);
    try {
      process.kill(-browser.pid, 'SIGKILL');
    } catch {}
    server.close();
    rmSync(profile, { recursive: true, force: true });
  }
}

const wrong = [];
for (const name of Object.keys(browsers)) {
  if (!browsers[name]) throw new Error(`${name} is required: put it on PATH or set ${name.toUpperCase()}_EXECUTABLE`);
  const logged = [];
  const reported = await results(name, logged);
  // An uncaught exception or a console error in the page fails too.
  wrong.push(...logged.map((text) => `${name}: ${text}`));
  const seen = new Map(reported.map((r) => [r.file, r]));
  for (const { path, file, width, height } of playable) {
    const r = seen.get(file) ?? seen.get('*') ?? { error: 'not played' };
    if (r.error || r.width !== width || r.height !== height || !(r.frames > 0))
      wrong.push(`${name}: ${path}: ${r.error ?? `${r.width}x${r.height}, ${r.frames} frames, not ${width}x${height}`}`);
  }
  console.log(`${name}: ${playable.length - wrong.filter((w) => w.startsWith(name)).length}/${playable.length} play`);
}
rmSync(dir, { recursive: true, force: true });
if (wrong.length) {
  console.error(wrong.join('\n'));
  process.exit(1);
}
