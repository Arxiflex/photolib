import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/errors.dart';
import 'package:photolib/core/problems.dart';
import 'package:photolib/features/servers/second_factor.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

/// The server page's entry to its [SecurityView].
class SecurityTile extends StatelessWidget {
  /// The entry.
  const new({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.security_outlined),
    title: Text(AppLocalizations.of(context).securityTitle),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: const ContentWidth(child: SecurityView()),
        ),
      ),
    ),
  );
}

/// Runs [call]; when the server needs a fresh proof first
/// (`step_up.required`), has [prove] get one and runs it once more. Null when
/// the person gave none.
Future<T?> withStepUp<T>(
  Future<T> Function() call,
  Future<bool> Function() prove,
) async {
  try {
    return await call();
  } on ServerError catch (error) {
    if (error.detail?.code != 'step_up.required') rethrow;
    if (!await prove()) return null;
    return await call();
  }
}

/// Proves again on [session] that its account's person is at this device
/// (M2-43): with [password] through the kernel's OPAQUE, else with [code], six
/// digits from an authenticator app or a recovery code.
Future<void> stepUp(
  Opaque opaque,
  RpcClient session, {
  String? password,
  String code = '',
}) async {
  final auth = AuthServiceApi(session);
  var id = '';
  Future<(List<int>, List<int>)> start(List<int> ke1) async {
    final started = await auth.startStepUp(null, StartStepUpRequest(ke1: ke1));
    id = started.stepUpId;
    return (started.ksfParams, started.ke2);
  }

  final FinishStepUpRequest request;
  if (password != null) {
    request = FinishStepUpRequest(
      ke3: await opaqueKe3(opaque, password, start),
    );
  } else {
    await start(const []);
    request = isTotpCode(code)
        ? FinishStepUpRequest(totpCode: code)
        : FinishStepUpRequest(recoveryCode: code);
  }
  await auth.finishStepUp(null, request..stepUpId = id);
}

/// The second factors of the account signed in on the server (ADR-0088): its
/// passkeys, authenticator app and recovery codes. Adding, removing or
/// replacing one asks for the password or a code first when the server wants a
/// fresh proof (ADR-0242). Passkeys are added through the relay, on desktops.
class SecurityView extends ConsumerStatefulWidget {
  /// The view, which reads the session's second factors.
  const new({super.key});

  @override
  ConsumerState<SecurityView> createState() => _SecurityViewState();
}

class _SecurityViewState extends ConsumerState<SecurityView> {
  Future<ListSecondFactorsResponse>? _factors;

  void _reload() => setState(() => _factors = null);

  /// Runs [change] with a step-up when the server asks for one and loads the
  /// factors again; its answer, or null when it failed, which it says, or the
  /// person gave no proof.
  Future<T?> _change<T>(Future<T> Function() change) async {
    try {
      return await withStepUp(
        change,
        () async =>
            mounted &&
            (await showDialog<bool>(
                  context: context,
                  builder: (_) => const _StepUp(),
                ) ??
                false),
      );
    } on CallError catch (error) {
      if (mounted) showProblem(context, error);
      return null;
    } finally {
      if (mounted) _reload();
    }
  }

