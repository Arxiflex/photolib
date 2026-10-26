import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib/core/on_device_ocr.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_data/photolib_data.dart';

/// How far on-device indexing has run the model it ran last, while shown:
/// anew on a change to the library but at most once a second.
final StreamProvider<MlProgressResult> indexingProgressProvider =
    StreamProvider.autoDispose((ref) async* {
      final db = await ref.watch(replicaProvider.future);
      yield* everySecond(mlProgress(db, null).watchSingle());
    });

/// How far on-device OCR has run, while shown.
final StreamProvider<MlProgressResult> textProgressProvider =
    StreamProvider.autoDispose((ref) async* {
      final db = await ref.watch(replicaProvider.future);
      yield* everySecond(mlProgress(db, ocrModel).watchSingle());
    });

/// The photos the model run last could not read, while shown.
final StreamProvider<List<MlFailuresResult>> indexingFailuresProvider =
    StreamProvider.autoDispose((ref) async* {
      final db = await ref.watch(replicaProvider.future);
      yield* mlFailures(db, null).watch();
    });

/// Settings' on-device indexing (docs/09-ml-and-search.md §3.4, §12.2): the
/// consent to download the model and from where, what holds indexing back,
/// how far it is and what it could not read, and the user's overrides of the
/// device's gates. Browsers never index, so the web has none.
class IndexingSection extends ConsumerWidget {
  /// The section, on native targets.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final health = ref.watch(deviceHealthProvider).value;
    final server = ref.watch(serverProvider).value;
    // The file every device runs.
    final file = mlModel.imageFile('android') ?? mlModel.files.first;
    final status = _status(strings, ref, settings, health);
    final failed = ref.watch(indexingFailuresProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: AppTokens.of(context).lg),
        Text(
          strings.settingsIndexing,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.indexingModels),
          subtitle: Text(
            strings.indexingModelsFrom(
              (file.size / 1e6).round(),
              server?.name ?? Uri.parse(file.urls.first).host,
            ),
          ),
          value: settings.indexModels,
          onChanged: (on) =>
              ref.read(settingsProvider.notifier).setIndexModels(on: on),
        ),
        if (status != null) _line(Icons.image_search_outlined, status),
        const _TextSection(),
        if (health != null && liteMode(health))
          _line(Icons.memory_outlined, strings.indexingLite),
        if (failed.isNotEmpty) _Failures(failed),
        const _Gates(),
      ],
    );
  }

  static Widget _line(IconData icon, String text) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(text),
  );

  /// What the model's download says, else what holds indexing back or how
  /// far it is, once a model has run here.
  static String? _status(
    AppLocalizations strings,
    WidgetRef ref,
    Settings settings,
    Map<Object?, Object?>? health,
  ) {
    final ml = ref.watch(onDeviceMlProvider);
    final progress = switch (ref.watch(indexingProgressProvider).value) {
      final p? when p.done > 0 => p,
      _ => null,
    };
    final hold = health == null || progress == null
        ? null
        : mlHold(health, settings);
    return switch ((ml.phase, hold)) {
      (MlPhase.waiting, _) => strings.indexingWaiting,
      (MlPhase.downloading, _) => strings.indexingDownloading(
        (ml.progress * 100).floor(),
      ),
      (MlPhase.missing, _) => strings.indexingMissing,
      (MlPhase.unavailable, _) => strings.indexingUnavailable,
      (MlPhase.noDecoder, _) => strings.indexingNoDecoder,
      (_, Hold.heat) => strings.indexingPausedHeat,
      (_, Hold.powerSaving) => strings.indexingPausedSaver,
      (_, Hold.charger) => strings.indexingPausedCharger,
      (_, Hold.battery) => strings.indexingPausedBattery(settings.indexBattery),
      _ when progress != null => strings.indexingProgress(
        progress.done,
        progress.total,
      ),
      _ => null,
    };
  }
}

/// Reading the text in photos on this device (ADR-0388): the consent to
/// download the text models and from where, and how far it is; on a phone,
/// that the platform reads the text itself. Only where the registry has the
/// models for the platform (the desktops) or the platform reads.
class _TextSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(mlHostProvider).value;
    final files = ocrFiles(host?.target ?? '');
    final platform = host?.platformText ?? false;
    if (files.isEmpty && !platform) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final server = ref.watch(serverProvider).value;
    final bytes = files.fold<int>(0, (sum, f) => sum + f.$2.size);
    final status = ref.watch(onDeviceOcrProvider);
    final progress = ref.watch(textProgressProvider).value;
    final line = switch (status.phase) {
      MlPhase.waiting => strings.indexingTextWaiting,
      MlPhase.downloading => strings.indexingTextDownloading(
        (status.progress * 100).floor(),
      ),
      MlPhase.missing => strings.indexingTextMissing,
      MlPhase.unavailable => strings.indexingTextUnavailable,
      MlPhase.running when progress != null && progress.done > 0 =>
        strings.indexingTextProgress(progress.done, progress.total),
      _ => null,
    };
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.indexingText),
          subtitle: Text(
            platform
                ? strings.indexingTextPlatform
                : strings.indexingTextFrom(
                    (bytes / 1e6).round(),
                    server?.name ?? Uri.parse(files.first.$2.urls.first).host,
                  ),
          ),
          value: settings.indexText,
          onChanged: (on) =>
              ref.read(settingsProvider.notifier).setIndexText(on: on),
        ),
        if (line != null)
          IndexingSection._line(Icons.text_snippet_outlined, line),
      ],
    );
  }
}

/// The photos the model could not read: their count, and on a tap each with
/// why (design 09 §2.2), until another decoder or model reads them.
class _Failures extends StatelessWidget {
  const new(this.failed);

  final List<MlFailuresResult> failed;

  @override
  Widget build(BuildContext context) {
    final title = AppLocalizations.of(context).indexingFailed(failed.length);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.broken_image_outlined),
      title: Text(title),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in failed)
                  ListTile(
                    title: Text(f.a.name ?? f.a.path ?? f.a.sourceId),
                    subtitle: Text(f.failure ?? ''),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The user's overrides of the device's gates (design 09 §3.4).
class _Gates extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    Widget toggle(
      String title, {
      required bool value,
      required ValueChanged<bool> set,
    }) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: set,
    );
    return Column(
      children: [
        toggle(
          strings.indexingChargingOnly,
          value: settings.indexWhileCharging,
          set: (on) => notifier.setIndexWhileCharging(on: on),
        ),
        // The rest matter once the device indexes.
        if (settings.indexModels || settings.indexText) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.indexingBattery),
            trailing: DropdownButton<int>(
              value: settings.indexBattery,
              onChanged: (percent) =>
                  notifier.setIndexBattery(percent ?? settings.indexBattery),
              items: [
                for (final percent in {10, 20, 30, 50, settings.indexBattery})
                  DropdownMenuItem(
                    value: percent,
                    child: Text(strings.indexingPercent(percent)),
                  ),
              ],
            ),
          ),
          toggle(
            strings.indexingAllowSaver,
            value: settings.indexAllowSaver,
            set: (on) => notifier.setIndexAllowSaver(on: on),
          ),
          toggle(
            strings.indexingAllowMetered,
            value: settings.indexAllowMetered,
            set: (on) => notifier.setIndexAllowMetered(on: on),
          ),
        ],
      ],
    );
  }
}
