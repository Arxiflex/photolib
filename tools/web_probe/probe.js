// The media probe that tools/web_requests.py opens in each browser: what the browser offers the web app
// (docs/user/browsers.md), how fast each decoder turns a thumbnail into pixels, and two uploads of `upload` bytes in
// appends of `append` bytes from a worker. It posts the results to /probe/result, then opens the app.
import { rate } from "./rate.js";

const MS = 500;
const IMAGE_TYPES = ["jpeg", "png", "webp", "gif", "avif", "heic", "jxl"];
const CODECS = {
  "H.264": 'video/mp4; codecs="avc1.640028"',
  HEVC: 'video/mp4; codecs="hvc1.1.6.L120.90"',
  VP9: 'video/mp4; codecs="vp09.00.40.08"',
  AV1: 'video/mp4; codecs="av01.0.08M.08"',
  AAC: 'audio/mp4; codecs="mp4a.40.2"',
  Opus: 'audio/mp4; codecs="opus"',
};

let worker;
let calls = 0;
const call = (task, input) =>
  new Promise((resolve, reject) => {
    const id = ++calls;
    worker.addEventListener("message", function reply({ data }) {
      if (data.id !== id) return;
      worker.removeEventListener("message", reply);
      "error" in data ? reject(new Error(data.error)) : resolve(data.output);
    });
    worker.postMessage({ id, task, input });
  });

async function features() {
  const source = globalThis.ManagedMediaSource ?? globalThis.MediaSource;
  const decodes = async (type) => typeof ImageDecoder === "function" && ImageDecoder.isTypeSupported(`image/${type}`);
  const decoded = await Promise.all(IMAGE_TYPES.map(decodes));
  return {
    WasmGC: WebAssembly.validate(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 95, 1, 120, 0])),
    ImageDecoder: IMAGE_TYPES.filter((_, i) => decoded[i]),
    "native HLS": document.createElement("video").canPlayType("application/vnd.apple.mpegurl"),
    MSE: source ? Object.keys(CODECS).filter((codec) => source.isTypeSupported(CODECS[codec])) : [],
    ManagedMediaSource: typeof ManagedMediaSource === "function",
    "WebCodecs video": typeof VideoDecoder === "function",
    OPFS: typeof navigator.storage?.getDirectory === "function",
    SharedWorker: typeof SharedWorker === "function",
    "Web Locks": typeof navigator.locks?.request === "function",
    "File System Access": typeof showDirectoryPicker === "function",
    webkitdirectory: "webkitdirectory" in document.createElement("input"),
    WebGPU: "gpu" in navigator,
    "Trusted Types": typeof trustedTypes === "object",
    "cross-origin isolated": crossOriginIsolated,
    ...(await call("features")),
  };
}

/** A 256 px photo-like thumbnail, a gradient with noise that JPEG and WebP cannot compress away, in both formats. */
async function thumbnails() {
  const canvas = new OffscreenCanvas(256, 256);
  const context = canvas.getContext("2d");
  const image = context.createImageData(256, 256);
  for (let i = 0; i < image.data.length; i += 4) {
    const noise = Math.random() * 64;
    image.data.set([((i / 4) % 256) + noise, i / 1024 + noise, 96 + noise, 255], i);
  }
  context.putImageData(image, 0, 0);
  const blobs = {};
  for (const [format, type] of [["JPEG", "image/jpeg"], ["WebP", "image/webp"]]) {
    const blob = await canvas.convertToBlob({ type, quality: 0.8 });
    if (blob.type === type) blobs[format] = blob;
  }
  return blobs;
}

/** Decodes per second of each thumbnail with each decoder: the browser's, in the page and in a worker, WebCodecs'
 * ImageDecoder (which Flutter uses in Chromium) and CanvasKit's own codecs (which it uses elsewhere). */
async function decodes(blobs) {
  const canvasKit = await (await import("/canvaskit/canvaskit.js")).default({ locateFile: (f) => `/canvaskit/${f}` });
  const result = {};
  for (const [format, blob] of Object.entries(blobs)) {
    const data = new Uint8Array(await blob.arrayBuffer());
    result[format] = {
      bytes: blob.size,
      createImageBitmap: await rate(MS, async () => (await createImageBitmap(blob)).close()),
      "createImageBitmap in a worker": await call("decode", { blob, ms: MS }),
      ImageDecoder:
        typeof ImageDecoder === "function"
          ? await rate(MS, async () => {
              const decoder = new ImageDecoder({ data, type: blob.type });
              (await decoder.decode()).image.close();
              decoder.close();
            })
          : null,
      CanvasKit: await rate(MS, () => {
        const animated = canvasKit.MakeAnimatedImageFromEncoded(data);
        animated.makeImageAtCurrentFrame().delete();
        animated.delete();
      }),
    };
  }
  return result;
}

const params = new URLSearchParams(location.search);
const [size, append] = [Number(params.get("upload")), Number(params.get("append"))];
let result;
try {
  // The string URL goes through the app's default Trusted Types policy (app/web/trusted_types.js).
  worker = new Worker("worker.js", { type: "module" });
  result = { features: await features(), decodes: await decodes(await thumbnails()), upload: {} };
  for (const [name, read] of [["slices", false], ["bytes", true]]) {
    result.upload[name] = await call("upload", { name, size, append, read });
  }
} catch (error) {
  result = { error: String(error) };
}
await fetch("/probe/result", { method: "POST", body: JSON.stringify(result) });
location.href = "/";