  Future<void> _show(List<String> codes) async {
    if (codes.isEmpty || !mounted) return;
    final s = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.securityRecoveryCodes),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppTokens.of(context).sm,
          children: [
            Text(s.securityCodesHelp),
            SelectableText(codes.join('\n'), style: _monospace),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _setUpTotp(AuthServiceApi auth) async {
    final started = await _change(
      () => auth.startTotpSetup(null, StartTotpSetupRequest()),
    );
    if (started == null || !mounted) return;
    final codes = await showDialog<List<String>>(
      context: context,
      builder: (_) => _TotpSetup(auth, started),
    );
    if (mounted) _reload();
    await _show(codes ?? const []);
  }

  /// Creates a passkey through photolibd's relay [relay] and adds it.
  Future<void> _addPasskey(AuthServiceApi auth, PasskeyRelay relay) async {
    final s = AppLocalizations.of(context);
    final endpoints = ref.read(serverProvider).value?.endpoints ?? const [];
    try {
      final added = await _change(() async {
        final started = await auth.startPasskeySetup(
          null,
          StartPasskeySetupRequest(),
        );
        final options = started.optionsJson;
        final credential = await relay(
          relayPage(endpoints, options),
          options,
          s.securityAddPasskey,
          create: true,
        );
        return await auth.finishPasskeySetup(
          null,
          FinishPasskeySetupRequest(
            setupId: started.setupId,
            credentialJson: credential,
            name: thisDevice().name,
          ),
        );
      });
      await _show(added?.recoveryCodes ?? const []);
    } on PasskeyFailed {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.securityPasskeyNotAdded)));
      }
    }
  }

  List<Widget> _items(AuthServiceApi auth, ListSecondFactorsResponse factors) {
    final s = AppLocalizations.of(context);
    final relay = ref.watch(passkeyRelayProvider);
    return [
      for (final passkey in factors.passkeys)
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(passkey.name),
          trailing: IconButton(
            tooltip: s.securityRemovePasskey,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _change(
              () => auth.deletePasskey(
                null,
                DeletePasskeyRequest(passkeyId: passkey.passkeyId),
              ),
            ),
          ),
        ),
      if (relay != null)
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(s.securityAddPasskey),
          onTap: () => _addPasskey(auth, relay),
        ),
      ListTile(
        leading: const Icon(Icons.pin_outlined),
        title: Text(s.securityTotp),
        subtitle: Text(s.securityTotpState(factors.totp ? 'on' : 'off')),
      ),
      Padding(
        padding: EdgeInsetsDirectional.only(start: AppTokens.of(context).md),
        child: Wrap(
          spacing: AppTokens.of(context).sm,
          children: [
            OutlinedButton(
              onPressed: () => _setUpTotp(auth),
              child: Text(s.securitySetUp),
            ),
            if (factors.totp)
              TextButton(
                onPressed: () =>
                    _change(() => auth.deleteTotp(null, DeleteTotpRequest())),
                child: Text(s.securityTurnOff),
              ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.password_outlined),
        title: Text(s.securityRecoveryCodes),
        subtitle: Text(s.securityCodesLeft(factors.recoveryCodesLeft)),
        trailing: TextButton(
          onPressed: () async {
            final created = await _change(
              () =>
                  auth.createRecoveryCodes(null, CreateRecoveryCodesRequest()),
            );
            await _show(created?.recoveryCodes ?? const []);
          },
          child: Text(s.securityNewCodes),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    if (session == null) return ErrorView(message: s.serverSignedOut);
    final auth = AuthServiceApi(session);
    return FutureBuilder(
      future: _factors ??= auth.listSecondFactors(
        null,
        ListSecondFactorsRequest(),
      )..ignore(),
      builder: (context, snapshot) => ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(AppTokens.of(context).md),
            child: Semantics(
              header: true,
              child: Text(
                s.securityTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ...switch (snapshot) {
            AsyncSnapshot(
              connectionState: ConnectionState.done,
              :final data?,
            ) =>
              _items(auth, data),
            AsyncSnapshot(:final error?) => [
              ErrorView(error: error, onRetry: _reload),
            ],
            _ => [const Center(child: CircularProgressIndicator())],
          },
        ],
      ),
    );
  }
}

const _monospace = TextStyle(fontFamily: 'monospace');

/// Asks for the password or a code and proves the session with it; closes
/// with true once the server took it.
class _StepUp extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_StepUp> createState() => _StepUpState();
}

class _StepUpState extends ConsumerState<_StepUp> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _prove(RpcClient session) async {
    final s = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final (password, code) = (_password.text, _code.text.trim());
    if (password.isEmpty && code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await stepUp(
        ref.read(opaqueProvider),
        session,
        password: password.isEmpty ? null : password,
        code: code,
      );
      navigator.pop(true);
      return;
    } on Object catch (error) {
      final (:cause, :next, detail: _) = problemOf(s, error);
      // The kernel or the server found a wrong password or code.
      _error = cause == s.problemLoginFailed
          ? s.securityWrongProof
          : '$cause $next';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    return AlertDialog(
      title: Text(s.securityStepUpTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppTokens.of(context).sm,
        children: [
          Text(s.securityStepUpBody),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: s.serverPassword),
          ),
          TextField(
            controller: _code,
            decoration: InputDecoration(labelText: s.securityCode),
          ),
          if (_error case final error?) _Error(error),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy || session == null ? null : () => _prove(session),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// The key of a new TOTP secret and a field for its first code; closes with
/// the recovery codes the server made, if any.
class _TotpSetup extends StatefulWidget {
  const new(this.auth, this.started);

  final AuthServiceApi auth;
  final StartTotpSetupResponse started;

  @override
  State<_TotpSetup> createState() => _TotpSetupState();
}

class _TotpSetupState extends State<_TotpSetup> {
  final _code = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final s = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final finished = await widget.auth.finishTotpSetup(
        null,
        FinishTotpSetupRequest(
          setupId: widget.started.setupId,
          code: _code.text.trim(),
        ),
      );
      navigator.pop(finished.recoveryCodes);
      return;
    } on CallError catch (error) {
      final (:cause, :next, detail: _) = problemOf(s, error);
      _error = error is ServerError && error.code == 'invalid_argument'
          ? s.securityWrongCode
          : '$cause $next';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.securityTotp),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppTokens.of(context).sm,
        children: [
          Text(s.securityTotpHelp),
          SelectableText(widget.started.secret, style: _monospace),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: s.securityCode),
          ),
          if (_error case final error?) _Error(error),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy ? null : _finish,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error));
}
