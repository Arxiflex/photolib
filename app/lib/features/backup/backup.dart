import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_log/photolib_log.dart';

const _log = Logger('photolib.backup');

/// What the person chose for backup (ING-05, ING-06, ING-26), kept sealed in
/// the vault: whether it runs, the folders by key (a folder not in [folders]
/// is new and asked about once), media types, the capture date it starts at,
/// what a metered network may carry, roaming, charging, and after how many
/// hours without a complete backup the device warns.
@immutable
class BackupSettings {
  /// Off; photos and videos of every folder chosen; photos up to 50 MB on a
  /// metered network; a warning after a day.
  const new({
    this.enabled = false,
    this.folders = const {},
    this.photos = true,
    this.videos = true,
    this.since,
    this.photosMetered = true,
    this.videosMetered = false,
    this.meteredCap = _cap,
    this.roaming = false,
    this.charging = false,
    this.warnAfter = 24,
    this.warned,
  });

  new _fromJson(Map<String, Object?> json)
    : enabled = json['enabled'] == true,
      folders = (json['folders'] as Map? ?? const {}).cast(),
      photos = json['photos'] != false,
      videos = json['videos'] != false,
      since = json['since'] as int?,
      photosMetered = json['photosMetered'] != false,
      videosMetered = json['videosMetered'] == true,
      meteredCap = json.containsKey('meteredCap')
          ? json['meteredCap'] as int?
          : _cap,
      roaming = json['roaming'] == true,
      charging = json['charging'] == true,
      warnAfter = json['warnAfter'] as int? ?? 24,
      warned = json['warned'] as int?;

  static const _cap = 50000000;

  /// Whether the device backs up.
  final bool enabled;

  /// Whether each folder is backed up, by its key.
  final Map<String, bool> folders;

  /// Whether photos are backed up.
  final bool photos;

  /// Whether videos are backed up.
  final bool videos;

  /// The capture time items are backed up from, in UTC milliseconds.
  final int? since;

  /// Whether a metered network carries photos.
  final bool photosMetered;

  /// Whether a metered network carries videos.
  final bool videosMetered;

  /// The largest item a metered network carries, in bytes; null for any.
  final int? meteredCap;

  /// Whether backup runs while roaming.
  final bool roaming;

  /// Whether backup runs only while the device charges.
  final bool charging;

  /// The hours without a complete backup after which the device warns.
  final int warnAfter;

  /// When the watchdog last warned, in UTC milliseconds.
  final int? warned;

  /// What the engine selects by.
  BackupSelection get selection => BackupSelection(
    folders: folders,
    photos: photos,
    videos: videos,
    since: since,
  );

  /// These settings with the fields given changed, and those [clear] names
  /// (`since`, `meteredCap`) cleared.
  BackupSettings copyWith({
    bool? enabled,
    Map<String, bool>? folders,
    bool? photos,
    bool? videos,
    int? since,
    bool? photosMetered,
    bool? videosMetered,
    int? meteredCap,
    bool? roaming,
    bool? charging,
    int? warnAfter,
    int? warned,
    Set<String> clear = const {},
  }) => BackupSettings(
    enabled: enabled ?? this.enabled,
    folders: folders ?? this.folders,
    photos: photos ?? this.photos,
    videos: videos ?? this.videos,
    since: clear.contains('since') ? null : since ?? this.since,
    photosMetered: photosMetered ?? this.photosMetered,
    videosMetered: videosMetered ?? this.videosMetered,
    meteredCap: clear.contains('meteredCap')
        ? null
        : meteredCap ?? this.meteredCap,
    roaming: roaming ?? this.roaming,
    charging: charging ?? this.charging,
    warnAfter: warnAfter ?? this.warnAfter,
    warned: warned ?? this.warned,
  );

  Map<String, Object?> _toJson() => {
    'enabled': enabled,
    'folders': folders,
    'photos': photos,
    'videos': videos,
    'since': since,
    'photosMetered': photosMetered,
    'videosMetered': videosMetered,
    'meteredCap': meteredCap,
    'roaming': roaming,
    'charging': charging,
    'warnAfter': warnAfter,
    'warned': warned,
  };
}

/// Where the backup settings are kept: the vault's sealed `backup` object.
final backupStoreProvider = Provider<SecretStore>((ref) {
  final vault = ref.watch(vaultProvider.future);
  return VaultText(() => vault, 'backup');
});

/// The backup settings, read at start and written back on every change.
class BackupSettingsNotifier extends StoredNotifier<BackupSettings> {
  @override
  Provider<SecretStore> get store => backupStoreProvider;

  @override
  BackupSettings get initial => const BackupSettings();

  @override
  BackupSettings decode(Object json) =>
      BackupSettings._fromJson(json as Map<String, Object?>);

