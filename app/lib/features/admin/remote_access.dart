import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/tokens.dart';

/// The service whose nodes fetch a URL from outside (ADR-0311).
final Uri checkHost = Uri.parse('https://check-host.net/');

/// The client that asks [checkHost]; tests fake it.
final outsideProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Whether [checkHost]'s nodes reach [url] (OPS-28): one that gets a 200
/// passes; [polls] reads of their results, [poll] apart, before giving up.
Future<({bool reachable, String detail})> checkFromOutside(
  http.Client client,
  Uri url, {
  Duration poll = const Duration(seconds: 2),
  int polls = 15,
}) async {
  const json = {'accept': 'application/json'};
  const limit = Duration(seconds: 30);
  final started = await client
      .get(
        checkHost
            .resolve('check-http')
            .replace(queryParameters: {'host': '$url', 'max_nodes': '3'}),
        headers: json,
      )
      .timeout(limit);
  final id = switch (jsonDecode(started.body)) {
    {'request_id': final String id} => id,
    _ => null,
  };
  if (id == null) return (reachable: false, detail: started.body);
  var detail = '';
  for (var i = 0; i < polls; i++) {
    await Future<void>.delayed(poll);
    final result = await client
        .get(checkHost.resolve('check-result/$id'), headers: json)
        .timeout(limit);
    detail = result.body;
    // A node answers null until it is done, then [[ok, seconds, message,
    // status, address]].
    final nodes = (jsonDecode(detail) as Map<String, Object?>).values;
    final done = nodes.whereType<List<Object?>>().toList();
    if (done.any(
      (node) => switch (node) {
        [[_, _, _, '200', ...]] => true,
        _ => false,
      },
    )) {
      return (reachable: true, detail: detail);
    }
    if (nodes.isNotEmpty && done.length == nodes.length) break;
  }
  return (reachable: false, detail: detail);
}

/// The admin console's remote access (OPS-28): three ways in without
/// port-forwarding, their configuration filled in from this app's addresses,
/// and a test of the public address from outside.
class RemoteAccess extends ConsumerStatefulWidget {
  /// The section.
  const new({super.key});

  @override
  ConsumerState<RemoteAccess> createState() => _RemoteAccessState();
}

class _RemoteAccessState extends ConsumerState<RemoteAccess> {
  ({bool reachable, String detail})? _result;
  var _busy = false;

  Future<void> _test(Uri url) async {
    final s = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.adminRemoteTest),
        content: Text(s.adminRemoteTestAsk(checkHost.host, '$url')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(MaterialLocalizations.of(context).continueButtonLabel),
          ),
        ],
      ),
    );
    if (go != true) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    ({bool reachable, String detail}) result;
    try {
      result = await checkFromOutside(ref.read(outsideProvider), url);
    } on Exception catch (error) {
      result = (reachable: false, detail: '$error');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final endpoints = ref.watch(serverProvider).value?.endpoints ?? const [];
    final public = endpoints.where((url) => url.scheme == 'https').firstOrNull;
    return ListView(
      padding: EdgeInsets.all(tokens.md),
      children: [
        Semantics(
          header: true,
          child: Text(
            s.adminRemote,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        SizedBox(height: tokens.sm),
        Text(s.adminRemoteBody),
        for (final (name, about, lines) in _paths(s, endpoints))
          ExpansionTile(
            title: Text(name),
            subtitle: Text(about),
            tilePadding: EdgeInsets.zero,
            expandedAlignment: AlignmentDirectional.centerStart,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                lines.join('\n'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: Text(s.problemCopy),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: lines.join('\n'))),
              ),
            ],
          ),
        SizedBox(height: tokens.md),
        if (public == null)
          Text(s.adminRemoteNoAddress)
        else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: _busy ? null : () => _test(public.resolve('healthz')),
              child: Text(s.adminRemoteTest),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_result case (:final reachable, :final detail))
          ExpansionTile(
            leading: Icon(
              reachable ? Icons.check_circle_outline : Icons.error_outline,
            ),
            title: Text(
              reachable ? s.adminRemoteReachable : s.adminRemoteUnreachable,
            ),
            tilePadding: EdgeInsets.zero,
            children: [SelectableText(detail)],
          ),
      ],
    );
  }
}

/// Each way in: its name, what it needs and its configuration, filled in from
/// [endpoints], this app's addresses of the server.
List<(String, String, List<String>)> _paths(
  AppLocalizations s,
  List<Uri> endpoints,
) {
  final public = endpoints.where((url) => url.scheme == 'https').firstOrNull;
  final local = endpoints.where((url) => url.scheme == 'http').firstOrNull;
  final wan = public?.host ?? 'photos.example.org';
  final lan = local == null ? 'photolibd:8080' : '${local.host}:${local.port}';
  return [
    // i18n-ok: product names
    (
      'Tailscale, Headscale',
      s.adminRemoteTailscale,
      ['tailscale serve --bg http://127.0.0.1:${local?.port ?? 8080}'],
    ),
    // i18n-ok: product names
    (
      'WireGuard',
      s.adminRemoteWireguard,
      [
        '[Interface]',
        'Address = 10.8.0.2/32',
        "PrivateKey = <this device's private key>",
        '',
        '[Peer]',
        "PublicKey = <the server's public key>",
        'Endpoint = $wan:51820',
        'AllowedIPs = 10.8.0.1/32',
      ],
    ),
    // i18n-ok: product names
    (
      'Cloudflare Tunnel',
      s.adminRemoteCloudflare,
      [
        'tunnel: photolib',
        'credentials-file: /etc/cloudflared/photolib.json',
        'ingress:',
        '  - hostname: $wan',
        '    service: http://$lan',
        '  - service: http_status:404',
      ],
    ),
  ];
}
