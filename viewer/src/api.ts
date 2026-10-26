// The viewer's client of photolibd's Connect API, over the browser's fetch: the browser owns TLS, so a private CA or a
// client certificate must be installed in the browser or the operating system (design 10 §9).
import {
  create,
  type DescMessage,
  type DescMethodUnary,
  fromBinary,
  type MessageInitShape,
  type MessageShape,
  toBinary,
} from "@bufbuild/protobuf";
import { base64Decode } from "@bufbuild/protobuf/wire";

import { type ErrorDetail, ErrorDetailSchema } from "./gen/photolib/api/v1/error_pb.ts";

/** photolibd's answer: a Connect code, and the reason and parameters the viewer renders in its reader's language. */
export class ServerError extends Error {
  constructor(
    readonly code: string,
    readonly detail?: ErrorDetail,
  ) {
    super(`photolibd answered ${code}`);
  }

  /** True only for an explicit revocation: `unauthenticated` with a reason code. */
  get logsOut(): boolean {
    return this.code === "unauthenticated" && this.detail !== undefined;
  }
}

/** No answer from photolibd: a timeout, a network or TLS failure, or a page from something in between, such as a
 * reverse proxy's 502 or 504 or a captive portal. The viewer goes offline; it never logs out. */
export class Unreachable extends Error {
  readonly logsOut = false;
  constructor(cause: unknown) {
    super(`photolibd is unreachable: ${String(cause)}`, { cause });
  }
}

export interface Options {
  /** Headers for every HTTPS request, such as a Cloudflare Access token; a plain-HTTP server gets none, since any
   * machine on its network could answer. */
  headers?: Record<string, string>;
  /** The longest wait for the response headers. */
  timeoutMs?: number;
}

const connectCodes = new Set([
  "canceled", "unknown", "invalid_argument", "deadline_exceeded", "not_found", "already_exists", "permission_denied",
  "resource_exhausted", "failed_precondition", "aborted", "out_of_range", "unimplemented", "internal", "unavailable",
  "data_loss", "unauthenticated",
]);

/** One server at `base`: API calls and media. */
export class Server {
  constructor(
    readonly base: string,
    private readonly options: Options = {},
  ) {}

  /** Calls a unary RPC, such as `ServerInfoService.method.getServerInfo`, in binary Connect. */
  async call<I extends DescMessage, O extends DescMessage>(
    method: DescMethodUnary<I, O>,
    request: MessageInitShape<I>,
  ): Promise<MessageShape<O>> {
    const url = this.url(`${method.parent.typeName}/${method.name}`);
    return guard(async () => {
      const response = await this.fetch(url, "POST", {
        "content-type": "application/proto",
        "connect-protocol-version": "1",
      }, toBinary(method.input, create(method.input, request)));
      if (response.status !== 200 || response.headers.get("content-type") !== "application/proto") {
        return failure(response);
      }
      return fromBinary(method.output, new Uint8Array(await response.arrayBuffer()));
    });
  }

  /** Fetches media — a thumbnail, a preview, video bytes; `headers` may ask for a byte range or revalidate (304). */
  async get(path: string, headers: Record<string, string> = {}): Promise<Response> {
    const url = this.url(path);
    return guard(async () => {
      const response = await this.fetch(url, "GET", headers);
      const html = response.headers.get("content-type")?.startsWith("text/html");
      return (response.ok || response.status === 304) && !html ? response : failure(response);
    });
  }

  /** `path` on the server; never another origin, which would get the configured headers. */
  private url(path: string): URL {
    const url = new URL(path, this.base);
    if (url.origin !== new URL(this.base).origin) throw new RangeError(`${path} leaves ${this.base}`);
    return url;
  }

  /** Follows no redirect, which could lead anywhere with the headers. */
  private async fetch(url: URL, method: string, headers: Record<string, string>, body?: Uint8Array<ArrayBuffer>) {
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(new DOMException("no answer", "TimeoutError")), this.options.timeoutMs ?? 30_000);
    try {
      return await fetch(url, {
        method,
        headers: { ...(url.protocol === "https:" ? this.options.headers : {}), ...headers },
        body,
        redirect: "error",
        signal: abort.signal,
      });
    } finally {
      clearTimeout(timeout);
    }
  }
}

/** Runs a call and turns every failure on the way into {@link Unreachable}, but photolibd's own errors. */
async function guard<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch (error) {
    throw error instanceof ServerError || error instanceof Unreachable ? error : new Unreachable(error);
  }
}

/** What a response that is not a success means: photolibd's Connect error, or {@link Unreachable}. */
async function failure(response: Response): Promise<never> {
  const type = response.headers.get("content-type") ?? "";
  const json: unknown = type.startsWith("application/json") ? await response.json().catch(() => undefined) : undefined;
  if (typeof json === "object" && json !== null && "code" in json && connectCodes.has(json.code as string)) {
    throw new ServerError(json.code as string, "details" in json ? detail(json.details) : undefined);
  }
  await response.body?.cancel();
  throw new Unreachable(`HTTP ${response.status} ${type}`);
}

function detail(details: unknown): ErrorDetail | undefined {
  for (const detail of Array.isArray(details) ? details : []) {
    if (detail?.type === "photolib.api.v1.ErrorDetail" && typeof detail.value === "string") {
      return fromBinary(ErrorDetailSchema, base64Decode(detail.value));
    }
  }
  return undefined;
}
