// Encrypted-playback benchmark; methodology, budgets and results: docs/dev/encrypted-playback.md.
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { pageErrors } from '../web_probe/errors.mjs';
import { original, seal, stream } from './stream.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../..');
const MODES = process.env.MODES?.split(',') ?? ['plain', 'proxy', 'mse', 'sw'];
const SEEKS = Array.from({ length: 10 }, (_, i) => Math.round((((i + 1) * 683.3) % 7190) * 100) / 100 + 2.7);
const PLAY_SECONDS = 4;
const BUDGET_MS = 1000;
const browsers = {
  chrome: process.env.CHROME_EXECUTABLE || which('google-chrome') || which('chromium'),
  firefox: process.env.FIREFOX_EXECUTABLE || which('firefox'),
};
const NAMES = process.env.BROWSERS?.split(',') ?? Object.keys(browsers);

function which(name) {
  return spawnSync('sh', ['-c', `command -v ${name}`], { encoding: 'utf8' }).stdout.trim();
}

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'inherit'] });
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')} failed`);
  return result.stdout;
}

/// The processes in the tree under `pid`, with their CPU ticks (1/100 s): utime + stime. None without /proc.
function tree(pid) {
  const all = [];
  if (!existsSync('/proc')) return all;
  for (const entry of readdirSync('/proc')) {
    try {
      const stat = readFileSync(`/proc/${entry}/stat`, 'utf8');
      const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
      all.push({ pid: Number(entry), ppid: Number(fields[1]), ticks: Number(fields[11]) + Number(fields[12]) });
    } catch {}
  }
  const found = all.filter((p) => p.pid === pid);
  for (let i = 0; i < found.length; i++) found.push(...all.filter((p) => p.ppid === found[i].pid));
  return found;
}
const ticks = (pid) => (existsSync('/proc') ? tree(pid).reduce((sum, p) => sum + p.ticks, 0) : NaN);

function launch(name, url) {
  const profile = mkdtempSync(join(tmpdir(), `playback-${name}-`));
  const args =
    name === 'firefox'
      ? ['--headless', '--no-remote', '--profile', profile, url]
      : ['--headless=new', `--user-data-dir=${profile}`, '--no-first-run', '--autoplay-policy=no-user-gesture-required', url];
  if (name === 'firefox') writeFileSync(join(profile, 'user.js'), 'user_pref("media.autoplay.default", 0);\n');
  const child = spawn(browsers[name], args, { stdio: 'ignore', detached: true });
  return {
    name,
    pid: child.pid,
    close() {
      for (const pid of [...tree(child.pid).map((p) => p.pid).reverse(), -child.pid]) {
        try {
          process.kill(pid, 'SIGKILL');
        } catch {}
      }
      rmSync(profile, { recursive: true, force: true });
    },
  };
}

/// `promise`, or a failure after `ms`; the timer does not keep the script alive once the rest is done.
const within = (promise, ms, what) =>
  Promise.race([promise, new Promise((_, no) => setTimeout(() => no(new Error(`${what} timed out`)), ms).unref())]);

/// Answers a byte range of a lazily read file, streamed in pieces so an open-ended range costs nothing up front.
function serveRange(request, response, file, type) {
  const [, from, to] = /^bytes=(\d+)-(\d*)$/.exec(request.headers.range ?? '') ?? [];
  const start = Number(from ?? 0);
  const end = to ? Math.min(Number(to) + 1, file.size) : file.size;
  if (start >= file.size) return response.writeHead(416, { 'content-range': `bytes */${file.size}` }).end();
  response.writeHead(request.headers.range ? 206 : 200, {
    'content-type': type,
    'accept-ranges': 'bytes',
    'content-length': end - start,
    ...(request.headers.range && { 'content-range': `bytes ${start}-${end - 1}/${file.size}` }),
  });
  Readable.from(
    (function* () {
      for (let at = start; at < end; at += 1 << 18) yield file.read(at, Math.min(at + (1 << 18), end));
    })(),
  ).pipe(response);
}

