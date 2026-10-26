// The server's side of errors.js for the node drivers.
import { readFileSync } from 'node:fs';

const script = readFileSync(new URL('errors.js', import.meta.url));

/** Answers a request for /errors.js, or one that posts an error to /errors, which goes to `report`; else false. */
export async function pageErrors(request, response, report) {
  const path = request.url.split('?')[0];
  if (path === '/errors.js') {
    response.writeHead(200, { 'content-type': 'text/javascript' });
    response.end(script);
    return true;
  }
  if (path !== '/errors' || request.method !== 'POST') return false;
  report(Buffer.concat(await Array.fromAsync(request)).toString());
  response.end();
  return true;
}
