import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/collections/collections.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart';

/// How many changes exist only on this device while the store has no recovery
/// code and the offer is not put off, else null (docs/21 §6); read at start.
final recoveryOfferProvider = FutureProvider<int?>((ref) async {
  final later = ref.watch(settingsProvider.select((s) => s.recoveryReminder));
  if (later != null && DateTime.now().isBefore(later)) return null;
  final vault = await ref.watch(vaultProvider.future);
  if (await vault.hasRecoveryCode()) return null;
  final count = await localOnlyCount(await ref.watch(replicaProvider.future));
  return count == 0 ? null : count;
});

final _rebuiltSeen = NotifierProvider<_Seen, bool>(_Seen.new);

class _Seen extends Notifier<bool> {
  @override
  bool build() => false;

  void seen() => state = true;
}

// Opens the vault anew and reads the settings and collections again with it,
// so that defaults never overwrite what the store holds.
void _reopen(WidgetRef ref) => ref
  ..invalidate(vaultProvider)
  ..invalidate(settingsProvider)
  ..invalidate(collectionsProvider);

/// The local store's state where the user can act on it (ADR-0057), above
/// every tab and in Settings: rebuilt because the keystore lost its key,
/// waiting for its recovery code, failed to open (where nothing the app keeps
/// is kept), or holding changes no recovery code protects.
class StoreBanner extends ConsumerWidget {
  /// The banner, empty while the store needs nothing of the user.
  const new({super.key, this.margin});

  /// Space around it, where it sits among other content.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    Widget banner(String text, List<Widget> actions, [String? more]) =>
        MaterialBanner(
          margin: margin,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(text), if (more != null) Text(more)],
          ),
          forceActionsBelow: true,
          actions: actions,
        );
    final linux = !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
    final vault = ref.watch(vaultProvider);
    return switch (vault.isLoading ? null : vault.error) {
      RecoveryNeeded() => banner(strings.storeRecoveryNeeded, [
        TextButton(
          onPressed: () => _reset(context, ref),
          child: Text(strings.storeReset),
        ),
        FilledButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _RecoveryCodeDialog(),
          ),
          child: Text(strings.recoveryCodeEnter),
        ),
      ]),
      Object() => banner(strings.storeUnavailable, [
        TextButton(
          onPressed: () => _reopen(ref),
          child: Text(strings.errorRetry),
        ),
      ], linux ? strings.storeNoKeyring : strings.storeNoKeystore),
      _ when (vault.value?.rebuilt ?? false) && !ref.watch(_rebuiltSeen) =>
        banner(strings.storeRebuilt, [
          TextButton(
            onPressed: ref.read(_rebuiltSeen.notifier).seen,
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ]),
      _ => switch (ref.watch(recoveryOfferProvider).value) {
        final count? => banner(strings.recoveryOffer(count), [
          TextButton(
            onPressed: ref.read(settingsProvider.notifier).remindRecoveryLater,
            child: Text(strings.recoveryLater),
          ),
          FilledButton(
            onPressed: () => createRecoveryCode(context, ref),
            child: Text(strings.recoveryCreate),
          ),
        ]),
        _ => const SizedBox.shrink(),
      },
    };
  }

  // Erases the store, which opens anew, once the user confirms.
  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.storeReset),
        content: Text(strings.storeResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.storeReset),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await (await ref.read(vaultOpenerProvider)()).erase();
    _reopen(ref);
  }
}

/// Makes a recovery code, replacing any, and shows its 24 words once.
Future<void> createRecoveryCode(BuildContext context, WidgetRef ref) async {
  final words = await (await ref.read(vaultProvider.future)).addRecoveryCode();
  ref.invalidate(recoveryOfferProvider);
  if (!context.mounted) return;
  final strings = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.recoveryCode),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Text(strings.recoveryShow),
          SelectableText(
            words,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: words)),
          child: Text(MaterialLocalizations.of(context).copyButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    ),
  );
}

/// Settings' way to make a recovery code at any time.
class RecoveryCodeTile extends ConsumerWidget {
  /// The tile.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.key_outlined),
      title: Text(strings.recoveryCode),
      subtitle: Text(strings.recoveryCodeAbout),
      enabled: ref.watch(vaultProvider).hasValue,
      onTap: () => createRecoveryCode(context, ref),
    );
  }
}

// Opens the store with its recovery code, under a new keystore key.
class _RecoveryCodeDialog extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_RecoveryCodeDialog> createState() => _RecoveryState();
}

class _RecoveryState extends ConsumerState<_RecoveryCodeDialog> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final vault = await ref.read(vaultOpenerProvider)();
    try {
      await vault.unlock(recoveryCode: _code.text);
      await vault.lock();
    } on Exception {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).recoveryWrong);
      }
      return;
    }
    _reopen(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.recoveryCodeEnter),
      content: TextField(
        controller: _code,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: strings.recoveryCode,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(onPressed: _unlock, child: Text(strings.recoveryUnlock)),
      ],
    );
  }
}
