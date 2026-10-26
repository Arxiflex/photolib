/// A stand-in photolibd for sync and backup tests, in the VM only:
/// GetServerInfo, CheckHashes over `SyncServer.hashes`, PushMutations through
/// `SyncServer.onPush`, ReportBackup into `SyncServer.backupReports`,
/// resumable uploads into `SyncServer.uploads`, SyncService.Sync over each
/// stream's scripted log of batches, whose cursor is the epoch and how many of
/// its batches a device has applied, gzipping messages of 1 KiB and more when
/// the device accepts it, as photolibd does, and `/events`, whose hints the
/// test sends.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_api/src/gen/photolib/api/v1/auth.pb.dart';
import 'package:photolib_api/src/gen/photolib/api/v1/error.pb.dart';
import 'package:photolib_api/src/gen/photolib/api/v1/server_info.pb.dart';
import 'package:photolib_api/src/gen/photolib/api/v1/sync.pb.dart';
import 'package:photolib_api/src/gen/photolib/sync/v1/sync.pb.dart';

/// The stand-in photolibd, on a loopback port.
class SyncServer {
  new _(this._http);
  final HttpServer _http;

  /// Starts one.
  static Future<SyncServer> start() async =>
      SyncServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
        .._listen();

  /// Where it answers.
  Uri get url => Uri.parse('http://127.0.0.1:${_http.port}/');

  /// Its epoch, `<instance id>.<restores>`.
  String epoch = 'instance.0';

  /// What GetServerInfo says it can do.
  final List<String> capabilities = ['sync.hints.v1', 'sync.stream.v1'];

  /// Each stream's log, the changes of a batch each: a `List<Rows>`, or the
  /// `changes` fields of a SyncBatch already encoded, which serve a long log
  /// faster. `Iterable.generate` makes one as it is read.
  final streams = <String, Iterable<Object>>{};

  /// Streams the device may not sync.
  final forbidden = <String>{};

  /// Streams whose cursors are too old: they start again from an empty one.
  final reset = <String>{};

  /// The asset that holds each file, by the file's hash in hex.
  final hashes = <String, String>{};

  /// How many hashes CheckHashes was asked about.
  int checked = 0;

  /// The pending counts ReportBackup was told, in order.
  final backupReports = <int>[];

  /// The Sync requests that arrived.
  final requests = <SyncRequest>[];

  /// After this many batches, Sync ends its answer without photolibd's end of
  /// stream, as a dropped connection does.
  int? dropAfter;

  /// The methods that answer 503, as a server that is restarting does.
  final unavailable = <String>{};

  /// The error that ends every Sync, as photolibd's end of stream carries it.
  Map<String, Object?>? error;

  /// How many messages Sync has sent compressed.
  int compressed = 0;

  /// Runs as each Sync arrives, before it is answered: a restore just then.
  void Function()? onSync;

  /// Answers each PushMutations; null answers 404, as a server without
  /// `sync.mutations.v1` does.
  PushMutationsResponse Function(PushMutationsRequest)? onPush;

  /// Answers each EmptyTrash; null answers 404.
  EmptyTrashResponse Function(EmptyTrashRequest)? onEmptyTrash;

  /// The streams each hints channel followed, in the order they opened.
  final follows = <List<String>>[];
  final _channels = <HttpResponse>[];

  /// Sends every open hints channel an event naming [streams].
  Future<void> hint(Iterable<String> streams) async {
    for (final channel in _channels) {
      channel.write(_event(streams));
      await channel.flush();
    }
  }

  /// Ends every hints channel, as photolibd does when it stops.
  Future<void> endHints() async {
    final open = [..._channels];
    _channels.clear();
    await Future.wait(open.map((channel) => channel.close()));
  }

  /// The uploads created, in order; an upload's path is `upload/<its index>`.
  final uploads = <StandInUpload>[];

  /// Runs as the bytes of an append from an offset arrive; false drops them
  /// and answers 503, as a connection that broke on the way does.
  bool Function(StandInUpload upload, int offset)? onAppend;

  /// The Connect code and reason of photolibd's refusal of new uploads, such
  /// as `quota.exceeded`.
  (String, String)? refuseUploads;

  /// Every call but GetServerInfo is answered as photolibd answers a revoked
  /// session.
  bool revoked = false;

  /// Stops it, dropping the connections it holds.
  Future<void> close() => _http.close(force: true);

