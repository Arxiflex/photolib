# viewer/

The lightweight TypeScript viewer that renders public links and static exports, so recipients do not have to load
the Flutter web app.

## Architecture

* A small TypeScript and WASM bundle (initial load under 200 KB): justified grid, story layout with text blocks,
  full-screen viewer with zoom, video streaming, download and comments.
* The kernel runs in the viewer as WASM, so crypto and metadata rules are the ones the server and the apps use: the
  ES module that `tools/kernel/wasm.sh` builds for Flutter web too, with its TypeScript types.
  Generated API types come from `proto/` into `viewer/src/gen`.
* For private (end-to-end encrypted) albums the decryption key travels in the URL fragment and never reaches the
  server.
* The `api` role serves the viewer; static exports bundle it.

## Contents

* `src/api.ts`: the client of photolibd's Connect API over the browser's fetch: `Server.call` takes a generated method
  (`ServerInfoService.method.getServerInfo`), `Server.get` fetches media. Only an `unauthenticated` error with a
  reason logs out; a proxy's error page, a timeout or a network failure is `Unreachable`, and the viewer goes offline.
* `src/gen`: the generated messages; `test/`: `node:test` tests against a stand-in for photolibd.
* `npm ci`, then `npm run typecheck` and `npm test`; Node is pinned in `.nvmrc`. TypeScript stays on 6.x, which runs
  from node: 7.x starts a native binary, which a checkout on a `noexec` mount cannot run.

## Design

* Sharing
* Security, privacy and E2EE
