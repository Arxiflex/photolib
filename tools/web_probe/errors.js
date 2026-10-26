// Posts the page's uncaught errors, unhandled rejections and console.error calls to /errors, one text each: the browser
// drivers fail on them (tools/web_requests.py, tools/playback/bench.mjs, tools/video/play.mjs; errors_test.mjs).
{
  const report = (text) =>
    fetch("/errors", { method: "POST", body: `page ${location.pathname}: ${text}`, keepalive: true }).catch(() => {});
  // An object logged beside a message, such as a log record's fields, shows as JSON.
  const show = (value) => {
    if (value === null || typeof value !== "object" || value instanceof Error) return String(value);
    try {
      return JSON.stringify(value);
    } catch {
      return String(value);
    }
  };
  addEventListener("error", (event) => report(`uncaught: ${event.message}`));
  addEventListener("unhandledrejection", (event) => report(`unhandled rejection: ${event.reason}`));
  const logError = console.error;
  console.error = (...args) => {
    report(`console.error: ${args.map(show).join(" ")}`);
    logError.apply(console, args);
  };
}
