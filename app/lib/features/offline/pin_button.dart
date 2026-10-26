import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/features/offline/storage_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_data/photolib_data.dart';

/// Keeps a pin available offline on this device, or lets it go (MOB-15): a
/// push pin that is filled while it is kept. [make] builds the pin when it is
/// first kept, so that a page need not build one it never keeps.
class OfflinePinButton extends ConsumerWidget {
  /// The button of the pin [id].
  const new({required this.id, required this.make, super.key});

  /// Names the pin among the others.
  final String id;

  /// The pin, made when the button keeps it.
  final OfflinePin Function() make;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final pinned = ref.watch(
      offlinePinsProvider.select((pins) => pins.any((p) => p.id == id)),
    );
    return IconButton(
      key: const ValueKey('offline-pin'),
      isSelected: pinned,
      icon: const Icon(Icons.push_pin_outlined),
      selectedIcon: const Icon(Icons.push_pin),
      tooltip: pinned ? strings.offlineStopKeeping : strings.offlineKeep,
      onPressed: () {
        final pins = ref.read(offlinePinsProvider.notifier);
        pinned ? pins.unpin(id) : pins.pin(make());
      },
    );
  }
}

/// Where the pin [id] is, under the app bar of its page: nothing while it is
/// not kept (ADR-0200 P9: a pin made with no signal says it will download
/// when online).
class OfflineStatusLine extends ConsumerWidget {
  /// The status of the pin [id].
  const new(this.id, {super.key});

  /// Names the pin.
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pin = ref.watch(
      offlinePinsProvider.select(
        (pins) => pins.where((p) => p.id == id).firstOrNull,
      ),
    );
    if (pin == null) return const SizedBox.shrink();
    final policy = ref.watch(offlinePolicyProvider);
    final progress = ref.watch(offlineProgressProvider).value;
    final tokens = AppTokens.of(context);
    return Semantics(
      container: true,
      child: ColoredBox(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.md,
            vertical: tokens.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.push_pin,
                size: 16,
                color: scheme.onSecondaryContainer,
              ),
              SizedBox(width: tokens.sm),
              Expanded(
                child: Text(
                  pinStatus(strings, policy, progress, pin),
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
