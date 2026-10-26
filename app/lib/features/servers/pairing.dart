import 'package:photolib/features/servers/servers.dart';

/// What a pairing link brings (MOB-16, MOB-17): every address of a server, the
/// certificate it pins and its instance, so that nobody types them.
typedef Pairing = ({List<Uri> endpoints, String? pin, String? instance});

/// The link that pairs a device with [server]: its first address with the
/// others, its pin and its instance in the fragment, which reaches no server's
/// log. With [setup] it also brings a password setup token for its handle
/// (ADR-0052). *Add a server* takes it, as the web app will.
Uri pairingLink(SavedServer server, [({String handle, String token})? setup]) {
  final [first, ...others] = server.endpoints;
  final query = Uri(
    queryParameters: <String, Object>{
      if (setup != null) ...{'handle': setup.handle, 'token': setup.token},
      if (others.isNotEmpty) 'address': [for (final other in others) '$other'],
      'pin': ?server.pin,
      if (server.instance.isNotEmpty) 'instance': server.instance,
    },
  ).query;
  return first.replace(
    path: first.path.endsWith('/') ? first.path : '${first.path}/',
    fragment: '/${setup == null ? 'pair' : 'password-setup'}?$query',
  );
}

final _paired = RegExp(r'^/(pair|password-setup)\?');

/// What the first pairing or password setup link among [text]'s lines brings.
Pairing? pairing(String text) {
  for (final line in text.split('\n')) {
    final url = Uri.tryParse(line.trim());
    if (url == null || !_paired.hasMatch(url.fragment)) continue;
    final query = Uri(query: url.fragment.split('?').last).queryParametersAll;
    return (
      endpoints: [
        url.removeFragment(),
        for (final address in query['address'] ?? const <String>[])
          Uri.parse(address),
      ],
      pin: query['pin']?.first,
      instance: query['instance']?.first,
    );
  }
  return null;
}

/// The handle and token of the first password setup link among [text]'s
/// lines.
({String handle, String token})? passwordSetup(String text) {
  for (final line in text.split('\n')) {
    final fragment = Uri.tryParse(line.trim())?.fragment ?? '';
    if (!fragment.startsWith('/password-setup?')) continue;
    final query = Uri.splitQueryString(fragment.split('?').last);
    if (query case {'handle': final handle, 'token': final token}) {
      return (handle: handle, token: token);
    }
  }
  return null;
}

/// The addresses of a server, one a line, as URLs; https:// unless one says
/// otherwise. Null when one cannot be an address.
List<Uri>? endpoints(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty);
  final urls = [
    for (final line in lines)
      if (line.contains(RegExp(r'\s')))
        null
      else
        Uri.tryParse(line.contains('://') ? line : 'https://$line')
            ?.removeFragment(),
  ];
  final valid = urls.every(
    (url) =>
        url != null &&
        {'http', 'https'}.contains(url.scheme) &&
        url.host.isNotEmpty,
  );
  return urls.isEmpty || !valid ? null : urls.cast();
}

/// Headers, one `Name: value` a line; null when a line is not one.
Map<String, String>? headers(String text) {
  final found = <String, String>{};
  for (final line in text.split('\n').where((l) => l.trim().isNotEmpty)) {
    final colon = line.indexOf(':');
    final name = colon < 0 ? '' : line.substring(0, colon).trim();
    if (name.isEmpty || name.contains(' ')) return null;
    found[name] = line.substring(colon + 1).trim();
  }
  return found;
}

/// Whether [text] is a proxy as host:port.
bool isProxy(String text) => _proxy.hasMatch(text);

final _proxy = RegExp(r'^[^\s:/]+:\d{1,5}$');
