// errors.js and errors.mjs, the page-error capture of the browser drivers, in Chrome and Firefox on a page that fails
// on purpose. tools/tests/test_web_requests.sh runs it: node --test tools/web_probe/errors_test.mjs
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { pageErrors } from './errors.mjs';

const which = (name) => spawnSync('sh', ['-c', `command -v ${name}`], { encoding: 'utf8' }).stdout.trim();
const browsers = {
  chrome: process.env.CHROME_EXECUTABLE || which('google-chrome') || which('chromium'),
  firefox: process.env.FIREFOX_EXECUTABLE || which('firefox'),
};
const page = '<!doctype html><script src="/errors.js"></script><script src="/fail.js"></script>';
const fail = `console.error('on', 'purpose', { field: 1 }); Promise.reject(new Error('a rejection'));
  throw new Error('uncaught');`;

for (const [name, executable] of Object.entries(browsers)) {
  test(`${name} reports what a page logs as an error`, async () => {
    assert.ok(executable, `${name} is required: put it on PATH or set ${name.toUpperCase()}_EXECUTABLE`);
    const logged = [];
    const server = createServer(async (request, response) => {
      if (await pageErrors(request, response, (text) => logged.push(text))) return;
      response.writeHead(200, { 'content-type': request.url === '/' ? 'text/html' : 'text/javascript' });
      response.end(request.url === '/' ? page : fail);
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const url = `http://127.0.0.1:${server.address().port}/`;
    const profile = mkdtempSync(join(tmpdir(), `errors-${name}-`));
    const args =
      name === 'firefox'
        ? ['--headless', '--no-remote', '--profile', profile, url]
        : ['--headless=new', '--no-sandbox', '--no-first-run', `--user-data-dir=${profile}`, url];
    const browser = spawn(executable, args, { stdio: 'ignore', detached: true });
    try {
      for (const deadline = Date.now() + 60_000; logged.length < 3 && Date.now() < deadline; )
        await new Promise((resolve) => setTimeout(resolve, 100));
    } finally {
      try {
        process.kill(-browser.pid, 'SIGKILL');
      } catch {}
      server.close();
      rmSync(profile, { recursive: true, force: true });
    }
    assert.deepEqual(logged.toSorted().map((text) => text.replace('Uncaught Error', 'Error')), [
      'page /: console.error: on purpose {"field":1}',
      'page /: uncaught: Error: uncaught',
      'page /: unhandled rejection: Error: a rejection',
    ]);
  });
}
