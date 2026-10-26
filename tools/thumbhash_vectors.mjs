// Writes testdata/thumbhash.json: images encoded and hashes decoded by ThumbHash's reference implementation
// (Evan Wallace's `thumbhash` on npm, MIT), which every ThumbHash in Photolib must match.
//
//   node tools/thumbhash_vectors.mjs
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const REFERENCE = 'thumbhash@0.1.1'
const dir = mkdtempSync(join(tmpdir(), 'thumbhash-'))
try {
  execFileSync('npm', ['install', '--prefix', dir, '--ignore-scripts', '--no-audit', '--no-fund', REFERENCE])
  const th = await import(pathToFileURL(join(dir, 'node_modules/thumbhash/thumbhash.js')))
  const image = (w, h, pixel) => {
    const rgba = new Uint8Array(w * h * 4)
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) rgba.set(pixel(x, y), (y * w + x) * 4)
    return { w, h, rgba }
  }
  // Noise keeps every term of the transform away from zero, where a cosine's last bit in another libm would round
  // a factor the other way.
  const noise = (x, y) => ((x * 73856093) ^ (y * 19349663)) % 17 - 8
  const byte = v => Math.max(0, Math.min(255, Math.round(v)))
  const images = {
    'landscape gradient': image(40, 30, (x, y) => [x * 255 / 39, y * 255 / 29, 128, 255].map((v, i) =>
      i < 3 ? byte(v + noise(x, y + i)) : v)),
    'portrait rings': image(30, 45, (x, y) => {
      const d = Math.hypot(x - 13.7, y - 21.2)
      return [byte(128 + 127 * Math.cos(d / 4)), byte(90 + 60 * Math.sin(y / 9) + noise(x, y)), byte(200 - 3 * d), 255]
    }),
    'photo-like': image(60, 45, (x, y) => [
      byte(120 + 60 * Math.sin(x / 7) + 40 * Math.cos(y / 5) + noise(x, y)),
      byte(140 + 50 * Math.cos((x + y) / 11)),
      byte(90 + 70 * Math.sin((x - y) / 13) * Math.cos(x / 17)),
      255,
    ]),
    'alpha disc': image(32, 32, (x, y) =>
      [230, byte(40 + 5 * x + noise(x, y)), 30 + 6 * y, byte(255 - 18 * Math.hypot(x - 13.3, y - 17.6))]),
    'stripes': image(17, 13, (x, y) => (x * x + 3 * y) % 5 < 2 ? [250, 250, 245, 255] : [byte(20 + noise(x, y)), 10, 5, 255]),
    'small': image(9, 8, (x, y) => [byte(128 + 15 * noise(x, y)), byte(128 + 15 * noise(y, x)), byte(64 + 9 * noise(x, 2 * y)), 255]),
    'transparent': image(8, 8, () => [10, 20, 30, 0]),
  }
  const b64 = bytes => Buffer.from(bytes).toString('base64')
  const cases = Object.entries(images).map(([name, { w, h, rgba }]) => {
    const hash = th.rgbaToThumbHash(w, h, rgba)
    const decoded = th.thumbHashToRGBA(hash)
    return {
      name, w, h, rgba: b64(rgba), hash: b64(hash),
      average: th.thumbHashToAverageRGBA(hash),
      aspect: th.thumbHashToApproximateAspectRatio(hash),
      decoded: { w: decoded.w, h: decoded.h, rgba: b64(decoded.rgba) },
    }
  })
  writeFileSync(new URL('../testdata/thumbhash.json', import.meta.url),
    JSON.stringify({ reference: REFERENCE, cases }, null, 1) + '\n')
} finally {
  rmSync(dir, { recursive: true, force: true })
}