  void _listen() => _http.listen((request) async {
    final body = (await request.fold(
      BytesBuilder(copy: false),
      (all, chunk) => all..add(chunk),
    )).takeBytes();
    final response = request.response;
    final segments = request.uri.pathSegments;
    if (unavailable.contains(segments.last)) {
      response.statusCode = 503;
      return await response.close();
    }
    if (revoked && !request.uri.path.endsWith('/GetServerInfo')) {
      return await _refuse(response, 401, 'unauthenticated', 'session.revoked');
    }
    if (segments.first == 'upload') {
      final id = segments.length > 1 ? segments[1] : null;
      return await _upload(request, body, id);
    }
    switch (request.uri.path) {
      case '/photolib.api.v1.ServerInfoService/GetServerInfo':
        response.headers.contentType = ContentType('application', 'proto');
        response.add(
          GetServerInfoResponse(
            epoch: epoch,
            capabilities: capabilities,
          ).writeToBuffer(),
        );
      case '/photolib.api.v1.SyncService/CheckHashes':
        final asked = CheckHashesRequest.fromBuffer(body);
        checked += asked.hashes.length;
        response.headers.contentType = ContentType('application', 'proto');
        response.add(
          CheckHashesResponse(
            assetIds: [for (final h in asked.hashes) hashes[_hex(h)] ?? ''],
          ).writeToBuffer(),
        );
      case '/photolib.api.v1.SyncService/PushMutations':
        final push = onPush;
        if (push == null) {
          response.statusCode = 404;
        } else {
          response.headers.contentType = ContentType('application', 'proto');
          response.add(
            push(PushMutationsRequest.fromBuffer(body)).writeToBuffer(),
          );
        }
      case '/photolib.api.v1.SyncService/EmptyTrash':
        final empty = onEmptyTrash;
        if (empty == null) {
          response.statusCode = 404;
        } else {
          response.headers.contentType = ContentType('application', 'proto');
          response.add(
            empty(EmptyTrashRequest.fromBuffer(body)).writeToBuffer(),
          );
        }
      case '/photolib.api.v1.AuthService/ReportBackup':
        backupReports.add(
          ReportBackupRequest.fromBuffer(body).pendingCount.toInt(),
        );
        response.headers.contentType = ContentType('application', 'proto');
        response.add(ReportBackupResponse().writeToBuffer());
      case '/photolib.api.v1.SyncService/Sync':
        return await _sync(request, body);
      case '/events':
        return _channels.add(await _follow(request));
      default:
        response.statusCode = 404;
    }
    await response.close();
  });

  /// Answers a Sync with each asked stream's batches, as photolibd does.
  Future<void> _sync(HttpRequest request, Uint8List body) async {
    final response = request.response;
    final asked = SyncRequest.fromBuffer(body.sublist(5));
    requests.add(asked);
    onSync?.call();
    response.headers.contentType = ContentType('application', 'connect+proto');
    final gzipped = (request.headers.value('connect-accept-encoding') ?? '')
        .contains('gzip');
    if (gzipped) response.headers.set('connect-content-encoding', 'gzip');
    void send(int flags, List<int> message) {
      final squeeze = gzipped && message.length >= 1024;
      if (squeeze) compressed++;
      response.add(
        squeeze
            ? envelope(flags | 1, gzip.encode(message))
            : envelope(flags, message),
      );
    }

    var sent = 0;
    for (final batch in asked.streams.expand(_batches)) {
      if (sent++ == dropAfter) return await response.close();
      send(0, batch);
      await response.flush();
    }
    send(2, utf8.encode(jsonEncode({'error': ?error})));
    await response.close();
  }

  /// Opens a hints channel with an event naming the streams it may follow.
  Future<HttpResponse> _follow(HttpRequest request) async {
    final named = request.uri.queryParameters['streams'] ?? '';
    final followed = [
      for (final s in named.split(','))
        if (s.isNotEmpty) s,
    ];
    follows.add(followed);
    final response = request.response
      ..bufferOutput = false
      ..headers.contentType = ContentType('text', 'event-stream')
      ..write(
        _event(
          followed.where(
            (s) => streams.containsKey(s) && !forbidden.contains(s),
          ),
        ),
      );
    await response.flush();
    return response;
  }

  /// An event of hints, as photolibd sends it.
  static String _event(Iterable<String> streams) =>
      '${streams.map((s) => 'data: $s\n').join()}\n';

