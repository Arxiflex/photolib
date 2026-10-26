// What tools/web_e2e/run.mjs and cold_start.mjs share: the builds they need and the browsers they drive.
import { spawnSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = join(dirname(fileURLToPath(import.meta.url)), '../..');

export function run(command, args, options = {}) {
  // A cold `cargo build --message-format=json` prints well over spawnSync's default 1 MB: a full buffer kills the build
  // with no status and no message.
  const result = spawnSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], maxBuffer: 1 << 30, ...options });
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')} failed (${result.error?.code ?? result.signal ?? result.status})`);
  return result.stdout.trim();
}

/** The app's build, photolibd and the directory of an FFmpeg, each from the environment or built here. */
export function build() {
  let { WEB_DIR: web, PHOTOLIBD: photolibd, FFMPEG_DIR: ffmpegDir } = process.env;
  if (!web) {
    run('bash', [join(root, 'tools/data/web.sh'), join(root, 'app/web')]);
    run('bash', [join(root, 'tools/hls/web.sh'), join(root, 'app/web')]);
    run('bash', [join(root, 'tools/kernel/wasm.sh'), join(root, 'app/web/kernel')]);
    web = mkdtempSync(join(tmpdir(), 'photolib-web-'));
    run('flutter', ['build', 'web', '--wasm', '--output', web], { cwd: join(root, 'app') });
  }
  photolibd ||= run('cargo', ['build', '--locked', '-q', '--manifest-path', join(root, 'server/Cargo.toml'), '-p', 'photolib-server', '--bin', 'photolibd', '--message-format=json'])
    .split('\n')
    .map((line) => JSON.parse(line))
    .find((message) => message.reason === 'compiler-artifact' && message.executable)?.executable;
  ffmpegDir ||= run('bash', [join(root, 'tools/video/ffmpeg.sh')]);
  return { web, photolibd, ffmpegDir };
}

/** Starts `type` (a Playwright browser type) headless; Chrome is `CHROME_EXECUTABLE`'s, the others are fetched on first use. */
export async function launch(type, name) {
  const options = {
    headless: true,
    args: name === 'chromium' ? ['--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'] : [],
    executablePath: name === 'chromium' ? process.env.CHROME_EXECUTABLE : undefined,
  };
  try {
    return await type.launch(options);
  } catch (error) {
    if (!String(error).includes("Executable doesn't exist")) throw error;
    run('bash', [join(root, 'tools/playwright.sh'), 'install', name]);
    return type.launch(options);
  }
}

// The library of tools/playwright.sh's pinned install, or `PLAYWRIGHT_DIR`'s.
const library = process.env.PLAYWRIGHT_DIR ?? run('bash', [join(root, 'tools/playwright.sh'), '--dir']);
export const { chromium, devices, firefox, webkit } = await import(join(library, 'index.mjs'));
