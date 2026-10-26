// The viewer's API client against a stand-in for photolibd behind a reverse proxy. The browser owns TLS, so a private
// CA and client certificates are the browser's (design 10 §9); what the client decides is when to give up and when to
// log out.
import assert from "node:assert/strict";
import { createServer, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";

import { create, toBinary } from "@bufbuild/protobuf";
import { base64Encode } from "@bufbuild/protobuf/wire";

import { Server, ServerError, Unreachable } from "../src/api.ts";
import { ErrorDetailSchema } from "../src/gen/photolib/api/v1/error_pb.ts";
import { GetServerInfoResponseSchema, ServerInfoService } from "../src/gen/photolib/api/v1/server_info_pb.ts";

type Answer = (response: ServerResponse) => void;

const media = Uint8Array.from({ length: 100 }, (_, i) => i);
const photolibd: Answer = (response) => {
  const info = create(GetServerInfoResponseSchema, { apiVersion: "1.0", epoch: "instance-a" });
  response.writeHead(200, { "content-type": "application/proto" }).end(toBinary(GetServerInfoResponseSchema, info));
};
const page = (status: number): Answer => (response) =>
  response.writeHead(status, { "content-type": "text/html" }).end(`<html><h1>${status}</h1><hr>nginx</html>`);
const connectError = (status: number, code: string, reason?: string, params: Record<string, string> = {}): Answer =>
  (response) => {
    const value = reason && base64Encode(toBinary(ErrorDetailSchema, create(ErrorDetailSchema, { code: reason, params })), "std_raw");
    const details = value ? [{ type: "photolib.api.v1.ErrorDetail", value }] : undefined;
    response.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify({ code, details }));
  };

let answer: Answer = photolibd;
const seen: string[] = [];
const http = createServer((request, response) => {
  seen.push(`${request.method} ${request.url} ${request.headers["cf-access-token"]} ${request.headers.range}`);
  if (request.url?.startsWith("/media/") && answer === photolibd) {
    if (request.headers["if-none-match"] === '"m1"') response.writeHead(304, { etag: '"m1"' }).end();
    else response.writeHead(206, { "content-type": "image/webp", etag: '"m1"' }).end(media.subarray(10, 20));
  } else {
    answer(response);
  }
});
let server: Server;
// A loaded machine takes its time; the timeout passes only on the fake clock of the tests that test it.
const timeoutMs = 30_000;
before(async () => {
  await new Promise<void>((listening) => http.listen(0, "127.0.0.1", listening));
  const { port } = http.address() as AddressInfo;
  server = new Server(`http://127.0.0.1:${port}/`, { headers: { "cf-access-token": "token" }, timeoutMs });
});
after(() => http.close(() => {}).closeAllConnections());

const serverInfo = () => server.call(ServerInfoService.method.getServerInfo, {});

test("calls the API in binary Connect and fetches media, without the headers over plain HTTP", async () => {
  answer = photolibd;
  assert.equal((await serverInfo()).epoch, "instance-a");
  assert.deepEqual(new Uint8Array(await (await server.get("media/1/thumb_s", { range: "bytes=10-19" })).arrayBuffer()), media.subarray(10, 20));
  assert.deepEqual(seen.slice(-2), [
    "POST /photolib.api.v1.ServerInfoService/GetServerInfo undefined undefined",
    "GET /media/1/thumb_s undefined bytes=10-19",
  ]);
});

for (const [name, notPhotolibd] of [
  ["a reverse proxy's 502 page", page(502)],
  ["a reverse proxy's 504 page", page(504)],
  ["a reverse proxy's 401 page", page(401)],
  ["a captive portal's page", page(200)],
] as const) {
  test(`${name} is unreachable and does not log out`, async () => {
    answer = notPhotolibd;
    for (const call of [serverInfo, () => server.get("media/1/thumb_s")]) {
      await assert.rejects(call(), (error) => error instanceof Unreachable && !error.logsOut);
    }
  });
}

test("no answer within the timeout is unreachable and does not log out", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  for (const call of [serverInfo, () => server.get("media/1/thumb_s")]) {
    const heard = new Promise<void>((resolve) => (answer = () => resolve()));
    const failed = assert.rejects(call(), (error) =>
      error instanceof Unreachable && !error.logsOut && (error.cause as Error).name === "TimeoutError");
    await heard;
    t.mock.timers.tick(timeoutMs);
    await failed;
  }
});

test("an unauthenticated error without a reason does not log out", async () => {
  answer = connectError(401, "unauthenticated");
  await assert.rejects(serverInfo(), (error) => error instanceof ServerError && !error.logsOut);
});

test("a revoked session, with its reason, logs out", async () => {
  answer = connectError(401, "unauthenticated", "auth.session_revoked");
  await assert.rejects(serverInfo(), (error) => error instanceof ServerError && error.logsOut);
});

test("other errors carry the code, reason and parameters the viewer translates", async () => {
  answer = connectError(404, "not_found", "asset.not_found", { asset_id: "0190a3c2" });
  await assert.rejects(serverInfo(), (error) => {
    assert.ok(error instanceof ServerError);
    assert.deepEqual([error.code, error.detail?.code, error.detail?.params, error.logsOut], [
      "not_found",
      "asset.not_found",
      { asset_id: "0190a3c2" },
      false,
    ]);
    return true;
  });
});

test("never sends a request, with the configured headers, outside the server", async () => {
  const before = seen.length;
  for (const path of ["//elsewhere.example/x", "https://elsewhere.example/x"]) {
    await assert.rejects(server.get(path), RangeError);
  }
  assert.equal(seen.length, before);
});

test("sends the configured headers over HTTPS only, where TLS proves who answers", async (t) => {
  const sent: RequestInit[] = [];
  t.mock.method(globalThis, "fetch", async (_: URL, init: RequestInit) => {
    sent.push(init);
    return new Response(null, { status: 204 });
  });
  await new Server("https://photos.example/", { headers: { "cf-access-token": "token" } }).get("media/1/thumb_s");
  assert.deepEqual([(sent[0].headers as Record<string, string>)["cf-access-token"], sent[0].redirect], ["token", "error"]);
});

test("follows no redirect, which could take the headers elsewhere", async () => {
  answer = (response) => response.writeHead(302, { location: "/elsewhere" }).end();
  for (const call of [serverInfo, () => server.get("media/1/thumb_s")]) {
    await assert.rejects(call(), Unreachable);
  }
  assert.ok(!seen.some((request) => request.includes("/elsewhere")));
});

test("a 304 Not Modified is an answer", async () => {
  answer = photolibd;
  assert.equal((await server.get("media/1/thumb_s", { "if-none-match": '"m1"' })).status, 304);
});

test("the timeout ends with the response headers, not the body", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  let rest = () => {};
  answer = (response) => {
    response.writeHead(200, { "content-type": "video/mp4" }).write("a");
    rest = () => response.end("b");
  };
  const video = await server.get("media/1/original");
  t.mock.timers.tick(timeoutMs);
  rest();
  assert.equal(await video.text(), "ab");
});