  @override
  Object? encode(BackupSettings state) => state._toJson();

  /// Applies [edit] and keeps the outcome.
  void edit(BackupSettings Function(BackupSettings) edit) => change(edit);
}

/// The backup settings.
final backupSettingsProvider =
    NotifierProvider<BackupSettingsNotifier, BackupSettings>(
      BackupSettingsNotifier.new,
    );

/// What the device says of its network and power: whether the network in
/// use is metered (a phone's hotspot or tethering included) or roaming,
/// whether it charges, and its battery level in percent.
typedef DeviceState = ({
  bool metered,
  bool roaming,
  bool charging,
  int battery,
});

/// A device that says nothing: unmetered, on mains power.
const DeviceState anyDevice = (
  metered: false,
  roaming: false,
  charging: true,
  battery: 100,
);

/// What [settings] let a run send on a device in [device]'s state.
BackupConditions backupConditions(
  BackupSettings settings,
  DeviceState device,
) => BackupConditions(
  photos: !device.metered || settings.photosMetered,
  videos: !device.metered || settings.videosMetered,
  cap: device.metered ? settings.meteredCap : null,
  stop: settings.charging && !device.charging
      ? 'charging'
      : !device.charging && device.battery < 20
      ? 'battery_low'
      : device.roaming && !settings.roaming
      ? 'roaming'
      : null,
);

/// Reads the device's state now; tests fake it.
final deviceStateProvider = Provider<Future<DeviceState> Function()>(
  (ref) => readDeviceState,
);

/// The device's state: Android's from DeviceHealth.kt, Linux's from
/// NetworkManager and the kernel's power supplies; elsewhere [anyDevice].
Future<DeviceState> readDeviceState() async {
  if (kIsWeb) return anyDevice;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      final s = await deviceHealthChannel.invokeMapMethod<String, Object?>(
        'state',
      );
      return (
        metered: s?['metered'] == true,
        roaming: s?['roaming'] == true,
        charging: s?['charging'] != false,
        battery: s?['battery'] as int? ?? 100,
      );
    case TargetPlatform.linux:
      final (charging, battery) = await linuxPower(
        Directory('/sys/class/power_supply'),
      );
      return (
        metered: meteredByNetworkManager(await _gdbus(_metered)),
        roaming: false,
        charging: charging,
        battery: battery,
      );
    case TargetPlatform.iOS ||
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.fuchsia:
      return anyDevice;
  }
}

const _metered = [
  '--system',
  '--dest',
  'org.freedesktop.NetworkManager',
  '--object-path',
  '/org/freedesktop/NetworkManager',
  '--method',
  'org.freedesktop.DBus.Properties.Get',
  'org.freedesktop.NetworkManager',
  'Metered',
];

/// What `gdbus call` prints for [arguments]; nothing when it cannot run.
Future<String> _gdbus(List<String> arguments) async {
  try {
    return '${(await Process.run('gdbus', ['call', ...arguments])).stdout}';
  } on ProcessException {
    return '';
  }
}

/// Whether NetworkManager's `Metered`, as `gdbus` prints it (`(<uint32 1>,)`),
/// says yes (1) or guesses yes (3), as it does for a phone's hotspot, USB
/// tethering and mobile broadband.
bool meteredByNetworkManager(String gdbus) =>
    RegExp(r'uint32 [13]\b').hasMatch(gdbus);

/// Whether a Linux machine charges, or has no battery, and its battery level,
/// from the power supplies under [supplies] (`/sys/class/power_supply`).
Future<(bool, int)> linuxPower(Directory supplies) async {
  Future<String> read(Directory d, String name) =>
      File('${d.path}/$name')
          .readAsString()
          .then((s) => s.trim(), onError: (Object _) => '');
  var (mains, battery, charging) = (false, 100, true);
  try {
    await for (final d in supplies.list().where((e) => e is Directory)) {
      final supply = d as Directory;
      switch (await read(supply, 'type')) {
        case 'Mains':
          mains |= await read(supply, 'online') == '1';
        case 'Battery':
          battery = int.tryParse(await read(supply, 'capacity')) ?? battery;
          charging = await read(supply, 'status') != 'Discharging';
      }
    }
  } on FileSystemException {
    // No power supplies to read: a desktop on mains, as far as anyone knows.
  }
  return (mains || charging, battery);
}

/// Runs a backup in the data isolate (`backupReplica`); tests fake it.
typedef RunBackup = Future<BackupRunData> Function(
  Replica db,
  NetworkConfig config,
  BackupSelection selection,
  BackupConditions conditions, {
  String? instance,
});

/// How backups run.
final runBackupProvider = Provider<RunBackup>((ref) => backupReplica);

