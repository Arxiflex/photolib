import 'package:fixnum/fixnum.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

/// A server for the app: records each call as `Service/Method` with its
/// request, and answers from [answers] (a thrown [CallError] fails the call,
/// a future answers once it completes) or else with an empty message.
class FakeServer implements Link {
  new([Map<String, Object Function(GeneratedMessage)>? answers])
    : answers = {...standard, ...?answers};

  final Map<String, Object Function(GeneratedMessage)> answers;
  final calls = <(String, GeneratedMessage)>[];

  /// The requests made of [method], oldest first.
  List<T> requests<T extends GeneratedMessage>(String method) => [
    for (final (name, request) in calls)
      if (name == method) request as T,
  ];

  @override
  Future<T> invoke<T extends GeneratedMessage>(
    ClientContext? ctx,
    String serviceName,
    String methodName,
    GeneratedMessage request,
    T emptyResponse,
  ) async {
    final method = '$serviceName/$methodName';
    calls.add((method, request));
    var answer = answers[method]?.call(request);
    if (answer is Future) answer = await answer;
    if (answer is CallError) throw answer;
    return emptyResponse
      ..mergeFromMessage(answer as GeneratedMessage? ?? emptyResponse);
  }

  /// The files [media] streams, by path; any other is not found.
  final files = <String, List<int>>{};

  @override
  Future<Media> media(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final file = files[path] ?? (throw ServerError('not_found', null));
    return (
      status: 200,
      etag: null,
      bytes: Stream.value(file),
      length: file.length,
    );
  }

  /// The paths [sign] signed.
  final signed = <String>[];

  @override
  Future<Uri> sign(String path) async {
    signed.add(path);
    return Uri.parse('https://photos.example.org/$path?t=signed');
  }

  /// The uploads [sendUpload] took, whole.
  final uploads =
      <({int length, String blake3, String? path, List<int> sent})>[];

  /// The name of a file whose upload is refused.
  String? refuseUpload;
  final _created = <String, ({int length, String blake3, String? path})>{};

  @override
  Future<String> createUpload(int length, String blake3, {String? path}) async {
    if (path != null && path == refuseUpload) {
      throw ServerError('permission_denied', ErrorDetail(code: 'upload.quota'));
    }
    final location = '/upload/${_created.length + 1}';
    _created[location] = (length: length, blake3: blake3, path: path);
    return location;
  }

  @override
  Future<void> sendUpload(
    String path,
    int length,
    Stream<List<int>> Function(int offset) read,
  ) async {
    final sent = [await for (final chunk in read(0)) ...chunk];
    final created = _created[path]!;
    uploads.add((
      length: created.length,
      blake3: created.blake3,
      path: created.path,
      sent: sent,
    ));
  }

  /// How often the network changed.
  int networkChanges = 0;

  @override
  void networkChanged() => networkChanges++;

  @override
  void close() {}

  static final Timestamp at = Timestamp.fromDateTime(
    DateTime.utc(2026, 5, 1, 14, 30),
  );

