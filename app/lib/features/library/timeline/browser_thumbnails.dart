import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:photolib/core/logging.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib_data/browser.dart';
import 'package:web/web.dart' as web;

const _log = Logger('photolib.workers');

/// Browsers' decoders of the files [open] gives (docs/10-client-app.md §7.2,
/// ADR-0107), in a worker: WebCodecs' ImageDecoder where it takes the type,
/// else createImageBitmap, resized there so that the short side is at the
/// tier, never larger. The bitmap moves to the page and becomes an image
/// without a copy. A format the browser cannot decode is [NoThumbnail]; a
/// video is [browserPosters]'. [imageDecoder] off is createImageBitmap alone.
///
/// A HEIF still that neither decoder takes (HEIC outside Safari) is decoded
/// with WebCodecs where the system has its codec, as macOS and Windows have
/// HEVC for video: the worker asks the kernel's module at [kernel] (default
/// the app's own, `kernel/photolib_kernel_wasm.js`) where the coded images
/// are, decodes each as a keyframe, and composes, crops, turns and resizes
/// them (ADR-0387). Where the browser cannot decode the codec, the file is
/// marked and its reason names HEVC and the two ways out.
Thumbnailer browserThumbnails(
  Future<web.Blob?> Function(ThumbnailItem item) open, {
  bool imageDecoder = true,
  String? kernel,
}) => Thumbnailer('browser', (item, tier, cancelled) async {
  if (item.video) return null;
  final file = await open(item);
  if (file == null) return null;
  return Pixels.decoded(
    await _decode(
      file,
      tier,
      item: item,
      imageDecoder: imageDecoder,
      kernel: kernel ?? _kernelModule,
    ),
  );
});

final _kernelModule = Uri.base
    .resolve('kernel/photolib_kernel_wasm.js')
    .toString();

/// [encoded], a tile or a poster's JPEG, decoded by createImageBitmap in the
/// worker of [browserThumbnails] wherever Flutter's codec would decode it
/// with CanvasKit on the page, the UI thread: web tiers 2 and 3 (ADR-0056).
/// Null on Chromium, tier 1, where Flutter's codec is WebCodecs' ImageDecoder.
Future<ui.Image>? browserImage(Uint8List encoded, int tier) =>
    ui_web.browser.browserEngine == ui_web.BrowserEngine.blink
    ? null
    : _decode(web.Blob([encoded.toJS].toJS), tier);

web.Worker? _worker;
final _replies = <int, Completer<JSObject>>{};
var _next = 0;

Future<ui.Image> _decode(
  web.Blob blob,
  int tier, {
  ThumbnailItem? item,
  bool imageDecoder = false,
  String? kernel,
}) async {
  final worker = _worker ??=
      web.Worker(
          web.URL
              .createObjectURL(
                web.Blob(
                  [_script.toJS].toJS,
                  web.BlobPropertyBag(type: 'text/javascript'),
                ),
              )
              .toJS,
        )
        ..onmessage = (web.MessageEvent event) {
          final reply = event.data as JSObject?;
          if (reply == null) return;
          _replies
              .remove((reply['id'] as JSNumber?)?.toDartInt)
              ?.complete(reply);
        }.toJS
        ..onerror = (web.Event event) {
          _log.error(
            'thumbnail worker failed',
            error: (event as JSObject)['message'].dartify() ?? event.type,
          );
        }.toJS;
  if (_next == 0) _log.debug('thumbnail worker started');
  final id = _next++;
  final reply = (_replies[id] = Completer()).future;
  worker.postMessage(
    JSObject()
      ..['id'] = id.toJS
      ..['file'] = blob
      ..['tier'] = tier.toJS
      ..['decoder'] = imageDecoder.toJS
      ..['kernel'] = kernel?.toJS,
  );
  final answer = await reply;
  _log.debug(
    'browser decode',
    fields: {
      if (item != null) 'file': '$item',
      'via': (answer['via'] as JSString?)?.toDart,
      'type': blob.type,
      'bytes': blob.size,
      if (answer['checks'] case final JSNumber checks)
        'support_checks': checks.toDartInt,
    },
  );
  if (answer['refused'] case final JSString why) {
    throw NoThumbnail(cause: why.toDart);
  }
  if (answer['bitmap'] case final bitmap?) {
    return await ui_web.createImageFromImageBitmap(bitmap);
  }
  throw StateError('${(answer['error'] as JSString?)?.toDart}');
}

