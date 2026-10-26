import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';

/// Switches accounts in one tap, in the app bar while there are several
/// (ADR-0234).
class AccountSwitcher extends ConsumerWidget {
  /// The switcher of [accountsProvider].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider).value;
    if (accounts == null || accounts.servers.length < 2) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<int>(
      icon: const Icon(Icons.switch_account_outlined),
      tooltip: s.serverSwitch,
      onSelected: (i) => unawaited(ref.read(accountsProvider.notifier).use(i)),
      itemBuilder: (context) => [
        for (final (i, server) in accounts.servers.indexed)
          CheckedPopupMenuItem(
            value: i,
            checked: i == accounts.current,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(server.account?.name ?? s.serverSignedOut),
                Text(server.name, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

/// [child] anew for each account, so that nothing it holds, such as a
/// selection, outlives a switch (ADR-0234).
class AccountScope extends ConsumerWidget {
  /// [child], keyed by the replica in use.
  const new({required this.child, super.key});

  /// A tab's page.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => KeyedSubtree(
    key: ValueKey(ref.watch(replicaNameProvider).value),
    child: child,
  );
}
