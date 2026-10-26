import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/own_origin.dart';
import 'package:photolib/features/servers/server_pages.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';

/// The servers in Settings: each switches to its account and opens its page,
/// and the last tile adds one. Until the store says which it keeps, it offers
/// none of that: an account added then would replace them.
class ServerList extends ConsumerWidget {
  /// The tiles under Settings' server heading.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final state = ref.watch(accountsProvider);
    if (!state.hasValue) {
      final failed = state.hasError && !state.isLoading;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(failed ? Icons.error_outline : Icons.dns_outlined),
        title: Text(failed ? s.serverUnreadable : s.serverLoading),
        enabled: failed,
        trailing: failed
            ? TextButton(
                onPressed: () {
                  if (ref.read(vaultProvider).hasError) {
                    ref.invalidate(vaultProvider);
                  }
                  ref.invalidate(accountsProvider);
                },
                child: Text(s.errorRetry),
              )
            : null,
      );
    }
    final Accounts(:servers, :current) = state.requireValue;
    void open(Widget page) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page));
    return Column(
      children: [
        for (final (i, server) in servers.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            selected: servers.length > 1 && i == current,
            title: Text(server.name),
            subtitle: Text(switch (server.account) {
              final account? => s.serverSignedInAs(account.name),
              null => s.serverSignedOut,
            }),
            onTap: () {
              unawaited(ref.read(accountsProvider.notifier).use(i));
              open(const ServerPage());
            },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add),
          title: Text(s.serverAdd),
          // A browser offers the address it was served from (M2-25).
          onTap: () => open(
            AddServerPage(address: ref.read(ownOriginProvider)?.toString()),
          ),
        ),
      ],
    );
  }
}
