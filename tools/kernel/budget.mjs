// The kernel's web budget (ADR-0004): node budget.mjs <file>... fails when the files, brotli-compressed as a server
// sends them, exceed 1 MB together.
import { readFileSync } from 'node:fs';
import { brotliCompressSync } from 'node:zlib';

const budget = 1_000_000;
const size = process.argv.slice(2).reduce((sum, file) => sum + brotliCompressSync(readFileSync(file)).length, 0);
console.log(`kernel for the web: ${size} bytes brotli, budget ${budget}`);
if (size > budget) {
  console.error(`over budget by ${size - budget} bytes`);
  process.exit(1);
}