  /// A small server, which signs in with passwords: two accounts, a library,
  /// a backup, a dead job, a paused type, a store, a damaged file and an
  /// orphan, and a silent device.
  static final standard = <String, Object Function(GeneratedMessage)>{
    'ServerInfoService/GetServerInfo': (_) => GetServerInfoResponse(
      epoch: 'instance-a.0',
      authMethods: [AuthMethod.AUTH_METHOD_OPAQUE],
    ),
    'AdminService/GetStatus': (_) => GetStatusResponse(
      accounts: [
        AccountUsage(
          handle: 'ann',
          assetCount: Int64(1200),
          sizeBytes: Int64(3400000000),
        ),
      ],
      files: [
        FileUsage(
          role: 'thumb_s',
          fileCount: Int64(1200),
          sizeBytes: Int64(12000000),
        ),
      ],
      libraries: [
        LibraryStatus(
          libraryId: 'lib-1',
          name: 'Photos',
          ownerHandle: 'ann',
          kind: LibraryKind.LIBRARY_KIND_MANAGED,
          state: LibraryState.LIBRARY_STATE_ONLINE,
          assetCount: Int64(1200),
        ),
      ],
      backups: [
        Backup(
          name: 'backups/backup-20260501T143000Z.dump',
          sizeBytes: Int64(5000000),
          createdAt: at,
          store: 'local',
        ),
      ],
      pauses: [JobPause(type: 'render', untilAt: at)],
      findings: [
        IntegrityFinding(
          store: 'local',
          key: 'libraries/lib-1/originals/2026/2026-04/IMG_0042.HEIC',
          kind: FindingKind.FINDING_KIND_CONTENT,
          foundAt: at,
          fileName: 'IMG_0042.HEIC',
          ownerHandle: 'ann',
        ),
        IntegrityFinding(
          store: 'b2',
          key: 'libraries/lib-1/originals/stray.jpg',
          kind: FindingKind.FINDING_KIND_ORPHAN,
          foundAt: at,
        ),
      ],
      scrubs: [
        StoreScrub(store: 'b2'),
        StoreScrub(store: 'local', cycleEndedAt: at),
      ],
      deviceBackups: [
        DeviceBackup(
          name: 'Pixel 8',
          ownerHandle: 'ann',
          lastSeenAt: at,
          reportedAt: at,
          pendingCount: Int64(12),
          silent: true,
        ),
        DeviceBackup(
          name: 'iPad',
          ownerHandle: 'bob',
          lastSeenAt: at,
          reportedAt: at,
        ),
      ],
    ),
    'AdminService/ListJobs': (_) => ListJobsResponse(
      jobs: [
        Job(
          jobId: 'job-1',
          type: 'render',
          status: JobStatus.JOB_STATUS_DEAD,
          attempts: 5,
          error: 'boom',
        ),
        Job(jobId: 'job-2', type: 'embed', status: JobStatus.JOB_STATUS_QUEUED),
      ],
    ),
    'UserService/ListUsers': (_) => ListUsersResponse(
      users: [
        User(
          userId: 'u-1',
          handle: 'ann',
          displayName: 'Ann',
          role: UserRole.USER_ROLE_ADMIN,
          status: UserStatus.USER_STATUS_ACTIVE,
        ),
      ],
    ),
    'AdminService/ListStores': (_) => ListStoresResponse(
      stores: [
        StoreStatus(
          name: 'local',
          status: CheckStatus.CHECK_STATUS_OK,
          detail: 'online',
          freeBytes: Int64(2000000000),
        ),
      ],
    ),
    'AdminService/ListAuditEvents': (_) => ListAuditEventsResponse(
      events: [
        AuditEvent(
          sequence: Int64(7),
          recordedAt: at,
          actorUserId: 'u-1',
          action: 'job.pause',
          targetJson: '{"type": "render"}',
          detailsJson: 'null',
        ),
      ],
    ),
    'AdminService/TailLogs': (_) =>
        TailLogsResponse(lines: ['started', 'listening']),
    'AdminService/GetSettings': (_) => GetSettingsResponse(
      settings: Settings(
        trashRetentionDays: 60,
        minFreeDiskPercent: 5,
        minFreeDiskGb: 20,
        scrubDays: 90,
        backupSilentHours: 48,
      ),
    ),
    'AdminService/GetPolicy': (_) => GetPolicyResponse(
      switches: [
        for (final capability in Capability.values.skip(1))
          PolicySwitch(
            capability: capability,
            enabled: true,
            source: PolicySource.POLICY_SOURCE_DEFAULT,
          ),
      ],
    ),
    'AdminService/GetDiagnostics': (_) => GetDiagnosticsResponse(
      checks: [
        Check(
          name: 'postgres',
          status: CheckStatus.CHECK_STATUS_WARN,
          detail: 'data checksums are off',
        ),
      ],
      bundleJson: '{"photolibd": "0.0.0"}',
    ),
    'AdminService/Reprocess': (_) => ReprocessResponse(jobCount: Int64(2)),
  };
}
