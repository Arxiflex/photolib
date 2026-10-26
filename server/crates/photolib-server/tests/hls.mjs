// hls.js, which the web clients play photolibd's ladder with, in a real browser over a throttled link (ADR-0246): the
// page plays the master playlist through this script's proxy, which carries every byte of media over one link at the
// rate the page sets, 40 ms a round trip. Usage: node hls.mjs <chrome|firefox> <photolibd's origin> <signed master
// path>; prints what the page saw: "start_ms", "stalls" (where each began), "loaded" and "played" ([seconds, height]
// at each change), "errors", the bandwidth "estimates" at each change of rate, the "levels" ([height, bits a second])
// and when the first of each of hls.js's "events" came.
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import {
  existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync,
} from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [name, server, master] = process.argv.slice(2);
const root = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
const { pageErrors } = await import(join(root, 'tools/web_probe/errors.mjs'));
const HLS = 'hls.js@1.7.3';
const INTEGRITY = 'sha512-MsPlx6yVW4Qv4C7mEVou4/gk/5cN2dVxOTnrNjPSmyH2f0Ln+/UkG10Ax1PE6OvrmTVPKgQYozTtBaPOuCzq7A==';
const which = (command) => spawnSync('sh', ['-c', `command -v ${command}`], { encoding: 'utf8' }).stdout.trim();
const run = (command, args) => {
  const done = spawnSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
  if (done.status !== 0) throw new Error(`${command} ${args.join(' ')} failed`);
  return done.stdout.trim();
};

// hls.js from npm, checked against the integrity pinned above, kept per version.
const cache = join(process.env.PHOTOLIB_TOOLS_CACHE || join(tmpdir(), `photolib-tools-${process.getuid()}`), HLS);
if (!existsSync(join(cache, 'hls.min.js'))) {
  const dir = mkdtempSync(join(tmpdir(), 'hls.js-'));
  run('npm', ['pack', HLS, '--pack-destination', dir, '--silent']);
  const tarball = join(dir, readdirSync(dir).find((f) => f.endsWith('.tgz')));
  const integrity = `sha512-${createHash('sha512').update(readFileSync(tarball)).digest('base64')}`;
  if (integrity !== INTEGRITY) throw new Error(`${HLS} is ${integrity}, not ${INTEGRITY}`);
  run('tar', ['xzf', tarball, '-C', dir]);
  mkdirSync(dirname(cache), { recursive: true });
  renameSync(join(dir, 'package/dist'), cache);
  rmSync(dir, { recursive: true, force: true });
}

// Plays until 15 s of video on 3 Mbit/s, 30 s on 8 Mbit/s and 30 s on 1.5 Mbit/s have played, at most 3 minutes.
const page = `<!doctype html><script src="/errors.js"></script><script src="/hls.min.js"></script>
<video muted playsinline></video><script>
(async () => {
  // A browser that has just started is busy for seconds; a viewer's is not.
  await new Promise((done) => setTimeout(done, 3000));
  // At most 30 s ahead, as data saver needs, rather than up to 60 MB.
  const video = document.querySelector('video'), hls = new Hls({ maxMaxBufferLength: 30 });
  const result = { stalls: [], loaded: [], played: [], errors: [], estimates: [], events: {} };
  const changed = (list, start, height) => list.at(-1)?.[1] !== height && list.push([Math.round(start), height]);
  const rate = (bps) => {
    result.estimates.push(Math.round(hls.bandwidthEstimate));
    return fetch('/rate?' + bps, { method: 'POST' });
  };
  const until = (seconds) => new Promise((done) => {
    const check = () => (video.currentTime >= seconds || performance.now() > 180000 ? done() : setTimeout(check, 100));
    check();
  });
  hls.on(Hls.Events.FRAG_LOADED, (_, { frag }) => changed(result.loaded, frag.start, hls.levels[frag.level].height));
  hls.on(Hls.Events.FRAG_CHANGED, (_, { frag }) => changed(result.played, frag.start, hls.levels[frag.level].height));
  for (const event of ['MANIFEST_LOADED', 'LEVEL_LOADED', 'FRAG_LOADED', 'FRAG_BUFFERED']) {
    hls.on(Hls.Events[event], () => (result.events[event] ??= Math.round(performance.now() - started)));
  }
  hls.on(Hls.Events.ERROR, (_, data) => data.fatal && result.errors.push(data.details));
  const started = performance.now();
  const shown = new Promise((done) => video.requestVideoFrameCallback(done));
  hls.loadSource(${JSON.stringify(master)});
  hls.attachMedia(video);
  video.play();
  await shown;
  result.start_ms = Math.round(performance.now() - started);
  video.addEventListener('waiting', () => result.stalls.push(video.currentTime));
  await until(15);
  await rate(8e6);
  await until(45);
  await rate(1.5e6);
  await until(75);
  result.estimates.push(Math.round(hls.bandwidthEstimate));
  result.levels = hls.levels.map((level) => [level.height, level.bitrate]);
  if (video.currentTime < 75) result.errors.push('played only ' + video.currentTime + ' s in 3 minutes');
  await fetch('/done', { method: 'POST', body: JSON.stringify(result) });
})();
</script>`;

