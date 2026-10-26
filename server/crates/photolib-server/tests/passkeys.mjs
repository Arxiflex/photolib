// The passkey relay in a real browser (ADR-0088), driven as a desktop app drives it: ask photolibd for a ceremony, open
// /passkey in Chrome with a loopback return address, receive the credential there and finish the ceremony. Chrome runs
// headless with a virtual authenticator over the DevTools protocol (--remote-debugging-pipe: NUL-separated JSON on
// fds 3 and 4). Usage: node passkeys.mjs <server URL> <session token>; prints {"session": <token of the passkey sign-in>}.
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [server, token] = process.argv.slice(2);
const profile = mkdtempSync(join(tmpdir(), 'passkeys-'));
const chrome = spawn(
  process.env.CHROME_EXECUTABLE || 'google-chrome',
  [
    '--headless=new', '--no-sandbox', '--disable-gpu', '--no-first-run', '--disable-background-networking',
    '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1', '--remote-debugging-pipe',
    `--user-data-dir=${profile}`,
  ],
  { stdio: ['ignore', 'ignore', 'inherit', 'pipe', 'pipe'], detached: true },
);
const waiting = new Map();
// The page's uncaught errors, unhandled rejections and console.error calls fail the run.
const logged = [];
const events = {
  'Runtime.exceptionThrown': ({ exceptionDetails: { exception, text } }) => logged.push(`uncaught: ${exception?.description ?? text}`),
  'Runtime.consoleAPICalled': ({ type, args }) =>
    type === 'error' && logged.push(`console.error: ${args.map((arg) => arg.value ?? arg.description).join(' ')}`),
};
let [sent, received] = [0, ''];
chrome.stdio[4].on('data', (chunk) => {
  received += chunk;
  for (let end; (end = received.indexOf('\0')) >= 0; received = received.slice(end + 1)) {
    const { id, result, error, method, params } = JSON.parse(received.slice(0, end));
    events[method]?.(params);
    waiting.get(id)?.(error ? Promise.reject(new Error(JSON.stringify(error))) : result);
  }
});
const clean = () => {
  if (logged.length) throw new Error(`the relay page logged: ${logged.join('\n')}`);
};
const send = (method, params = {}, sessionId) =>
  new Promise((resolve, reject) => {
    waiting.set(++sent, resolve);
    chrome.stdio[3].write(`${JSON.stringify({ id: sent, method, params, sessionId })}\0`);
    setTimeout(() => reject(new Error(`${method} got no answer`)), 30_000).unref();
  });

async function until(test, what) {
  for (const deadline = Date.now() + 30_000; !(await test()); await new Promise((r) => setTimeout(r, 100))) {
    if (Date.now() > deadline) throw new Error(`timed out waiting for ${what}`);
  }
}

async function call(method, body, bearer) {
  const headers = { 'content-type': 'application/json', ...(bearer && { authorization: `Bearer ${bearer}` }) };
  const response = await fetch(`${server}/photolib.api.v1.AuthService/${method}`, { method: 'POST', headers, body: JSON.stringify(body) });
  const answer = await response.json();
  if (!response.ok) throw new Error(`${method}: ${JSON.stringify(answer)}`);
  return answer;
}

const returned = [];
const app = createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  if (url.pathname === '/passkey') returned.push(url);
  response.end();
});
await new Promise((resolve) => app.listen(0, '127.0.0.1', resolve));
const back = `http://127.0.0.1:${app.address().port}/passkey`;

try {
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  const page = (method, params) => send(method, params, sessionId);
  const value = async (expression) => (await page('Runtime.evaluate', { expression, userGesture: true })).result.value;
  await page('Runtime.enable');
  await page('WebAuthn.enable', { enableUI: false });
  const options = { protocol: 'ctap2', transport: 'internal', hasResidentKey: true, hasUserVerification: true };
  await page('WebAuthn.addVirtualAuthenticator', { options: { ...options, isUserVerified: true, automaticPresenceSimulation: true } });
  // Each ceremony opens the relay afresh, as an app's browser view does; a new fragment alone reloads nothing.
  const open = async (fragment) => {
    await page('Page.navigate', { url: 'about:blank' });
    await page('Page.navigate', { url: `${server}/passkey#${new URLSearchParams(fragment)}` });
    await until(() => value(`location.href.startsWith('${server}/passkey#') && document.readyState === 'complete'`), 'the relay');
    clean();
  };
  const relay = async (op, options) => {
    await open({ op, options, return: back, label: 'Continue' });
    await value(`document.getElementById('go').click()`);
    await until(() => returned.length > 0, 'the return address');
    const answer = returned.shift().searchParams;
    if (!answer.has('credential')) throw new Error(`the relay returned ${answer || 'nothing'}`);
    return answer.get('credential');
  };

  await open({ op: 'get', options: '{}', return: 'https://elsewhere.example/' });
  if (!(await value(`document.getElementById('go').hidden`))) throw new Error('the relay offered to answer another site');
  const setup = await call('StartPasskeySetup', {}, token);
  const credentialJson = await relay('create', setup.optionsJson);
  await call('FinishPasskeySetup', { setupId: setup.setupId, credentialJson, name: 'Chrome' }, token);
  const login = await call('StartPasskeyLogin', {});
  const asserted = await relay('get', login.optionsJson);
  const device = { name: 'Chrome', platform: 'linux' };
  const { session } = await call('FinishPasskeyLogin', { loginId: login.loginId, credentialJson: asserted, device });
  clean();
  console.log(JSON.stringify({ session: session.token }));
} finally {
  app.close();
  // Chrome's helpers, in its process group, still write to the profile after the browser exits: kill them all, then
  // remove the profile until nothing comes back.
  const exited = chrome.exitCode ?? chrome.signalCode ?? new Promise((resolve) => chrome.once('exit', resolve));
  try {
    process.kill(-chrome.pid, 'SIGKILL');
  } catch {}
  await exited;
  await until(() => {
    try {
      return !rmSync(profile, { recursive: true, force: true });
    } catch {
      return false;
    }
  }, 'the profile to be removed');
}
