// The web download path (ADR-0128, docs/10 §7.3) in the browsers' own downloads: app/web/download.js streams Chrome's
// through app/web/download_sw.js, 2 GiB while the browser grows by less than a quarter of it, and stages Firefox's in
// the origin's private file system; downloads outlive the 30 s that browsers give an idle Service Worker, and an abort
// leaves no file behind.
import { spawn, spawnSync } from 'node:child_process';
import { closeSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, readSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const web = join(dirname(fileURLToPath(import.meta.url)), '../../app/web');
const MiB = 1 << 20;
const NAME = 'Photolib ✓ 1.zip';
const CASES = [
  { browser: 'chrome', mib: 2048 },
  { browser: 'chrome', mib: 40, every: 1000 },
  { browser: 'chrome', mib: 64, abort: 8 },
  { browser: 'firefox', mib: 40, every: 1000 },
  { browser: 'firefox', mib: 64, abort: 8 },
];
const browsers = {
  chrome: process.env.CHROME_EXECUTABLE || which('google-chrome') || which('chromium'),
  firefox: process.env.FIREFOX_EXECUTABLE || which('firefox'),
};

function which(name) {
  return spawnSync('sh', ['-c', `command -v ${name}`], { encoding: 'utf8' }).stdout.trim();
}

// Writes `mib` chunks of a MiB, the nth filled with n, one each `every` ms; aborts at chunk `abort`.
const PAGE = `
import { save } from '/download.js';
const q = new URLSearchParams(location.search), mib = +q.get('mib'), every = +q.get('every'), abort = q.get('abort');
const tell = (what) => fetch('/report', { method: 'POST', body: what });
try {
  const writer = await save(${JSON.stringify(NAME)});
  await tell('started');
  for (let n = 0; n < mib; n++) {
    if (abort !== null && n === +abort) break;
    await writer.write(new Uint8Array(${MiB}).fill(n & 255));
    if (every) await new Promise((done) => setTimeout(done, every));
  }
  await (abort === null ? writer.close() : writer.abort());
  await tell('written');
} catch (error) {
  await tell('error ' + error);
}`;
// What photolibd sends with the app (tools/web_requests.py), Trusted Types included.
const CSP =
  "default-src 'self'; script-src 'self'; worker-src 'self' blob:; connect-src 'self'; object-src 'none'; " +
  "base-uri 'self'; frame-ancestors 'none'; require-trusted-types-for 'script'; trusted-types flutter-js default";
const FILES = {
  '/': ['text/html', '<!doctype html><script src="/trusted_types.js"></script><script type="module" src="/page.js"></script>'],
  '/page.js': ['text/javascript', PAGE],
};

/// The resident memory of the process tree under `pid`, in bytes.
function rss(pid) {
  const all = [];
  for (const entry of readdirSync('/proc')) {
    try {
      const stat = readFileSync(`/proc/${entry}/stat`, 'utf8');
      const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
      all.push({ pid: Number(entry), ppid: Number(fields[1]), rss: Number(fields[21]) * 4096 });
    } catch {}
  }
  const tree = all.filter((p) => p.pid === pid);
  for (let i = 0; i < tree.length; i++) tree.push(...all.filter((p) => p.ppid === tree[i].pid));
  return tree.reduce((sum, p) => sum + p.rss, 0);
}

/// A headless browser saving downloads into `downloads` without asking.
function launch(name, url, downloads) {
  const profile = mkdtempSync(join(tmpdir(), `download-${name}-`));
  let args;
  if (name === 'firefox') {
    const prefs = {
      'browser.download.dir': downloads,
      'browser.download.folderList': 2,
      'browser.download.useDownloadDir': true,
      'browser.download.always_ask_before_handling_new_types': false,
      'browser.helperApps.neverAsk.saveToDisk': 'application/octet-stream',
    };
    const lines = Object.entries(prefs).map(([key, value]) => `user_pref(${JSON.stringify(key)}, ${JSON.stringify(value)});`);
    writeFileSync(join(profile, 'user.js'), lines.join('\n'));
    args = ['--headless', '--no-remote', '--profile', profile, url];
  } else {
    mkdirSync(join(profile, 'Default'));
    const prefs = { download: { default_directory: downloads, prompt_for_download: false } };
    writeFileSync(join(profile, 'Default', 'Preferences'), JSON.stringify(prefs));
    args = ['--headless=new', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', url];
  }
  const child = spawn(browsers[name], args, { stdio: 'ignore', detached: true });
  return {
    pid: child.pid,
    close() {
      try {
        process.kill(-child.pid, 'SIGKILL');
      } catch {}
      rmSync(profile, { recursive: true, force: true });
    },
  };
}

/// Whether `file` holds `mib` MiB, the nth filled with n.
function intact(file, mib) {
  if (statSync(file).size !== mib * MiB) return false;
  const fd = openSync(file, 'r');
  const chunk = Buffer.alloc(MiB);
  try {
    for (let n = 0; n < mib; n++) {
      readSync(fd, chunk, 0, MiB, n * MiB);
      if (!chunk.equals(Buffer.alloc(MiB, n & 255))) return false;
    }
    return true;
  } finally {
    closeSync(fd);
  }
}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
let said = [];
const server = createServer(async (request, response) => {
  const path = request.url.split('?')[0];
  if (request.method === 'POST') {
    said.push(Buffer.concat(await Array.fromAsync(request)).toString());
    return response.end();
  }
  const [type, body] = FILES[path] ?? (/^\/(download|download_sw|trusted_types)\.js$/.test(path) ? ['text/javascript'] : []);
  if (!type) return response.writeHead(404).end();
  response.writeHead(200, { 'content-type': type, 'content-security-policy': CSP });
  response.end(body ?? readFileSync(join(web, path)));
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}/`;

let failed = false;
for (const { browser, mib, every = 0, abort } of CASES) {
  const what = `${browser}: ${mib} MiB${every ? ` over ${(mib * every) / 1000} s` : ''}${abort ? `, aborted after ${abort}` : ''}`;
  if (!browsers[browser]) {
    console.error(`FAIL: ${what}: no ${browser} (set ${browser.toUpperCase()}_EXECUTABLE)`);
    failed = true;
    continue;
  }
  const downloads = mkdtempSync(join(tmpdir(), 'downloads-'));
  said = [];
  const started = performance.now();
  const instance = launch(browser, `${origin}?mib=${mib}&every=${every}${abort ? `&abort=${abort}` : ''}`, downloads);
  let base, peak = 0;
  try {
    for (const deadline = started + 60000 + mib * (every + 50); ; await sleep(100)) {
      if (performance.now() > deadline) {
        const files = readdirSync(downloads).map((f) => `${f} (${statSync(join(downloads, f)).size} B)`);
        throw new Error(`timed out with ${files.join(', ') || 'no file'}; the page said ${said.join(', ') || 'nothing'}`);
      }
      const error = said.find((s) => s.startsWith('error'));
      if (error) throw new Error(`the page: ${error}`);
      if (said.includes('started')) {
        base ??= rss(instance.pid);
        peak = Math.max(peak, rss(instance.pid));
      }
      if (abort && said.includes('written')) {
        await sleep(3000);
        const left = readdirSync(downloads).map((f) => `${f} (${statSync(join(downloads, f)).size} B)`);
        if (left.length) throw new Error(`the aborted download left ${left.join(', ')}`);
        break;
      }
      const files = readdirSync(downloads);
      if (!abort && files.length === 1 && files[0] === NAME && statSync(join(downloads, NAME)).size === mib * MiB) {
        if (!intact(join(downloads, NAME), mib)) throw new Error('the file is not what the page wrote');
        break;
      }
    }
    const grown = (peak - base) / MiB;
    if (!abort && mib >= 1024 && grown > mib / 4) throw new Error(`the browser grew by ${grown.toFixed(0)} MiB`);
    console.log(`ok: ${what}, in ${((performance.now() - started) / 1000).toFixed(1)} s; the browser grew by ${grown.toFixed(0)} MiB`);
  } catch (error) {
    console.error(`FAIL: ${what}: ${error.message}`);
    failed = true;
  } finally {
    instance.close();
    rmSync(downloads, { recursive: true, force: true });
  }
}
server.close();
process.exit(failed ? 1 : 0);