/// Whether the app backs this device up itself: natively, but on iOS, whose
/// photos back up through PhotoKit (M2-20).
final backupSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS,
);

/// Raises a notification of the system's; tests fake it.
final noticeProvider = Provider<Future<void> Function(String, String)>(
  (ref) => systemNotice,
);

/// A notification with [title] and [body]: on Linux through the desktop's
/// notification service, on Android through DeviceHealth.kt; elsewhere only
/// the home screen says it (M2-19, M2-20).
Future<void> systemNotice(String title, String body) async {
  if (kIsWeb) return;
  switch (defaultTargetPlatform) {
    case TargetPlatform.linux:
      await _gdbus([
        '--session',
        '--dest',
        'org.freedesktop.Notifications',
        '--object-path',
        '/org/freedesktop/Notifications',
        '--method',
        'org.freedesktop.Notifications.Notify',
        'Photolib',
        '0',
        'photolib',
        title,
        body,
        '[]',
        '{}',
        '-1',
      ]);
    case TargetPlatform.android:
      await deviceHealthChannel.invokeMethod<void>('notify', {
        'channel': _strings().backupTitle,
        'title': title,
        'body': body,
      });
    case TargetPlatform.iOS ||
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.fuchsia:
  }
}

/// The app's strings in the device's language, where no widget is.
AppLocalizations _strings() => lookupAppLocalizations(
  basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  ),
);

/// Whether backup is overdue at [now] (ING-26): items wait, and no run left
/// nothing to send for [hours], since the last that did or else the first.
bool backupOverdue(BackupStatus status, int hours, int now) =>
    status.pending > 0 &&
    switch (status.completed ?? status.first) {
      final since? => now - since >= Duration(hours: hours).inMilliseconds,
      null => false,
    };

/// The backup at a glance, as it changes.
final backupStatusProvider = StreamProvider<BackupStatus>((ref) async* {
  yield* watchBackupStatus(await ref.watch(replicaProvider.future));
});

/// Backs the device up while backup is on and the app signed in (ADR-0226):
/// at start, every 15 minutes and when asked, one run at a time, on the
/// device's session, renewed silently before it expires. A run the server
/// stopped with a revocation signs the app out, which the home screen says
/// until the person signs in again; one overdue raises a notification once.
class BackupNotifier extends Notifier<BackupRunData?> {
  Future<BackupRunData?>? _running;

  @override
  BackupRunData? build() {
    final on =
        ref.watch(backupSupportedProvider) &&
        ref.watch(backupSettingsProvider.select((s) => s.enabled)) &&
        ref.watch(serverProvider.select((s) => s.value?.account != null));
    if (on) {
      final timer = Timer.periodic(
        const Duration(minutes: 15),
        (_) => unawaited(run()),
      );
      ref.onDispose(timer.cancel);
      Timer.run(() => unawaited(run()));
    }
    return null;
  }

  /// Backs up now, or returns the end of the run under way; null when none
  /// ran, or it failed, which the log says.
  Future<BackupRunData?> run() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<BackupRunData?> _run() async {
    try {
      return await _backUp();
    } on Object catch (error, stack) {
      _log.warning('backup did not run', error: error, stackTrace: stack);
      return null;
    }
  }

  Future<BackupRunData?> _backUp() async {
    final servers = ref.read(accountsProvider.notifier);
    await servers.renew();
    final server = ref.read(serverProvider).value;
    final account = server?.account;
    final settings = ref.read(backupSettingsProvider);
    if (server == null || account == null || !settings.enabled) return null;
    final db = await ref.read(replicaProvider.future);
    final device = await ref.read(deviceStateProvider)();
    final run = await ref.read(runBackupProvider)(
      db,
      server.config,
      settings.selection,
      backupConditions(settings, device),
      instance: server.instance,
    );
    if (run.stopped == 'signed_out') await servers.ended(account.token);
    if (!ref.mounted) return run;
    state = run;
    await _watch(db, settings);
    return run;
  }

  /// Raises a notification once backup is overdue, once until it completes.
  Future<void> _watch(Replica db, BackupSettings settings) async {
    final status = await watchBackupStatus(db).first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final since = status.completed ?? status.first ?? now;
    if (!backupOverdue(status, settings.warnAfter, now) ||
        (settings.warned ?? 0) > since) {
      return;
    }
    ref
        .read(backupSettingsProvider.notifier)
        .edit((s) => s.copyWith(warned: now));
    final strings = _strings();
    await ref.read(noticeProvider)(
      strings.backupOverdueTitle,
      strings.backupOverdue(
        settings.warnAfter,
        strings.folderItems(status.pending),
      ),
    );
  }
}

/// The device's backups, and the last run's log entry.
final backupProvider = NotifierProvider<BackupNotifier, BackupRunData?>(
  BackupNotifier.new,
);
