import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/problems.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_api/photolib_api.dart';

/// The passkey relay gave no credential: [name] is the browser's DOMException,
/// such as `NotAllowedError` when the person cancelled.
class PasskeyFailed implements Exception {
  /// The relay failed with [name].
  const new(this.name);

  /// The DOMException's name.
  final String name;
}

/// Runs a WebAuthn `get` ceremony for [options] on photolibd's relay [page]
/// (ADR-0088), or a `create` one when [create], whose button says [label], and
/// returns the credential's JSON.
typedef PasskeyRelay = Future<String> Function(
  Uri page,
  String options,
  String label, {
  bool create,
});

/// The relay in the system browser, on desktops; null where it needs the app's
/// own URL scheme (phones) or runs on its own origin (the web).
final passkeyRelayProvider = Provider<PasskeyRelay?>(
  (ref) =>
      !kIsWeb &&
          const {
            TargetPlatform.linux,
            TargetPlatform.macOS,
            TargetPlatform.windows,
          }.contains(defaultTargetPlatform)
      ? (page, options, label, {create = false}) => loopbackRelay(
          page,
          options,
          label,
          create: create,
          done: label,
          open: _browse,
        )
      : null,
);

/// Opens [page] in the system browser with the ceremony in its fragment and
/// waits, for up to five minutes, for the page to return to a port on this
/// machine's loopback (RFC 8252 §7), which then shows [done].
Future<String> loopbackRelay(
  Uri page,
  String options,
  String label, {
  required String done,
  required Future<void> Function(Uri url) open,
  bool create = false,
}) async {
  final loopback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final back = Uri.parse('http://127.0.0.1:${loopback.port}/');
    final ceremony = Uri(
      queryParameters: {
        'op': create ? 'create' : 'get',
        'options': options,
        'return': '$back',
        'label': label,
      },
    ).query;
    // Listening first: a browser may come back before `open` returns, which
    // some only do once they exit.
    final answered = _answer(loopback, done)..ignore();
    await open(Uri.parse('${page.removeFragment()}#$ceremony'));
    return await answered;
  } finally {
    await loopback.close(force: true);
  }
}

Future<String> _answer(HttpServer loopback, String done) async {
  try {
    await for (final request in loopback.timeout(const Duration(minutes: 5))) {
      final answer = request.uri.queryParameters;
      final (credential, error) = (answer['credential'], answer['error']);
      final response = request.response;
      if (credential == null && error == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        continue;
      }
      response.headers.contentType = ContentType.html;
      response.write(
        '<!doctype html><meta charset="utf-8"><p>${htmlEscape.convert(done)}',
      );
      await response.close();
      if (credential != null) return credential;
      throw PasskeyFailed(error ?? '');
    }
  } on TimeoutException {
    throw const PasskeyFailed('TimeoutError');
  }
  throw const PasskeyFailed('AbortError');
}

Future<void> _browse(Uri url) async {
  final (command, arguments) = switch (defaultTargetPlatform) {
    TargetPlatform.macOS => ('open', ['$url']),
    TargetPlatform.windows => (
      'rundll32',
      ['url.dll,FileProtocolHandler', '$url'],
    ),
    _ => ('xdg-open', ['$url']),
  };
  final opened = await Process.run(command, arguments);
  if (opened.exitCode != 0) throw const PasskeyFailed('NotSupportedError');
}

/// Where photolibd's relay is: on the address whose host passkeys bind to
/// ([options]' `rpId`, or `rp.id` of creation options), beneath its base path,
/// else on that host.
Uri relayPage(List<Uri> endpoints, String options) {
  final rp = switch (jsonDecode(options)) {
    {'rpId': final String id} || {'rp': {'id': final String id}} => id,
    _ => null,
  };
  final base =
      endpoints.where((e) => rp == null || e.host == rp).firstOrNull ??
      Uri(scheme: 'https', host: rp);
  final path = base.path.endsWith('/') ? base.path : '${base.path}/';
  return base.replace(path: '${path}passkey');
}

/// The second step of a password sign-in that the server challenged: a code
/// from the authenticator app, a recovery code or a passkey.
class SecondFactorPage extends ConsumerStatefulWidget {
  /// Answers [required].
  const new(this.required, {super.key});