const work = mkdtempSync(join(tmpdir(), 'playback-'));
const cleanup = [() => rmSync(work, { recursive: true, force: true })];
try {
  for (const name of NAMES) if (!browsers[name]) throw new Error(`no ${name}: install it or set it in the environment`);
  run('bash', [join(root, 'tools/kernel/wasm.sh'), join(work, 'kernel')], root);
  const build = ['build', '--locked', '--release', '-p', 'photolib-kernel-ffi', '--message-format=json'];
  const kernel = run('cargo', build, join(root, 'kernel'))
    .split('\n')
    .filter((line) => line.includes('"photolib_kernel_ffi"'))
    .flatMap((line) => JSON.parse(line).filenames ?? [])
    .find((file) => /\.(so|dylib|dll)$/.test(file));

  const key = randomBytes(32);
  let plain, index, media, current, proxyPid, requests = 0;
  const marks = {}, waiters = {}, logged = [];
  const arrived = (name) => new Promise((resolve) => (waiters[name] = resolve));
  const files = { '/': 'index.html', '/player.js': 0, '/plb.js': 0, '/sw.js': 0, '/worker.js': 0 };
  const server = createServer(async (request, response) => {
    // An uncaught exception or a console error in the page fails the benchmark.
    if (await pageErrors(request, response, (text) => logged.push(`${current.name}: ${text}`))) return;
    const path = request.url.split('?')[0];
    const body = request.method === 'POST' ? Buffer.concat(await Array.fromAsync(request)) : null;
    if (path.startsWith('/media/')) requests++;
    if (path in files) {
      response.writeHead(200, { 'content-type': path === '/' ? 'text/html' : 'text/javascript' });
      response.end(readFileSync(join(here, 'web', files[path] || path.slice(1))));
    } else if (path.startsWith('/kernel/')) {
      response.writeHead(200, { 'content-type': path.endsWith('.wasm') ? 'application/wasm' : 'text/javascript' });
      response.end(readFileSync(join(work, path)));
    } else if (path === '/config') {
      const config = { modes: MODES, key: key.toString('hex'), index, proxy: current.proxy, seeks: SEEKS, play: PLAY_SECONDS };
      response.end(JSON.stringify(config));
    } else if (path === '/stats') {
      response.end(String(requests));
    } else if (path === '/media/plain') {
      serveRange(request, response, plain, 'video/mp4');
    } else if (media?.[path]) {
      serveRange(request, response, media[path], 'application/octet-stream');
    } else if (path === '/mark') {
      const { mode, phase } = JSON.parse(body);
      marks[`${mode} ${phase}`] = { time: performance.now(), browser: ticks(current.pid), proxy: ticks(proxyPid) };
      response.end();
    } else if (path === '/log') {
      console.error(`${current.name}: ${body}`);
      response.end();
    } else if (body) {
      response.end();
      waiters[path.slice(1)]?.(body);
    } else {
      response.writeHead(404).end();
    }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  cleanup.push(() => server.close());
  const origin = `http://127.0.0.1:${server.address().port}/`;

  current = launch('chrome', `${origin}?encode`);
  const fixture = await within(arrived('fixture'), 120000, 'encoding');
  current.close();
  const frames = [];
  for (let at = 0; at < fixture.length; ) {
    const length = fixture.readUInt32BE(at + 1);
    frames.push({ key: fixture[at] === 1, data: fixture.subarray(at + 5, at + 5 + length) });
    at += 5 + length;
  }
  if (frames.length !== 100 || !frames[0].key || !frames[50].key) throw new Error(`the encoder gave ${frames.length} frames`);
  plain = original(frames, { width: 854, height: 480 });
  const rendition = stream(frames, { width: 854, height: 480 });
  index = rendition.index;
  media = { '/media/original': seal(plain, key, 1), '/media/stream': seal(rendition, key, 6) };
  console.log(`video: ${index.duration} s, ${(plain.size / 1e9).toFixed(2)} GB, ${((index.segment * 8) / index.seconds / 1e6).toFixed(2)} Mb/s`);

  const proxy = spawn('dart', ['run', 'tool/decrypting_proxy.dart', origin, kernel, key.toString('hex'), 'media/original'], {
    cwd: join(root, 'app/packages/photolib_api'),
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  cleanup.push(() => proxy.kill('SIGKILL'));
  proxyPid = proxy.pid;
  const proxyUrl = await new Promise((resolve, reject) => {
    let out = '';
    proxy.stdout.on('data', (data) => {
      out += data;
      const url = /^http:\/\/\S+$/m.exec(out);
      if (url) resolve(url[0]);
    });
    proxy.on('exit', (code) => reject(new Error(`the proxy exited with ${code}`)));
  });

  const rows = [];
  for (const name of NAMES) {
    const done = arrived('done');
    const collected = [];
    waiters.result = function collect(body) {
      collected.push(JSON.parse(body));
      waiters.result = collect;
    };
    current = { ...launch(name, `${origin}?run`), proxy: proxyUrl };
    await within(done, 300000, name);
    current.close();
    for (const { mode, version, error, seeks, dropped, frames } of collected) {
      let row = { browser: `${name} ${version}`, mode, error };
      if (!error) {
        const [start, end] = [marks[`${mode} start`], marks[`${mode} end`]];
        const seconds = (end.time - start.time) / 1000;
        const ms = seeks.map((s) => s.ms).sort((a, b) => a - b);
        row = {
          ...row,
          seek_p50_ms: Math.round(ms[ms.length >> 1]),
          seek_max_ms: Math.round(ms.at(-1)),
          requests_per_seek: seeks.reduce((n, s) => n + s.requests, 0) / ms.length,
          cpu_percent: Math.round((end.browser - start.browser + end.proxy - start.proxy) / seconds),
          proxy_cpu_percent: Math.round((end.proxy - start.proxy) / seconds),
          dropped,
          frames,
        };
      }
      console.log(JSON.stringify(row));
      rows.push(row);
    }
  }
  const failures = rows.filter((r) => r.error || !(r.seek_p50_ms <= BUDGET_MS));
  if (rows.length !== MODES.length * NAMES.length || failures.length) {
    throw new Error(`playback failed or missed the ${BUDGET_MS} ms budget:\n${failures.map((r) => JSON.stringify(r)).join('\n')}`);
  }
  if (logged.length) throw new Error(`the player's page logged errors:\n${logged.join('\n')}`);
} finally {
  for (const step of cleanup.reverse()) step();
}
