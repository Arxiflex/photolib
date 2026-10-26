import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_data/photolib_data.dart';

/// The budgets offered, in bytes: a browser's origin holds far less.
List<int> budgetChoices({required bool web}) => web
    ? const [100000000, 250000000, 500000000, 1000000000, 2000000000]
    : const [
        1000000000,
        2000000000,
        5000000000,
        10000000000,
        20000000000,
        50000000000,
        100000000000,
        200000000000,
        500000000000,
      ];

/// What a pin says of itself under [policy] and the pass's [progress]: what
/// it keeps, how far it is, that it waits for the network or the budget
/// (ADR-0200 P5, P9). Every number is the sum of the files it adds on this
/// device (I5).
String pinStatus(
  AppLocalizations strings,
  StoragePolicy policy,
  OfflineProgress? progress,
  OfflinePin pin,
) {
  final formats = Formats(strings);
  final have = progress?.pins[pin.id];
  if (!policy.pinsActive) return strings.storagePinPaused;
  if (have == null || (have.files == 0 && have.left == 0)) {
    return progress == null || progress.running
        ? strings.storagePinPlanning
        : strings.storagePinNothing;
  }
  if (have.left > 0) {
    return strings.storagePinLeft(formats.fileSize(have.leftBytes));
  }
  if (have.have < have.files) {
    return progress?.waiting ?? false
        ? strings.storagePinWaiting
        : strings.storagePinProgress(have.have, have.files);
  }
  return strings.storagePinReady(formats.fileSize(have.haveBytes));
}

/// What a pin of [kind] is called to the user.
String pinKindLabel(AppLocalizations strings, PinKind kind) =>
    strings.storagePinKind(kind.name);

/// IconData of a pin of [kind].
IconData pinKindIcon(PinKind kind) => switch (kind) {
  PinKind.album => Icons.photo_album_outlined,
  PinKind.search => Icons.search,
  PinKind.person => Icons.person_outline,
  PinKind.library => Icons.photo_library_outlined,
  PinKind.asset => Icons.photo_outlined,
};

/// The tile of Settings that opens [StoragePage].
class StorageTile extends StatelessWidget {
  /// The tile.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.sd_storage_outlined),
      title: Text(strings.storageTitle),
      subtitle: Text(strings.storageSubtitle),
      onTap: () => context.push('/settings/storage'),
    );
  }
}

/// Settings › Storage (LIB-20, MOB-15): what this device keeps offline, how
/// much it may take, and the albums, searches and photos pinned, each with
/// where it is and a way to let go.
class StoragePage extends ConsumerWidget {
  /// The page at /settings/storage.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.storageTitle)),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.all(tokens.md),
          children: [
            if (kIsWeb)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.md),
                child: Text(strings.storageWebNote),
              ),
            const _Presets(),
            SizedBox(height: tokens.lg),
            const _Budget(),
            SizedBox(height: tokens.lg),
            const _Pins(),
            SizedBox(height: tokens.lg),
            const _Clear(),
          ],
        ),
      ),
    );
  }
}