  /// The route of the page that answers [required].
  static Route<void> route(SecondFactorRequired required) =>
      MaterialPageRoute<void>(builder: (_) => SecondFactorPage(required));

  /// The challenge, and the account that signs in.
  final SecondFactorRequired required;

  @override
  ConsumerState<SecondFactorPage> createState() => _SecondFactorPageState();
}

class _SecondFactorPageState extends ConsumerState<SecondFactorPage> {
  final _code = TextEditingController();
  late bool _recovery = !_factors.contains(SecondFactor.SECOND_FACTOR_TOTP);
  var _busy = false;
  Object? _error;

  SecondFactorChallenge get _challenge => widget.required.challenge;
  List<SecondFactor> get _factors => _challenge.factors;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _answer(Future<FinishSecondFactorRequest> answer) async {
    final s = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountsProvider.notifier)
          .finishSecondFactor(widget.required.account, await answer);
      navigator.pop();
      return;
    } on Object catch (error) {
      _error = switch (error) {
        ServerError(:final detail) when detail?.code == 'login.failed' =>
          s.serverSecondFactorWrong,
        PasskeyFailed() => s.serverPasskeyFailed,
        _ => error,
      };
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<FinishSecondFactorRequest> _passkey(PasskeyRelay relay) async {
    final server = ref.read(serverProvider).requireValue;
    final options = _challenge.passkeyOptionsJson;
    final page = relayPage(server?.endpoints ?? const [], options);
    final label = AppLocalizations.of(context).serverUsePasskey;
    return FinishSecondFactorRequest(
      loginId: _challenge.loginId,
      passkeyCredentialJson: await relay(page, options, label),
    );
  }

  FinishSecondFactorRequest _codeAnswer(String code) => isTotpCode(code)
      ? FinishSecondFactorRequest(loginId: _challenge.loginId, totpCode: code)
      : FinishSecondFactorRequest(
          loginId: _challenge.loginId,
          recoveryCode: code,
        );

  List<Widget> _codes(AppLocalizations s, AppTokens tokens) => [
    Text(s.serverSecondFactorCode),
    SizedBox(height: tokens.sm),
    TextFormField(
      controller: _code,
      autofocus: true,
      keyboardType: _recovery ? null : TextInputType.number,
      autofillHints: _recovery ? null : const [AutofillHints.oneTimeCode],
      decoration: InputDecoration(
        labelText: _recovery ? s.serverRecoveryCode : s.serverTotpCode,
      ),
    ),
    SizedBox(height: tokens.sm),
    Wrap(
      spacing: tokens.sm,
      children: [
        FilledButton(
          onPressed: _busy
              ? null
              : () => _answer(Future.value(_codeAnswer(_code.text.trim()))),
          child: Text(s.serverConfirm),
        ),
        if (!_recovery &&
            _factors.contains(SecondFactor.SECOND_FACTOR_RECOVERY_CODE))
          TextButton(
            onPressed: () => setState(() => _recovery = true),
            child: Text(s.serverUseRecoveryCode),
          ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final relay = ref.watch(passkeyRelayProvider);
    final passkey =
        relay != null &&
        _factors.contains(SecondFactor.SECOND_FACTOR_PASSKEY) &&
        _challenge.passkeyOptionsJson.isNotEmpty;
    final codes =
        _factors.contains(SecondFactor.SECOND_FACTOR_TOTP) ||
        _factors.contains(SecondFactor.SECOND_FACTOR_RECOVERY_CODE);
    return Scaffold(
      appBar: AppBar(title: Text(s.serverSecondFactorTitle)),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.all(tokens.md),
          children: [
            if (!passkey && !codes) Text(s.problemSecondFactor),
            if (codes) ..._codes(s, tokens),
            if (passkey) ...[
              SizedBox(height: tokens.md),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.key_outlined),
                onPressed: _busy ? null : () => _answer(_passkey(relay)),
                label: Text(s.serverUsePasskey),
              ),
            ],
            if (_error case final error?)
              Padding(
                padding: EdgeInsets.only(top: tokens.md),
                child: switch (error) {
                  final String message => Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  _ => ProblemView(error),
                },
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
