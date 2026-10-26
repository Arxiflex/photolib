import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/pairing.dart';
import 'package:photolib/features/servers/server_pages.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';

/// The password setup link that [route], where the app was opened, brings
/// (ADR-0243): photolibd's page at the link hands the app
/// `photolib:/password-setup?server=…&handle=…&token=…`, and the web app is
/// [page], the link itself, `<server>/#/password-setup?handle=…&token=…`.
Uri? setupLink(Uri route, {Uri? page}) {
  final query = route.queryParameters;
  final server = switch (query['server']) {
    final address? => Uri.tryParse(address),
    null => page?.removeFragment(),
  };
  if (server == null || !{'http', 'https'}.contains(server.scheme)) {
    return null;
  }
  return switch (query) {
    {'handle': final handle, 'token': final token} => pairingLink(
      SavedServer(endpoints: [server], instance: ''),
      (handle: handle, token: token),
    ),
    _ => null,
  };
}

/// The password setup link the app was opened with, until [SetupLinks] takes
/// it.
class OpenedSetupLink extends Notifier<Uri?> {
  @override
  Uri? build() => null;

  /// Keeps [link], if any.
  void open(Uri? link) => state = link ?? state;

  /// The link, which only one page takes.
  Uri? take() {
    final link = state;
    state = null;
    return link;
  }
}

/// The password setup link the app was opened with.
final openedSetupLinkProvider = NotifierProvider<OpenedSetupLink, Uri?>(
  OpenedSetupLink.new,
);

/// Opens the password setup link the app was opened with over [child]: *Add
/// a server* with the link filled in, or the password page of the saved
/// server it is for while signed out; else that server's page, saying what to
/// do first, as the install has one server (ADR-0125).
class SetupLinks extends ConsumerStatefulWidget {
  /// Links over [child].
  const new({required this.child, super.key});

  /// The page under the links.
  final Widget child;

  @override
  ConsumerState<SetupLinks> createState() => _SetupLinksState();
}

class _SetupLinksState extends ConsumerState<SetupLinks> {
  @override
  void initState() {
    super.initState();
    // Opened before the first frame too: pages open after the build.
    ref.listenManual(openedSetupLinkProvider, (_, link) {
      if (link != null) scheduleMicrotask(() => unawaited(_open()));
    }, fireImmediately: true);
  }

  Future<void> _open() async {
    final link = ref.read(openedSetupLinkProvider.notifier).take();
    if (link == null) return;
    final saved = (await ref.read(accountsProvider.future)).server;
    final setup = passwordSetup('$link');
    if (setup == null || !mounted) return;
    final mine =
        saved?.account == null &&
        (saved?.endpoints.contains(endpoints('$link')?.single) ?? false);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (saved) {
          null => AddServerPage(address: '$link'),
          _ when mine => SetPasswordPage(
            handle: setup.handle,
            token: setup.token,
          ),
          _ => const ServerPage(),
        },
      ),
    );
    if (saved != null && !mine) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).serverSetupLinkElsewhere),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
