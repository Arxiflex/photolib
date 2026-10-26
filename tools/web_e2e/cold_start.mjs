// The web app's cold start (NFR-PERF-2, budget `cold-start` of tools/perf/budgets.json on the `web` target): the time
// from opening photolibd's address in Chrome, with nothing cached, to the first frame the engine draws, the fastest of
// three, which must be within the budget; printed as a result line, as perf.py's are. Needs the same builds as run.mjs.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { startServer } from './lib.mjs';
import { build, chromium, launch, root } from './setup.mjs';

const budget = JSON.parse(readFileSync(join(root, 'tools/perf/budgets.json'), 'utf8')).budgets['cold-start'].metrics.first_frame.max.web;

const built = build();
const server = await startServer(built);
const browser = await launch(chromium, 'chromium');
const times = [];
try {
  for (let run = 0; run < 3; run++) {
    // A context of its own: nothing cached, no service worker.
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();
    await page.addInitScript(() => {
      window.addEventListener('flutter-first-frame', () => (window.__firstFrame = performance.now()));
    });
    await page.goto(server.url, { waitUntil: 'load' });
    await page.waitForFunction(() => window.__firstFrame, null, { timeout: 120_000 });
    times.push(await page.evaluate(() => window.__firstFrame));
    await context.close();
  }
} finally {
  await browser.close();
  await server.stop();
}
console.error(`cold start: ${times.map((time) => `${time.toFixed(0)} ms`).join(', ')}`);
const value = Math.round(Math.min(...times) * 100) / 100;
console.log(JSON.stringify({ budget: 'cold-start', metric: 'first_frame', target: 'web', value }));
if (value > budget) {
  console.error(`FAIL: cold-start first_frame on the web: ${value} ms (budget ≤ ${budget} ms)`);
  process.exit(1);
}
console.error(`ok: cold-start first_frame on the web: ${value} ms (budget ≤ ${budget} ms)`);
