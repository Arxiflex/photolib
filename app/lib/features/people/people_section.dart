import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/on_device_faces.dart';
import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show deleteFaces;
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/registry.dart';

const _log = Logger('photolib.faces');

/// What the user's server says of their face consent (ADR-0389): null while
/// signed out.
final FutureProvider<FaceConsentState?> faceConsentProvider =
    FutureProvider.autoDispose((ref) async {
      final session = ref.watch(sessionProvider);
      if (session == null) return null;
      final answer = await FaceServiceApi(session)
          .getFaceConsent(null, GetFaceConsentRequest());
      return answer.state;
    });

/// The user's answer to the face recognition notice, on this device and, when
/// they are signed in, on their server (ADR-0389). Nothing about faces is
/// computed anywhere before [agree], and [withdraw] deletes what was found
/// everywhere.
class FaceConsent {
  /// Acts for [ref].
  const new(this.ref);

  /// The provider container of the app.
  final WidgetRef ref;

  /// Records that the user agreed to the notice, on this device and their
  /// server; false when the server could not be told.
  Future<bool> agree() {
    ref.read(settingsProvider.notifier).setFaceNotice(faceNotice);
    return _tellServer(granted: true);
  }

  /// Withdraws everywhere: this device stops and forgets its faces, and the
  /// server deletes its own; false when the server could not be told.
  Future<bool> withdraw() async {
    ref.read(settingsProvider.notifier).setFaceNotice(0);
    final db = ref.read(replicaProvider).value;
    if (db != null) await deleteFaces(db);
    return await _tellServer(granted: false);
  }

  Future<bool> _tellServer({required bool granted}) async {
    final session = ref.read(sessionProvider);
    if (session == null) return true;
    try {
      await FaceServiceApi(session).setFaceConsent(
        null,
        SetFaceConsentRequest(granted: granted, noticeVersion: faceNotice),
      );
      ref.invalidate(faceConsentProvider);
      return true;
    } on Object catch (error) {
      _log.warning('the server was not told of the face consent', error: error);
      return false;
    }
  }
}

/// Settings' faces: the notice and the one switch that lets Photolib find
/// faces (ADR-0389), and how far it is.
class FacesSection extends ConsumerWidget {
  /// The section.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final on = settings.faceNotice == faceNotice;
    final server = ref.watch(faceConsentProvider).value;
    final status = ref.watch(onDeviceFacesProvider);
    final aura = !kIsWeb && _desktop && registry.any((m) => m.id == 'auraface');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: AppTokens.of(context).lg),
        Text(
          strings.facesTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.facesSwitch),
          subtitle: Text(on ? strings.facesSwitchOn : strings.facesSwitchOff),
          value: on,
          onChanged: (want) =>
              unawaited(want ? _agree(context, ref) : _withdraw(context, ref)),
        ),
        if (on && !kIsWeb)
          if (_status(strings, status) case final line?)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.face_outlined),
              title: Text(line),
            ),
        if (on && server != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: Text(
              !server.available
                  ? strings.facesServerUnavailable
                  : server.granted
                  ? strings.facesServerOn
                  : strings.facesServerOff,
            ),
          ),
        if (on && aura)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.facesAura),
            value: settings.faceEmbedder == 'auraface',
            onChanged: (use) => ref
                .read(settingsProvider.notifier)
                .setFaceEmbedder(use ? 'auraface' : 'sface'),
          ),
      ],
    );
  }

  static bool get _desktop => const {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  }.contains(defaultTargetPlatform);

  static String? _status(AppLocalizations strings, MlStatus status) =>
      switch (status.phase) {
        MlPhase.off => null,
        MlPhase.waiting => strings.facesStatusWaiting,
        MlPhase.downloading => strings.facesStatusDownloading(
          (status.progress * 100).floor(),
        ),
        MlPhase.missing => strings.facesStatusMissing,
        MlPhase.unavailable => strings.facesStatusUnavailable,
        MlPhase.running => strings.facesStatusRunning,
        MlPhase.noDecoder => strings.facesStatusNoDecoder,
      };

  Future<void> _agree(BuildContext context, WidgetRef ref) async {
    final strings = AppLocalizations.of(context);
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.facesNoticeTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final paragraph in [
                strings.facesNoticeWhat,
                strings.facesNoticeWhere,
                strings.facesNoticeKeep,
                strings.facesNoticeOptional,
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(paragraph),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.facesNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.facesAgree),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    final told = await FaceConsent(ref).agree();
    if (!told && context.mounted) _tell(context, strings.facesServerFailed);
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final strings = AppLocalizations.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.facesWithdrawTitle),
        content: Text(strings.facesWithdrawBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.facesNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.facesWithdraw),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final told = await FaceConsent(ref).withdraw();
    if (!told && context.mounted) _tell(context, strings.facesServerFailed);
  }

  static void _tell(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}
