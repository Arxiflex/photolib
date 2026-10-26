import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/pairing.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

import '../support/console.dart';
import '../support/fake_server.dart';
import '../support/pump_app.dart';

const _scrubDays = 'Days for the scrub to check every original, 1 to 3650';
const _silentHours =
    "Hours without a report until a device's backup is silent, 1 to 8760";

void main() {
  testWidgets('without an administrator signed in the console is hidden', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tapAndSettle(find.byIcon(Icons.settings_outlined));
    await tester.scrollTo(find.text('Diagnostics'));
    expect(find.text('Server administration'), findsNothing);
  });

  testWidgets('an administrator opens the console from the settings', (
    tester,
  ) async {
    await openConsole(tester, FakeServer());
    await section(tester, 'Overview');
    expect(find.text('Usage by account'), findsOneWidget);
    expect(find.text('backup-20260501T143000Z.dump'), findsOneWidget);
    expect(find.textContaining('1,200 items'), findsWidgets);
  });

  testWidgets("lists the account's devices and signs one out", (tester) async {
    final server = FakeServer({
      'AuthService/ListDevices': (_) => ListDevicesResponse(
        devices: [
          Device(
            deviceId: 'd-1',
            name: "Ann's Pixel",
            platform: 'android',
            current: true,
          ),
          Device(
            deviceId: 'd-2',
            name: 'studio',
            platform: 'linux',
            lastSeenAt: FakeServer.at,
          ),
        ],
      ),
    });
    await openConsole(tester, server);
    await section(tester, 'Your devices');
    expect(find.text("Ann's Pixel"), findsOneWidget);
    expect(find.text('android · This device'), findsOneWidget);
    expect(find.textContaining('linux · Last seen '), findsOneWidget);
    await tester.tapAndSettle(find.text('Sign out').last);
    expect(
      server
          .requests<RevokeDeviceRequest>('AuthService/RevokeDevice')
          .single
          .deviceId,
      'd-2',
    );
    expect(
      server.requests<GeneratedMessage>('AuthService/ListDevices'),
      hasLength(2),
    );
  });

  testWidgets('a paused job type shows a banner until it is resumed', (
    tester,
  ) async {
    var paused = true;
    final server = FakeServer({
      'AdminService/GetStatus': (request) {
        final status = FakeServer.standard['AdminService/GetStatus']!(
          request,
        ) as GetStatusResponse;
        if (!paused) status.pauses.clear();
        return status;
      },
      'AdminService/ResumeJobType': (_) {
        paused = false;
        return ResumeJobTypeResponse();
      },
    });
    await openConsole(tester, server);
    expect(find.textContaining('render is paused until'), findsOneWidget);
    await tester.tapAndSettle(find.text('Resume'));
    expect(
      server
          .requests<ResumeJobTypeRequest>('AdminService/ResumeJobType')
          .single
          .type,
      'render',
    );
    expect(find.textContaining('is paused until'), findsNothing);
  });

  testWidgets(
    'the overview shows findings with repairs, scrubs and device backups',
    (tester) async {
      await openConsole(tester, FakeServer());
      await section(tester, 'Overview');
      await tester.scrollUntilVisible(find.text('iPad · bob'), 200);
      // Times are local, so only their place is checked.
      final damaged = [
        '^Damaged · local · .+',
        'libraries/lib-1/originals/2026/2026-04/IMG_0042.HEIC',
        r'Put it back from a backup or from a device that still has it$',
      ].join('\n');
      for (final pattern in [
        'IMG_0042.HEIC · ann',
        damaged,
        'libraries/lib-1/originals/stray.jpg',
        r'^Stray file · b2 · .+\nNo photo names it: check it, then delete or keep it$',
        'First full check under way',
        r'^Last full check .+$',
        'Pixel 8 · ann',
        r'^Silent since .+ · Last seen .+ · 12 items left to back up$',
        r'^Last seen .+ · Nothing left to back up$',
      ]) {
        expect(
          find.textContaining(RegExp(pattern)),
          findsOneWidget,
          reason: pattern,
        );
      }
    },
  );

  testWidgets(
    'reprocessing asks what to redo and sends only the chosen folder',
    (tester) async {
      final server = FakeServer();
      await openConsole(tester, server);
      await section(tester, 'Overview');
      await tester.tapAndSettle(find.text('Reprocess'));
      await tester.enterText(find.byType(TextField).last, ' 2024/05 ');
      await tester.tapAndSettle(find.text('Detect faces again'));
      await tester.tapAndSettle(find.text('OK'));
      final request = server
          .requests<ReprocessRequest>('AdminService/Reprocess')
          .single;
      expect(request.libraryId, 'lib-1');
      expect(request.folder, '2024/05');
      expect(request.assetIds, isEmpty);
      expect(request.kinds, [
        ReprocessKind.REPROCESS_KIND_METADATA,
        ReprocessKind.REPROCESS_KIND_FACES,
      ]);
      expect(find.text('2 jobs queued'), findsOneWidget);
    },
  );

  testWidgets(
    'the overview shows how the restore drills went, backs up now and '
    'restores a backup once asked',
    (tester) async {
      final server = FakeServer({
        'AdminService/GetStatus': (request) {
          final status = FakeServer.standard['AdminService/GetStatus']!(
            request,
          ) as GetStatusResponse;
          return status
            ..lastDrill = BackupRun(
              dump: 'backups/backup-20260501T143000Z.dump',
              detail: 'give the role CREATEDB',
              finishedAt: FakeServer.at,
            )
            ..lastVerifiedRestore = BackupRun(
              ok: true,
              finishedAt: FakeServer.at,
            )
            ..lastRestore = BackupRun(
              dump: 'backups/backup-20260430T030000Z.dump',
              detail: 'pg_restore failed',
            );
        },
        'AdminService/BackUpNow': (_) => BackUpNowResponse(jobId: 'job-9'),
      });
      await openConsole(tester, server);
      await section(tester, 'Overview');
      expect(find.textContaining('Last verified restore: '), findsOneWidget);
      expect(
        find.text('The last restore drill failed: give the role CREATEDB'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The restore of backup-20260430T030000Z.dump failed: '
          'pg_restore failed',
        ),
        findsOneWidget,
      );
      expect(find.text('backup-20260501T143000Z.dump'), findsOneWidget);
      expect(find.textContaining(' · 5 MB · local'), findsOneWidget);

      await tester.tapAndSettle(find.text('Back up now'));
      expect(server.requests<BackUpNowRequest>('AdminService/BackUpNow'), [
        BackUpNowRequest(),
      ]);
      expect(
        find.text('The backup is queued; a restore drill follows it'),
        findsOneWidget,
      );
      // The next message waits for this one to go.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tapAndSettle(find.widgetWithText(TextButton, 'Restore'));
      expect(
        find.textContaining(
          'replaces the whole database with backup-20260501T143000Z.dump',
        ),
        findsOneWidget,
      );
      await tester.tapAndSettle(find.text('Cancel'));
      expect(
        server.requests<GeneratedMessage>('AdminService/RestoreBackup'),
        isEmpty,
      );
      await tester.tapAndSettle(find.widgetWithText(TextButton, 'Restore'));
      await tester.tapAndSettle(find.widgetWithText(FilledButton, 'Restore'));
      final restore = server
          .requests<RestoreBackupRequest>('AdminService/RestoreBackup')
          .single;
      expect(
        (restore.store, restore.name),
        ('local', 'backups/backup-20260501T143000Z.dump'),
      );
      expect(
        find.text('photolibd is stopping to restore the backup'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an external library is added for an account, refused outside the roots '
    'and scanned again',
    (tester) async {
      final refusals = ['library.root_not_allowed', 'library.root_overlaps'];
      final server = FakeServer({
        'AdminService/GetStatus': (request) {
          final status = FakeServer.standard['AdminService/GetStatus']!(
            request,
          ) as GetStatusResponse;
          status.accounts.first.userId = 'user-ann';
          status.libraries.add(
            LibraryStatus(
              libraryId: 'lib-2',
              name: 'NAS',
              ownerHandle: 'ann',
              kind: LibraryKind.LIBRARY_KIND_EXTERNAL,
              state: LibraryState.LIBRARY_STATE_ONLINE,
            ),
          );
          return status;
        },
        'AdminService/CreateExternalLibrary': (_) => refusals.isEmpty
            ? CreateExternalLibraryResponse(libraryId: 'lib-3')
            : ServerError(
                'permission_denied',
                ErrorDetail(code: refusals.removeAt(0)),
              ),
        'AdminService/ScanLibrary': (_) => ServerError(
          'failed_precondition',
          ErrorDetail(code: 'library.scanning'),
        ),
      });
      await openConsole(tester, server);
      await section(tester, 'Overview');
      Future<void> add(String root) async {
        await tester.tapAndSettle(find.text('Add an external library'));
        await dialogField(tester, 'Name', ' Archive ');
        await dialogField(
          tester,
          'Folder on the server, such as /srv/photos',
          root,
        );
        await tester.tapAndSettle(find.text('OK'));
      }

      Future<void> refused(String root, String why) async {
        await add(root);
        expect(find.textContaining(why), findsOneWidget);
        // The next message waits for this one to go.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }

      await refused('/etc', 'external_roots');
      await refused('/srv', 'another library');
      await add(' /srv/photos/ann ');
      final created = server
          .requests<CreateExternalLibraryRequest>(
            'AdminService/CreateExternalLibrary',
          )
          .last;
      expect(
        (created.ownerUserId, created.name, created.root),
        ('user-ann', 'Archive', '/srv/photos/ann'),
      );
      expect(created.hasFilesPerSecond(), isFalse, reason: 'the defaults');

      expect(find.text('Scan now'), findsOneWidget, reason: 'external only');
      await tester.tapAndSettle(find.text('Scan now'));
      expect(
        server
            .requests<ScanLibraryRequest>('AdminService/ScanLibrary')
            .single
            .libraryId,
        'lib-2',
      );
      expect(
        find.text(
          'This library is being scanned already. '
          'Wait a minute, then try again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'jobs are filtered, retried, cancelled and paused for an hour by default',
    (tester) async {
      final server = FakeServer();
      await openConsole(tester, server);
      await section(tester, 'Jobs');
      expect(find.textContaining('Failed, 5 attempts'), findsOneWidget);
      await tester.tapAndSettle(find.byType(DropdownButton<JobStatus>));
      await tester.tapAndSettle(find.text('Failed').last);
      expect(
        server.requests<ListJobsRequest>('AdminService/ListJobs').last.status,
        JobStatus.JOB_STATUS_DEAD,
      );

      await tester.tapAndSettle(find.text('Retry'));
      expect(
        server.requests<RetryJobRequest>('AdminService/RetryJob').single.jobId,
        'job-1',
      );
      await tester.tapAndSettle(find.text('Cancel job'));
      expect(
        server
            .requests<CancelJobRequest>('AdminService/CancelJob')
            .single
            .jobId,
        'job-2',
      );

      await tester.tapAndSettle(find.text('Pause a job type'));
      await dialogField(tester, 'Job type, such as render', 'render');
      await dialogField(tester, 'Minutes, 1 to 1440', '1441');
      await tester.tapAndSettle(find.text('OK'));
      expect(find.text('Out of range'), findsOneWidget);
      expect(
        server.requests<PauseJobTypeRequest>('AdminService/PauseJobType'),
        isEmpty,
      );
      await dialogField(tester, 'Minutes, 1 to 1440', '60');
      await tester.tapAndSettle(find.text('OK'));
      final pause = server
          .requests<PauseJobTypeRequest>('AdminService/PauseJobType')
          .single;
      expect((pause.type, pause.pauseMinutes), ('render', 60));
    },
  );

  testWidgets('a maintenance type is paused for up to a week, others a day', (
    tester,
  ) async {
    final server = FakeServer();
    await openConsole(tester, server);
    await section(tester, 'Jobs');
    await tester.tapAndSettle(find.text('Pause a job type'));
    await dialogField(tester, 'Job type, such as render', 'scrub');
    await tester.pump();
    await dialogField(tester, 'Minutes, 1 to 10080', '10081');
    await tester.tapAndSettle(find.text('OK'));
    expect(find.text('Out of range'), findsOneWidget);
    await dialogField(tester, 'Minutes, 1 to 10080', '10080');
    await dialogField(tester, 'Job type, such as render', 'render');
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Minutes, 1 to 1440'), findsOne);
    await tester.tapAndSettle(find.text('OK'));
    expect(find.text('Out of range'), findsOneWidget);
    await dialogField(tester, 'Job type, such as render', 'storage-purge');
    await tester.pump();
    await tester.tapAndSettle(find.text('OK'));
    final pause = server
        .requests<PauseJobTypeRequest>('AdminService/PauseJobType')
        .single;
    expect((pause.type, pause.pauseMinutes), ('storage-purge', 10080));
  });

  testWidgets('a maintenance pause the server refuses says why', (
    tester,
  ) async {
    final server = FakeServer({
      'AdminService/PauseJobType': (_) => ServerError(
        'permission_denied',
        ErrorDetail(code: 'job.maintenance'),
      ),
    });
    await openConsole(tester, server);
    await section(tester, 'Jobs');
    await tester.tapAndSettle(find.text('Pause a job type'));
    await dialogField(tester, 'Job type, such as render', 'scrub');
    await tester.tapAndSettle(find.text('OK'));
    expect(find.textContaining('not with an API key'), findsOneWidget);
  });

  testWidgets('accounts are added, edited, disabled and deleted', (
    tester,
  ) async {
    final server = FakeServer();
    await openConsole(tester, server);
    await section(tester, 'Accounts');
    expect(find.text('ann · Administrator · Active'), findsOneWidget);

    await tester.tapAndSettle(find.text('Add account'));
    await dialogField(tester, 'Sign-in name', 'kid');
    await dialogField(tester, 'Name', 'Kid');
    await dialogField(tester, 'Storage quota in GB; empty for none', '5');
    await tester.tapAndSettle(find.byType(DropdownButtonFormField<UserRole>));
    await tester.tapAndSettle(find.text('Viewer').last);
    await tester.tapAndSettle(find.text('Save'));
    final created = server
        .requests<CreateUserRequest>('UserService/CreateUser')
        .single
        .user;
    expect(
      (
        created.handle,
        created.displayName,
        created.role,
        created.quotaBytes.toInt(),
      ),
      ('kid', 'Kid', UserRole.USER_ROLE_VIEWER, 5000000000),
    );

    Future<void> menu(String item) async {
      await tester.tapAndSettle(find.byType(PopupMenuButton<VoidCallback>));
      await tester.tapAndSettle(find.text(item));
    }

    await menu('Disable');
    final disabled = server
        .requests<UpdateUserRequest>('UserService/UpdateUser')
        .single;
    expect(disabled.user.userId, 'u-1');
    expect(disabled.user.status, UserStatus.USER_STATUS_DISABLED);
    expect(disabled.updateMask.paths, ['status']);
    await menu('Edit');
    await dialogField(tester, 'Name', 'Ann B.');
    await tester.tapAndSettle(find.text('Save'));
    final edited = server
        .requests<UpdateUserRequest>('UserService/UpdateUser')
        .last;
    expect(
      (edited.user.displayName, edited.user.hasQuotaBytes()),
      ('Ann B.', false),
    );
    expect(edited.updateMask.paths, [
      'display_name',
      'email',
      'role',
      'quota_bytes',
    ]);
    await menu('Delete');
    expect(
      server
          .requests<DeleteUserRequest>('UserService/DeleteUser')
          .single
          .userId,
      'u-1',
    );
  });

  testWidgets(
    "a password setup link carries the server's address and the token, as text "
    'and as a QR code, to send by any channel',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      final server = FakeServer({
        'UserService/CreatePasswordSetup': (_) => CreatePasswordSetupResponse(
          passwordSetup: PasswordSetup(token: 'ab12', expiresAt: FakeServer.at),
        ),
      });
      await openConsole(
        tester,
        server,
        saved: SavedServer(
          endpoints: [Uri.parse('https://photos.example.org/photolib')],
          instance: 'instance-a',
        ),
      );
      await section(tester, 'Accounts');
      await tester.tapAndSettle(find.byType(PopupMenuButton<VoidCallback>));
      await tester.tapAndSettle(find.text('Password setup link'));
      expect(
        server
            .requests<CreatePasswordSetupRequest>(
              'UserService/CreatePasswordSetup',
            )
            .single
            .userId,
        'u-1',
      );
      const link =
          'https://photos.example.org/photolib/'
          '#/password-setup?handle=ann&token=ab12&instance=instance-a';
      expect(find.text(link), findsOneWidget);
      expect(find.textContaining('Send this link to Ann'), findsOneWidget);
      expect(find.bySemanticsLabel('QR code of the link'), findsOneWidget);
      await tester.tapAndSettle(find.text('Copy link'));
      expect(copied, [link]);
    },
  );

  testWidgets('a device pairs with every address and the certificate pin, '
      'as a link and a QR code', (tester) async {
    await openConsole(
      tester,
      FakeServer(),
      saved: SavedServer(
        endpoints: [
          Uri.parse('https://photos.example.org/'),
          Uri.parse('http://192.168.1.10:8080/'),
        ],
        instance: 'instance-a',
        pin: 'ab' * 32,
      ),
    );
    await section(tester, 'Pair a device');
    final link =
        'https://photos.example.org/#/pair?'
        'address=http%3A%2F%2F192.168.1.10%3A8080%2F&pin=${'ab' * 32}'
        '&instance=instance-a';
    expect(find.text(link), findsOneWidget);
    expect(find.bySemanticsLabel('QR code of the link'), findsOneWidget);
    expect(
      pairing(link)?.endpoints.last,
      Uri.parse('http://192.168.1.10:8080/'),
    );
  });

  testWidgets('policies are checked before they are saved', (tester) async {
    final server = FakeServer();
    await openConsole(tester, server);
    await section(tester, 'Policies');
    await dialogField(tester, 'Days in the trash, 1 to 3650', '0');
    await tester.tapAndSettle(find.text('Save'));
    expect(find.text('Out of range'), findsOneWidget);
    expect(
      server.requests<UpdateSettingsRequest>('AdminService/UpdateSettings'),
      isEmpty,
    );
    await dialogField(tester, 'Days in the trash, 1 to 3650', '30');
    const gb = 'or below this free disk in GB, if less, 0 to 100000';
    await dialogField(tester, gb, '100001');
    await tester.tapAndSettle(find.text('Save'));
    expect(find.text('Out of range'), findsOneWidget);
    await dialogField(tester, gb, '50');
    await dialogField(tester, _scrubDays, '0');
    await tester.tapAndSettle(find.text('Save'));
    expect(find.text('Out of range'), findsOneWidget);
    await dialogField(tester, _scrubDays, '30');
    await dialogField(tester, _silentHours, '24');
    await tester.tapAndSettle(
      find.text('Every account must set up a second factor'),
    );
    await tester.tapAndSettle(find.text('Save'));
    final saved = server
        .requests<UpdateSettingsRequest>('AdminService/UpdateSettings')
        .single
        .settings;
    expect(
      (
        saved.trashRetentionDays,
        saved.requireTwoFactor,
        saved.minFreeDiskPercent,
        saved.minFreeDiskGb,
        saved.scrubDays,
        saved.backupSilentHours,
      ),
      (30, true, 5, 50, 30, 24),
    );
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('capability switches say where their value comes from, '
      'pinned ones are read-only', (tester) async {
    final server = FakeServer({
      'AdminService/GetSettings': (_) => GetSettingsResponse(
        settings: Settings(trashRetentionDays: 30, minFreeDiskPercent: 5),
        pinned: ['trash_retention_days'],
      ),
      'AdminService/GetPolicy': (_) => GetPolicyResponse(
        switches: [
          PolicySwitch(
            capability: Capability.CAPABILITY_UPLOADS,
            source: PolicySource.POLICY_SOURCE_CONFIG,
            set: false,
          ),
          PolicySwitch(
            capability: Capability.CAPABILITY_SHARING,
            source: PolicySource.POLICY_SOURCE_SERVER,
            set: false,
          ),
          PolicySwitch(
            capability: Capability.CAPABILITY_ML_SEARCH,
            enabled: true,
            source: PolicySource.POLICY_SOURCE_DEFAULT,
          ),
        ],
      ),
      'AdminService/UpdatePolicy': (_) => ServerError(
        'failed_precondition',
        ErrorDetail(code: 'setting.pinned'),
      ),
    });
    await openConsole(tester, server);
    await section(tester, 'Policies');
    final trash = find.widgetWithText(
      TextFormField,
      'Days in the trash, 1 to 3650',
    );
    expect(tester.widget<TextFormField>(trash).enabled, isFalse);
    SwitchListTile switchOf(String title) =>
        tester.widget(find.widgetWithText(SwitchListTile, title));
    final uploads = switchOf('Uploads from devices, the web and the CLI');
    expect((uploads.value, uploads.onChanged), (false, null));
    expect(find.text('Set in config'), findsNWidgets(2));
    expect(find.text('Set for the server'), findsOneWidget);
    expect(find.text('On by default'), findsOneWidget);
    await tester.ensureVisible(find.text('Sharing and public links'));
    await tester.tapAndSettle(find.text('Sharing and public links'));
    final changed = server
        .requests<UpdatePolicyRequest>('AdminService/UpdatePolicy')
        .single;
    expect(
      (changed.userId, changed.libraryId, changed.capability, changed.enabled),
      ('', '', Capability.CAPABILITY_SHARING, true),
    );
    expect(
      find.textContaining('set in the configuration file'),
      findsOneWidget,
    );
  });

  testWidgets('a preset says what it switches off before it is applied', (
    tester,
  ) async {
    final server = FakeServer();
    await openConsole(tester, server);
    await section(tester, 'Policies');
    await tester.ensureVisible(find.text('Apply a preset'));
    await tester.tapAndSettle(find.text('Apply a preset'));
    expect(find.textContaining('no uploads'), findsOneWidget);
    await tester.tapAndSettle(find.text('Personal'));
    await tester.tapAndSettle(find.text('OK'));
    final applied = server.requests<ApplyPresetRequest>(
      'AdminService/ApplyPreset',
    );
    expect(applied.single.preset, Preset.PRESET_PERSONAL);
  });

  testWidgets("an account's and a library's own switches override the server's "
      'and can be cleared', (tester) async {
    final server = FakeServer({
      'AdminService/GetPolicy': (request) => GetPolicyResponse(
        switches: [
          PolicySwitch(
            capability: Capability.CAPABILITY_EDITS,
            enabled: true,
            source: (request as GetPolicyRequest).userId.isEmpty
                ? PolicySource.POLICY_SOURCE_LIBRARY
                : PolicySource.POLICY_SOURCE_USER,
            set: true,
          ),
        ],
      ),
    });
    await openConsole(tester, server);
    await section(tester, 'Accounts');
    await tester.tapAndSettle(find.byType(PopupMenuButton<VoidCallback>));
    await tester.tapAndSettle(find.text('Policies'));
    expect(find.text('Set for this account'), findsOneWidget);
    await tester.tapAndSettle(find.byTooltip("Use the wider level's value"));
    final cleared = server
        .requests<UpdatePolicyRequest>('AdminService/UpdatePolicy')
        .single;
    expect(
      (cleared.userId, cleared.capability, cleared.hasEnabled()),
      ('u-1', Capability.CAPABILITY_EDITS, false),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await section(tester, 'Overview');
    await tester.tapAndSettle(find.byTooltip('Policies'));
    expect(find.text('Set for this library'), findsOneWidget);
    final asked = server.requests<GetPolicyRequest>('AdminService/GetPolicy');
    expect(asked.last.libraryId, 'lib-1');
  });

  testWidgets(
    'storage, the audit log, the server log and the diagnostics show what '
    'the server reports',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      final server = FakeServer();
      await openConsole(tester, server);
      await section(tester, 'Storage');
      expect(find.text('2 GB free\nonline'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == 'OK'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await section(tester, 'Audit log');
      expect(find.text('job.pause'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await section(tester, 'Server log');
      expect(find.text('listening'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await section(tester, 'Diagnostics');
      expect(find.text('data checksums are off'), findsOneWidget);
      await tester.tapAndSettle(find.text('Copy diagnostics for a bug report'));
      expect(copied, ['{"photolibd": "0.0.0"}']);
    },
  );

  testWidgets('an unreachable server offers to try again', (tester) async {
    final server = FakeServer({
      'AdminService/GetStatus': (_) => Unreachable('down'),
    });
    await openConsole(tester, server);
    await section(tester, 'Overview');
    expect(find.text('The server does not answer.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tapAndSettle(find.text('Details'));
    expect(find.text('Unreachable(down)'), findsOneWidget);
  });

  testWidgets('a server the session may not go to over plain HTTP says it '
      'needs HTTPS (ADR-0125)', (tester) async {
    final server = FakeServer({
      'AdminService/GetStatus': (_) => HttpsRequired(Uri()),
    });
    await openConsole(tester, server);
    await section(tester, 'Overview');
    expect(
      find.text(
        'This server needs an HTTPS address: beyond your local network, '
        'Photolib does not sign in over plain HTTP.',
      ),
      findsOneWidget,
    );
  });
}