class _Presets extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final preset = ref.watch(offlinePolicyProvider.select((p) => p.preset));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.storagePresets,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        RadioGroup<StoragePreset>(
          groupValue: preset,
          onChanged: (chosen) {
            if (chosen != null) {
              ref.read(offlinePolicyProvider.notifier).setPreset(chosen);
            }
          },
          child: Column(
            children: [
              for (final p in StoragePreset.values)
                // A browser keeps no originals: the preset that is all
                // originals is not offered there.
                if (!(kIsWeb && p == StoragePreset.everything))
                  RadioListTile<StoragePreset>(
                    contentPadding: EdgeInsets.zero,
                    value: p,
                    title: Text(strings.storagePreset(p.name)),
                    subtitle: Text(strings.storagePresetHelp(p.name)),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Budget extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final formats = Formats(strings);
    final policy = ref.watch(offlinePolicyProvider);
    final used = ref.watch(offlineProgressProvider).value?.used ?? 0;
    final choices = {...budgetChoices(web: kIsWeb), policy.budget}.toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.storageBudget),
          trailing: DropdownButton<int>(
            value: policy.budget,
            items: [
              for (final bytes in choices)
                DropdownMenuItem(
                  value: bytes,
                  child: Text(formats.fileSize(bytes)),
                ),
            ],
            onChanged: (bytes) {
              if (bytes != null) {
                ref.read(offlinePolicyProvider.notifier).setBudget(bytes);
              }
            },
          ),
        ),
        LinearProgressIndicator(
          value: policy.budget == 0
              ? 0
              : (used / policy.budget).clamp(0.0, 1.0),
        ),
        Padding(
          padding: EdgeInsets.only(top: AppTokens.of(context).xs),
          child: Text(
            strings.storageUsed(
              formats.fileSize(used),
              formats.fileSize(policy.budget),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pins extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final pins = ref.watch(offlinePinsProvider);
    final policy = ref.watch(offlinePolicyProvider);
    final progress = ref.watch(offlineProgressProvider).value;
    final notifier = ref.read(offlinePinsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.storagePins,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (pins.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: AppTokens.of(context).sm),
            child: Text(strings.storageNoPins),
          ),
        for (final pin in pins)
          Column(
            key: ValueKey(pin.id),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(pinKindIcon(pin.kind)),
                title: Text(
                  pin.title.isEmpty
                      ? pinKindLabel(strings, pin.kind)
                      : pin.title,
                ),
                subtitle: Text(pinStatus(strings, policy, progress, pin)),
                trailing: IconButton(
                  icon: const Icon(Icons.push_pin),
                  tooltip: strings.offlineStopKeeping,
                  onPressed: () => notifier.unpin(pin.id),
                ),
              ),
              if (!kIsWeb && policy.preset != StoragePreset.everything)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(strings.storageKeepOriginals),
                  value: pin.originals,
                  onChanged: (on) => notifier.setOriginals(pin.id, on: on),
                ),
            ],
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.storageKeepLibrary),
          value: pins.any((p) => p.id == OfflinePin.libraryId),
          onChanged: (on) => on
              ? notifier.pin(
                  OfflinePin.library(
                    created: DateTime.now().millisecondsSinceEpoch,
                  ),
                )
              : notifier.unpin(OfflinePin.libraryId),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_add_alt_outlined),
          title: Text(strings.storageAddPerson),
          onTap: () => _pickPerson(context, ref),
        ),
      ],
    );
  }

  Future<void> _pickPerson(BuildContext context, WidgetRef ref) async {
    final strings = AppLocalizations.of(context);
    final people = await ref.read(namedPeopleProvider.future);
    if (!context.mounted) return;
    final chosen = await showDialog<({Uint8List id, String name, int photos})>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(strings.storageAddPerson),
        children: [
          if (people.isEmpty)
            Padding(
              padding: EdgeInsets.all(AppTokens.of(context).md),
              child: Text(strings.storageNoPeople),
            ),
          for (final person in people)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, person),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(person.name),
                subtitle: Text(strings.folderItems(person.photos)),
              ),
            ),
        ],
      ),
    );
    if (chosen != null) {
      ref
          .read(offlinePinsProvider.notifier)
          .pin(
            OfflinePin.person(
              chosen.id,
              chosen.name,
              created: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }
  }
}

class _Clear extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final used = ref.watch(offlineProgressProvider).value?.used ?? 0;
    final pins = ref.watch(offlinePinsProvider);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.delete_sweep_outlined),
        label: Text(strings.storageClear),
        onPressed: used == 0 && pins.isEmpty
            ? null
            : () => _confirm(context, ref, used),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, int used) async {
    final strings = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.storageClear),
        content: Text(
          strings.storageClearBody(Formats(strings).fileSize(used)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.storageClearAction),
          ),
        ],
      ),
    );
    if (!(go ?? false)) return;
    ref.read(offlinePinsProvider.notifier).clear();
    // A library kept whole would fill it again.
    final policy = ref.read(offlinePolicyProvider.notifier);
    if (ref.read(offlinePolicyProvider).library != Keep.nothing) {
      policy.setPreset(StoragePreset.travel);
    }
  }
}