// One link for every response, paced 16 KiB at a time at the page's rate.
let bps = 3e6;
let free = 0;
const sleep = (ms) => new Promise((done) => setTimeout(done, Math.max(0, ms)));
async function carry(response, bytes) {
  for (let at = 0; at < bytes.length; at += 16384) {
    const chunk = bytes.subarray(at, at + 16384);
    const now = performance.now();
    free = Math.max(now, free) + (chunk.length * 8000) / bps;
    await sleep(free - now);
    response.write(chunk);
  }
  response.end();
}

let resolve;
const done = new Promise((r) => (resolve = r));
const logged = [];
const proxy = createServer(async (request, response) => {
  if (await pageErrors(request, response, (text) => logged.push(text))) return;
  const path = request.url.split('?')[0];
  if (path === '/') return response.end(page);
  if (path === '/hls.min.js') {
    response.writeHead(200, { 'content-type': 'text/javascript' });
    return response.end(readFileSync(join(cache, 'hls.min.js')));
  }
  const body = Buffer.concat(await Array.fromAsync(request));
  if (path === '/rate') return (bps = Number(request.url.split('?')[1])), response.end();
  if (path === '/done') return response.end(), resolve(JSON.parse(body));
  await sleep(20);
  const answer = await fetch(server + request.url, { method: request.method });
  const bytes = Buffer.from(await answer.arrayBuffer());
  const kept = ['content-type', 'retry-after'].filter((h) => answer.headers.has(h));
  const headers = Object.fromEntries(kept.map((h) => [h, answer.headers.get(h)]));
  await sleep(20);
  response.writeHead(answer.status, headers);
  await carry(response, bytes);
});
proxy.listen(0, '127.0.0.1');
await new Promise((r) => proxy.once('listening', r));

const url = `http://127.0.0.1:${proxy.address().port}/`;
const profile = mkdtempSync(join(tmpdir(), `hls-${name}-`));
const browser = {
  chrome: process.env.CHROME_EXECUTABLE || which('google-chrome') || which('chromium'),
  firefox: process.env.FIREFOX_EXECUTABLE || which('firefox'),
}[name];
if (!browser) throw new Error(`${name} is required: put it on PATH or set ${name.toUpperCase()}_EXECUTABLE`);
const args =
  name === 'firefox'
    ? ['--headless', '--no-remote', '--profile', profile, url]
    : ['--headless=new', `--user-data-dir=${profile}`, '--no-first-run', '--autoplay-policy=no-user-gesture-required',
      url];
// Without a proxy to look for, as a desktop's Firefox has long since found out.
const prefs = { 'media.autoplay.default': 0, 'network.proxy.type': 0 };
const lines = Object.entries(prefs).map(([pref, value]) => `user_pref("${pref}", ${value});\n`);
if (name === 'firefox') writeFileSync(join(profile, 'user.js'), lines.join(''));
// On Linux, Firefox decodes H.264 and AAC only with the system's FFmpeg; here the pinned LGPL build's libraries.
const libs = name === 'firefox' ? run('bash', [join(root, 'tools/video/ffmpeg.sh'), '--libs']) : '';
const env = libs ? { ...process.env, LD_LIBRARY_PATH: libs } : process.env;
const child = spawn(browser, args, { stdio: 'ignore', detached: true, env });
const timeout = setTimeout(() => resolve({ errors: [`${name} reported nothing within 5 minutes`] }), 300000);
try {
  const result = await done;
  result.errors.push(...logged);
  console.log(JSON.stringify(result));
} finally {
  clearTimeout(timeout);
  try {
    process.kill(-child.pid, 'SIGKILL');
  } catch {}
  proxy.close();
  proxy.closeAllConnections();
  rmSync(profile, { recursive: true, force: true });
}