  Future<void> _upload(HttpRequest request, Uint8List body, String? id) async {
    final response = request.response;
    String header(String name) => request.headers.value(name) ?? '';
    if (id == null) {
      if (refuseUploads case (final code, final reason)) {
        return await _refuse(response, 403, code, reason);
      }
      uploads.add(
        StandInUpload(
          int.parse(header('upload-length')),
          header('photolib-hash'),
          library: request.headers.value('photolib-library'),
          path: request.headers.value('photolib-path'),
        ),
      );
      response
        ..statusCode = 201
        ..headers.set('location', 'upload/${uploads.length - 1}');
      return await response.close();
    }
    final upload = uploads.elementAtOrNull(int.tryParse(id) ?? -1);
    if (upload == null) {
      return await _refuse(response, 404, 'not_found', 'upload.not_found');
    }
    if (request.method == 'PATCH') {
      final offset = int.parse(header('upload-offset'));
      if (offset != upload.bytes.length || upload.complete) {
        response.statusCode = 409;
        return await response.close();
      }
      if (onAppend?.call(upload, offset) == false) {
        response.statusCode = 503;
        return await response.close();
      }
      upload.bytes.add(body);
      upload.complete =
          header('upload-complete') == '?1' &&
          upload.bytes.length == upload.length;
    }
    response
      ..statusCode = 204
      ..headers.set('upload-offset', '${upload.bytes.length}')
      ..headers.set('upload-complete', upload.complete ? '?1' : '?0');
    await response.close();
  }

  Future<void> _refuse(
    HttpResponse response,
    int status,
    String code,
    String reason,
  ) async {
    final detail = ErrorDetail(code: reason).writeToBuffer();
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'code': code,
          'details': [
            {
              'type': 'photolib.api.v1.ErrorDetail',
              'value': base64.encode(detail),
            },
          ],
        }),
      );
    await response.close();
  }

  /// The SyncResponses of a stream, encoded.
  Iterable<Uint8List> _batches(StreamCursor at) sync* {
    Uint8List batch(StreamStatus status, [Object? changes, int? applied]) {
      final head = SyncBatch(
        stream: at.stream,
        status: status,
        changes: changes is List<Rows> ? changes : null,
        cursor: applied == null ? null : utf8.encode('$epoch $applied'),
        caughtUp: changes == null,
      ).writeToBuffer();
      final batch = BytesBuilder(copy: false)..add(head);
      if (changes is Uint8List) batch.add(changes);
      final response = BytesBuilder(copy: false)..addByte(0x0a);
      for (var n = batch.length; ; n >>= 7) {
        response.addByte(n < 0x80 ? n : n & 0x7f | 0x80);
        if (n < 0x80) break;
      }
      return (response..add(batch.takeBytes())).takeBytes();
    }

    final log = streams[at.stream];
    if (log == null || forbidden.contains(at.stream)) {
      yield batch(StreamStatus.STREAM_STATUS_FORBIDDEN);
      return;
    }
    final [cursorEpoch, applied] = at.cursor.isEmpty
        ? [epoch, '0']
        : utf8.decode(at.cursor).split(' ');
    final from = int.parse(applied);
    if (cursorEpoch != epoch ||
        from > log.length ||
        (from > 0 && reset.contains(at.stream))) {
      yield batch(StreamStatus.STREAM_STATUS_RESET_REQUIRED);
      return;
    }
    for (var i = from; i < log.length; i++) {
      yield batch(StreamStatus.STREAM_STATUS_OK, log.elementAt(i), i + 1);
    }
    yield batch(StreamStatus.STREAM_STATUS_OK, null, log.length);
  }
}

/// A Connect stream's message: its flags, its length in four bytes,
/// big-endian, and its bytes.
Uint8List envelope(int flags, List<int> message) =>
    Uint8List(5 + message.length)
      ..[0] = flags
      ..buffer.asByteData().setUint32(1, message.length)
      ..setRange(5, 5 + message.length, message);

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// An upload the stand-in photolibd holds: what its creation announced, and
/// the bytes that arrived.
class StandInUpload {
  /// An upload of [length] bytes whose BLAKE3 is [hash], in hex.
  new(this.length, this.hash, {this.library, this.path});

  /// What its creation announced.
  final int length;

  /// The BLAKE3 its creation announced, in hex.
  final String hash;

  /// The library it is for; none for the account's upload destination.
  final String? library;

  /// The file's path below its folder.
  final String? path;

  /// What arrived.
  final BytesBuilder bytes = BytesBuilder();

  /// Whether its last append arrived.
  bool complete = false;
}
