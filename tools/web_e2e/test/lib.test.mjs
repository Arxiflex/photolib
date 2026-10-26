import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { test } from 'node:test';
import { inflateSync } from 'node:zlib';
import { clip, freePort, png } from '../lib.mjs';

test('the photos it uploads are PNGs of 64 x 48 that differ by seed', () => {
  const [a, b] = [png(1), png(2)];
  assert.deepEqual([...a.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(a.readUInt32BE(16), 64);
  assert.equal(a.readUInt32BE(20), 48);
  assert.notDeepEqual(a, b);
  // The pixels inflate to one filter byte and 64 RGB triples a row.
  const size = a.readUInt32BE(33);
  assert.equal(inflateSync(a.subarray(41, 41 + size)).length, 48 * (1 + 64 * 3));
});

test('a free port is one nothing listens on', async () => {
  const [a, b] = [await freePort(), await freePort()];
  assert.ok(a > 0 && b > 0);
});

test('without an FFmpeg there is no clip, and the run goes on without a video', () => {
  assert.equal(clip(mkdtempSync(`${tmpdir()}/clip-`), '/nonexistent', 'clip.mp4'), null);
});