/// Poster frames of the videos [open] gives, from the browser's own player
/// (ADR-0116), with their durations; a video it cannot play is marked so.
Thumbnailer browserPosters(Future<web.Blob?> Function(ThumbnailItem) open) =>
    Thumbnailer('player', (item, tier, cancelled) async {
      final file = item.video ? await open(item) : null;
      if (file == null) return null;
      try {
        final poster = await browserPoster(file, tier, cancelled: cancelled);
        return Pixels.encoded(poster.bytes, duration: poster.duration);
      } on Unplayable catch (e) {
        throw NoThumbnail(
          video: true,
          unplayable: true,
          duration: e.duration,
          cause: e.cause,
        );
      }
    });

const _script = r'''
// HEIF stills go through the kernel's ReadHeif (WASM, loaded here) and WebCodecs: the browser has no HEIC decoder
// but, on macOS and Windows, a system HEVC decoder for video (M1-43, ADR-0387).
const cannot = (codec) => `this browser cannot decode ${codec}; the desktop app and a connected server show it`;
const CODECS = ["", "HEVC", "AV1", "AVC"];
const supported = new Map();
let checks = 0;
let kernel;

const varint = (n) => {
  const out = [];
  while (n >= 128) { out.push((n % 128) | 128); n = Math.floor(n / 128); }
  out.push(n);
  return out;
};
const concat = (parts) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
};
const number = (field, n) => Uint8Array.from([...varint(field << 3), ...varint(n)]);
const bytes = (field, data) => concat([Uint8Array.from([...varint(field << 3 | 2), ...varint(data.length)]), data]);

// The fields of a protobuf message as [field, value]: a varint is a number (signed 64-bit), anything else bytes.
const fields = (data) => {
  const out = [];
  let at = 0;
  const read = () => {
    let n = 0n, shift = 0n, byte;
    do { byte = data[at++]; n |= BigInt(byte & 127) << shift; shift += 7n; } while (byte & 128);
    return Number(BigInt.asIntN(64, n));
  };
  while (at < data.length) {
    const key = read(), wire = key & 7;
    if (wire === 0) out.push([key >> 3, read()]);
    else if (wire === 2) { const length = read(); out.push([key >> 3, data.subarray(at, at + length)]); at += length; }
    else throw new Error("unexpected protobuf wire type " + wire);
  }
  return out;
};
const text = new TextDecoder();
const decodeImage = (data) => {
  const image = { spans: [] };
  for (const [f, v] of fields(data)) {
    if (f === 1) image.codec = v;
    else if (f === 2) image.codecString = text.decode(v);
    else if (f === 3) image.config = v;
    else if (f === 4) image.width = v;
    else if (f === 5) image.height = v;
    else if (f === 6) { const s = fields(v); image.spans.push({ offset: s.find((x) => x[0] === 1)?.[1] ?? 0, length: s.find((x) => x[0] === 2)?.[1] ?? 0 }); }
  }
  return image;
};
const decodePicture = (data) => {
  const p = { tiles: [], rows: 0, columns: 0, rotation: 0, mirror: null, clap: null, image: null, width: 0, height: 0 };
  for (const [f, v] of fields(data)) {
    if (f === 1) p.width = v;
    else if (f === 2) p.height = v;
    else if (f === 3) p.image = decodeImage(v);
    else if (f === 4) p.rows = v;
    else if (f === 5) p.columns = v;
    else if (f === 6) p.tiles.push(decodeImage(v));
    else if (f === 7) { const c = Object.fromEntries(fields(v)); p.clap = { w: (c[1] ?? 0) / (c[2] || 1), h: (c[3] ?? 0) / (c[4] || 1), x: (c[5] ?? 0) / (c[6] || 1), y: (c[7] ?? 0) / (c[8] || 1) }; }
    else if (f === 8) p.rotation = v & 3;
    else if (f === 9) p.mirror = v;
  }
  return p;
};
const decodeHeif = (data) => {
  const r = { missing: [], status: 0, itemType: "", picture: null, thumbnail: null };
  for (const [f, v] of fields(data)) {
    if (f === 1) { const s = Object.fromEntries(fields(v)); r.missing.push([s[1] ?? 0, s[2] ?? 0]); }
    else if (f === 2) r.status = v;
    else if (f === 3) r.itemType = text.decode(v);
    else if (f === 4) r.picture = decodePicture(v);
    else if (f === 5) r.thumbnail = decodePicture(v);
  }
  return r;
};

const loadKernel = (url) => kernel ??= import(url).then(async (m) => { await m.default(); return m; }, (error) => { kernel = undefined; throw error; });
const slice = async (file, offset, length) => new Uint8Array(await file.slice(offset, offset + length).arrayBuffer());

// What the kernel says of the file's HEIF items, asking for the ranges it misses: null when it is no HEIF file.
const readHeif = async (file, url) => {
  const module = await loadKernel(url);
  const ranges = new Map([[0, await slice(file, 0, Math.min(file.size, 65536))]]);
  for (let round = 0; round < 8; round++) {
    const request = concat([...[...ranges].map(([offset, data]) => bytes(1, concat([number(1, offset), bytes(2, data)]))), number(2, file.size)]);
    let answer;
    try { answer = module.call(43, request); } catch (error) { kernel = undefined; throw error; }
    const call = fields(answer);
    const response = call.find((f) => f[0] === 1);
    if (!response) throw new Error("the kernel refused the request");
    const heif = decodeHeif(response[1]);
    const fresh = heif.missing.filter(([offset, length]) => offset < file.size && !ranges.has(offset) && length > 0);
    if (heif.status !== 2 || !fresh.length) return heif;
    for (const [offset, length] of fresh) ranges.set(offset, await slice(file, offset, Math.min(length, file.size - offset)));
  }
  return null;
};

const hex = (data) => Array.from(data, (b) => b.toString(16).padStart(2, "0")).join("");
// VideoDecoder.isConfigSupported, once for each codec configuration in the session.
const canDecode = (image) => {
  const key = image.codecString + ":" + hex(image.config);
  if (!supported.has(key)) {
    checks++;
    supported.set(key, VideoDecoder.isConfigSupported({ codec: image.codecString, description: image.config })
      .then((r) => r.supported, () => false));
  }
  return supported.get(key);
};

// The coded image as a VideoFrame: one keyframe.
const decodeFrame = async (image, file, decoders) => {
  const key = image.codecString + ":" + hex(image.config);
  let decoder = decoders.get(key);
  if (!decoder) {
    const state = { frames: [], error: null };
    decoder = { state, video: new VideoDecoder({ output: (f) => state.frames.push(f), error: (e) => { state.error = e; } }), next: 0 };
    decoder.video.configure({ codec: image.codecString, description: image.config, codedWidth: image.width, codedHeight: image.height });
    decoders.set(key, decoder);
  }
  const data = await new Blob(image.spans.map((s) => file.slice(s.offset, s.offset + s.length))).arrayBuffer();
  decoder.video.decode(new EncodedVideoChunk({ type: "key", timestamp: decoder.next++, data }));
  await decoder.video.flush();
  if (decoder.state.error) throw decoder.state.error;
  const frame = decoder.state.frames.shift();
  if (!frame) throw new Error("the decoder gave no frame");
  return frame;
};

// The picture as a canvas, then cropped (clap), turned (irot) and mirrored (imir) as it is shown, at the tier.
const compose = async (picture, file, tier) => {
  const decoders = new Map();
  try {
    let width = picture.width, height = picture.height, canvas;
    if (picture.image) {
      const frame = await decodeFrame(picture.image, file, decoders);
      width = width || frame.displayWidth; height = height || frame.displayHeight;
      canvas = new OffscreenCanvas(width, height);
      canvas.getContext("2d").drawImage(frame, 0, 0);
      frame.close();
    } else {
      canvas = new OffscreenCanvas(width, height);
      const context = canvas.getContext("2d");
      const [tileWidth, tileHeight] = [picture.tiles[0].width, picture.tiles[0].height];
      for (const [i, tile] of picture.tiles.entries()) {
        const frame = await decodeFrame(tile, file, decoders);
        context.drawImage(frame, 0, 0, Math.min(tile.width, frame.displayWidth), Math.min(tile.height, frame.displayHeight),
          (i % picture.columns) * tileWidth, Math.floor(i / picture.columns) * tileHeight,
          Math.min(tile.width, frame.displayWidth), Math.min(tile.height, frame.displayHeight));
        frame.close();
      }
    }
    return finish(canvas, width, height, picture, tier);
  } finally {
    for (const { video } of decoders.values()) { try { video.close(); } catch { /* already closed */ } }
  }
};

const finish = (canvas, width, height, picture, tier) => {
  let [x, y, w, h] = [0, 0, width, height];
  if (picture.clap) {
    const c = picture.clap;
    [w, h] = [Math.max(1, Math.round(c.w)), Math.max(1, Math.round(c.h))];
    [x, y] = [Math.round(width / 2 + c.x - c.w / 2), Math.round(height / 2 + c.y - c.h / 2)];
  }
  const turned = picture.rotation & 1;
  const [shownWidth, shownHeight] = turned ? [h, w] : [w, h];
  const scale = Math.min(1, tier / Math.min(shownWidth, shownHeight));
  const out = new OffscreenCanvas(Math.max(1, Math.round(shownWidth * scale)), Math.max(1, Math.round(shownHeight * scale)));
  const turn = [[1, 0, 0, 1, 0, 0], [0, -1, 1, 0, 0, w], [-1, 0, 0, -1, w, h], [0, 1, -1, 0, h, 0]][picture.rotation & 3];
  let matrix = new DOMMatrix([out.width / shownWidth, 0, 0, out.height / shownHeight, 0, 0]);
  if (picture.mirror === 0) matrix = matrix.multiply(new DOMMatrix([1, 0, 0, -1, 0, shownHeight]));
  if (picture.mirror === 1) matrix = matrix.multiply(new DOMMatrix([-1, 0, 0, 1, shownWidth, 0]));
  matrix = matrix.multiply(new DOMMatrix(turn)).translate(-x, -y);
  const context = out.getContext("2d");
  context.imageSmoothingQuality = "high";
  context.setTransform(matrix);
  context.drawImage(canvas, 0, 0);
  return out.transferToImageBitmap();
};

// An ISO base media file, which a HEIF still is: only these ask for the kernel.
const looksHeif = async (file) => text.decode((await slice(file, 4, 4))) === "ftyp";

const heic = async (file, tier, url) => {
  const heif = await readHeif(file, url);
  if (!heif || heif.status !== 1) return null;
  const small = heif.thumbnail && Math.min(heif.thumbnail.width, heif.thumbnail.height) >= tier;
  const picture = small ? heif.thumbnail : heif.picture;
  const first = picture.image ?? picture.tiles[0];
  if (!(await canDecode(first))) return { unsupported: CODECS[first.codec] || "this codec" };
  return { bitmap: await compose(picture, file, tier), via: "WebCodecs" };
};

onmessage = async ({ data: { id, file, tier, decoder, kernel: url } }) => {
  let source, via = "createImageBitmap";
  const name = file.name ?? "tile";
  try {
    if (decoder && self.ImageDecoder && (await ImageDecoder.isTypeSupported(file.type).catch(() => false))) {
      via = "ImageDecoder";
      const images = new ImageDecoder({ data: file.stream(), type: file.type });
      try {
        source = (await images.decode()).image;
      } finally {
        images.close();
      }
    } else {
      source = await createImageBitmap(file);
    }
  } catch (error) {
    // The browser has no decoder for it: a HEIF still is decoded with WebCodecs where the system has the codec.
    const heif = url && (await looksHeif(file).catch(() => false));
    if (heif && self.VideoDecoder) {
      try {
        const found = await heic(file, tier, url);
        if (found?.bitmap) return postMessage({ id, via: found.via, checks, bitmap: found.bitmap }, [found.bitmap]);
        if (found?.unsupported) {
          return postMessage({ id, via: "WebCodecs", checks, refused: `${name}: ${cannot(found.unsupported)}` });
        }
      } catch (failure) {
        return postMessage({ id, via: "WebCodecs", checks, refused: `${name}: ${failure}` });
      }
    } else if (heif) {
      return postMessage({ id, via, checks, refused: `${name}: ${cannot("HEVC")}` });
    }
    return postMessage({ id, via, checks, refused: `${name}: ${error}` });
  }
  try {
    const width = source.displayWidth ?? source.width, height = source.displayHeight ?? source.height;
    const scale = Math.min(1, tier / Math.min(width, height));
    const bitmap = await createImageBitmap(source, {
      resizeWidth: Math.max(1, Math.round(width * scale)),
      resizeHeight: Math.max(1, Math.round(height * scale)),
      resizeQuality: "medium",
    });
    postMessage({ id, via, checks, bitmap }, [bitmap]);
  } catch (error) {
    postMessage({ id, via, checks, error: `${name}: ${error}` });
  } finally {
    source.close();
  }
};
''';
