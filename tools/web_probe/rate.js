/** How many times per second `work` completes, run one at a time for `ms` milliseconds. */
export async function rate(ms, work) {
  const start = performance.now();
  let count = 0;
  for (; performance.now() - start < ms; count++) await work();
  return Math.round((count * 1000) / (performance.now() - start));
}
