import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/problems.dart';
import 'package:photolib/features/servers/connection_check.dart';
import 'package:photolib/features/servers/devices.dart';
import 'package:photolib/features/servers/nearby.dart';
import 'package:photolib/features/servers/pairing.dart';
import 'package:photolib/features/servers/second_factor.dart';
import 'package:photolib/features/servers/security.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_api/photolib_api.dart';

/// A file of one of these extensions the user picks; null on the web, whose
/// browser owns TLS.
final fileProvider =
    Provider<Future<XFile?> Function(List<String> extensions)?>(
      (ref) => kIsWeb
          ? null
          : (extensions) => FileSelectorPlatform.instance.openFile(
              acceptedTypeGroups: [XTypeGroup(extensions: extensions)],
            ),
    );

/// [error]'s [ProblemView], which offers [server]'s connection check when the
/// server does not answer, or the message a page gives as [error].
class _Problem extends StatelessWidget {
  const new(this.error, this.server, {this.saved = true});

  final Object error;
  final SavedServer? server;
  final bool saved;

  @override
  Widget build(BuildContext context) => switch (error) {
    final String message => Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
    _ => ProblemView(
      error,
      action: switch ((error, server)) {
        (Unreachable(), final SavedServer server) => (
          AppLocalizations.of(context).checkRun,
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConnectionCheckPage(server, saved: saved),
            ),
          ),
        ),
        _ => null,
      },
    ),
  };
}

/// The page of a form of [fields] that [action] submits, saying why it failed.
class _FormPage extends StatelessWidget {
  const new({
    required this.title,
    required this.form,
    required this.fields,
    required this.action,
    required this.onSubmit,
    required this.busy,
    this.error,
    this.check,
  });

  final String title;
  final GlobalKey<FormState> form;
  final List<Widget> fields;
  final String action;
  final VoidCallback onSubmit;
  final bool busy;
  final Object? error;

  /// The server whose connection check an unreachable [error] offers.
  final SavedServer? check;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ContentWidth(
        child: Form(
          key: form,
          child: ListView(
            padding: EdgeInsets.all(tokens.md),
            children: [
              ...fields,
              SizedBox(height: tokens.md),
              if (error case final error?)
                Padding(
                  padding: EdgeInsets.only(bottom: tokens.md),
                  child: _Problem(error, check, saved: false),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(
                  onPressed: busy ? null : onSubmit,
                  child: Text(action),
                ),
              ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _field(
  TextEditingController controller,
  String label, {
  String? help,
  String? Function(String text)? check,
  bool secret = false,
  bool lines = false,
  bool readOnly = false,
  Widget? suffix,
}) => TextFormField(
  controller: controller,
  obscureText: secret,
  readOnly: readOnly,
  minLines: lines ? 2 : null,
  maxLines: lines ? null : 1,
  decoration: InputDecoration(
    labelText: label,
    helperText: help,
    helperMaxLines: 3,
    suffixIcon: suffix,
  ),
  validator: check == null ? null : (text) => check((text ?? '').trim()),
);

/// Adds a server by its addresses, with the first-contact checks of
/// docs/admin/clients.md: a private CA, a proxy, headers, and a self-signed
/// certificate whose fingerprint the user confirms.
class AddServerPage extends ConsumerStatefulWidget {
  /// The page the server list or a password setup link opens.
  const new({this.address, super.key});

  /// The addresses filled in: a password setup link the app was opened with.
  final String? address;

  @override
  ConsumerState<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends ConsumerState<AddServerPage> {
  final _form = GlobalKey<FormState>();
  late final _addresses = TextEditingController(text: widget.address);
  final _ca = TextEditingController();
  final _proxyText = TextEditingController();
  final _headers = TextEditingController();
  final _identityName = TextEditingController();
  final _identityPassword = TextEditingController();
  Uint8List? _identity;
  var _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final c in [
      _addresses,
      _ca,
      _proxyText,
      _headers,
      _identityName,
      _identityPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The server entered, or the one a pasted pairing link brings.
  SavedServer _server({String? pin, String instance = ''}) {
    final paired = pairing(_addresses.text);
    return SavedServer(
      endpoints:
          paired?.endpoints ??
          endpoints(_addresses.text) ??
          (throw StateError('validated')),
      instance: instance,
      ca: _ca.text.trim().isEmpty ? null : _ca.text.trim(),
      identity: _identity,
      identityPassword: _identity == null ? null : _identityPassword.text,
      pin: pin ?? paired?.pin,
      proxy: _proxyText.text.trim().isEmpty ? null : _proxyText.text.trim(),
      headers: headers(_headers.text) ?? (throw StateError('validated')),
    );
  }

  /// The instance [server] answers as, which must be the one a pairing link
  /// names.
  Future<String> _instance(SavedServer server) async {
    final expected = pairing(_addresses.text)?.instance;
    final link = ref.read(connectProvider)(server.config, expected);
    try {
      final info = await ServerInfoServiceApi(link)
          .getServerInfo(null, GetServerInfoRequest());
      final instance = info.epoch.split('.').first;
      if (expected != null && instance != expected) {
        throw Unreachable('instance $instance, not $expected');
      }
      return instance;
    } finally {
      link.close();
    }
  }

  /// The server that answers, after its user confirmed an untrusted
  /// certificate; null when they did not.
  Future<SavedServer?> _probe() async {
    final server = _server();
    try {
      return _server(instance: await _instance(server));
    } on Unreachable {
      // A pairing link's pin is the certificate to trust.
      if (server.pin != null) rethrow;
      for (final url in server.endpoints.where((u) => u.scheme == 'https')) {
        final pin = await ref.read(certificateProvider)(server.config, url);
        if (pin == null) continue;
        if (!mounted || !await trustCertificate(context, url, pin)) return null;
        return _server(
          pin: pin,
          instance: await _instance(_server(pin: pin)),
        );
      }
      rethrow;
    }
  }

  Future<void> _connect() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final server = await _probe();
      if (server != null) {
        await ref.read(accountsProvider.notifier).add(server);
        final setup = passwordSetup(_addresses.text);
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => setup == null
                ? const ServerPage()
                : SetPasswordPage(handle: setup.handle, token: setup.token),
          ),
        );
        return;
      }
    } on CallError catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The client certificate: a PKCS#12 bundle [pick]ed, and its password.
  List<Widget> _identityFields(
    AppLocalizations s,
    Future<XFile?> Function(List<String> extensions) pick,
  ) => [
    _field(
      _identityName,
      s.serverIdentity,
      readOnly: true,
      suffix: IconButton(
        tooltip: s.serverIdentityChoose,
        icon: const Icon(Icons.badge_outlined),
        onPressed: () async {
          final file = await pick(['p12', 'pfx']);
          if (file == null) return;
          final identity = await file.readAsBytes();
          setState(() => _identity = identity);
          _identityName.text = file.name;
        },
      ),
    ),
    if (_identity case final identity?)
      _field(
        _identityPassword,
        s.serverIdentityPassword,
        secret: true,
        check: (_) => opensIdentity(identity, _identityPassword.text)
            ? null
            : s.serverIdentityInvalid,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final pick = ref.watch(fileProvider);
    return _FormPage(
      title: s.serverAdd,
      form: _form,
      busy: _busy,
      error: _error,
      check:
          endpoints(_addresses.text) == null || headers(_headers.text) == null
          ? null
          : _server(),
      action: s.serverConnect,
      onSubmit: _connect,
      fields: [
        if (ref.watch(nearbyProvider).value case final nearby?
            when nearby.isNotEmpty) ...[
          ListTile(title: Text(s.serverNearby)),
          for (final server in nearby)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(server.name),
              subtitle: Text(server.endpoints.join('\n')),
              onTap: () async {
                _addresses.text = server.endpoints.join('\n');
                await _connect();
              },
            ),
        ],
        _field(
          _addresses,
          s.serverAddresses,
          help: s.serverAddressesHelp,
          lines: true,
          check: (text) =>
              endpoints(text) == null ? s.serverAddressInvalid : null,
        ),
        // The browser owns TLS and proxies (docs/admin/clients.md).
        if (!kIsWeb) ...[
          _field(
            _ca,
            s.serverCa,
            lines: true,
            suffix: pick == null
                ? null
                : IconButton(
                    tooltip: s.serverCaChoose,
                    icon: const Icon(Icons.file_open_outlined),
                    onPressed: () async {
                      final file = await pick(['pem', 'crt', 'cer']);
                      if (file != null) _ca.text = await file.readAsString();
                    },
                  ),
          ),
          if (pick != null) ..._identityFields(s, pick),
          _field(
            _proxyText,
            s.serverProxy,
            check: (text) =>
                text.isEmpty || isProxy(text) ? null : s.serverProxyInvalid,
          ),
        ],
        _field(
          _headers,
          s.serverHeaders,
          help: s.serverHeadersHelp,
          lines: true,
          check: (text) =>
              headers(text) == null ? s.serverHeadersInvalid : null,
        ),
      ],
    );
  }
}

/// The server: its addresses and state, and signing in and out.
class ServerPage extends ConsumerWidget {
  /// The page the server tile opens.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final server = ref.watch(serverProvider).value;
    if (server == null) return Scaffold(appBar: AppBar());
    final info = ref.watch(serverInfoProvider);
    final account = server.account;
    final tokens = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(server.name)),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.all(tokens.md),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                info.hasError
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
              ),
              title: Text(server.endpoints.join('\n')),
              subtitle: info.hasError
                  ? Text(switch (info.error) {
                      HttpsRequired() => s.serverNeedsHttps,
                      _ when account == null => s.problemUnreachable,
                      _ => s.serverOffline,
                    })
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.network_check),
              title: Text(s.checkRun),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConnectionCheckPage(server),
                ),
              ),
            ),
            if (server.ended)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.serverEnded),
              ),
            if (account != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(s.serverSignedInAs(account.name)),
              ),
              const SecurityTile(),
              if (ref.watch(sessionProvider) case final session?)
                DevicesTile(session),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  onPressed: () =>
                      ref.read(accountsProvider.notifier).signOut(),
                  child: Text(s.serverSignOut),
                ),
              ),
            ] else
              _SignIn(methods: info.value?.authMethods),
            SizedBox(height: tokens.lg),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await ref.read(accountsProvider.notifier).remove();
                  navigator.pop();
                },
                child: Text(s.serverRemove),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignIn extends ConsumerStatefulWidget {
  const new({this.methods});

  /// The server's sign-in methods, once it answered.
  final List<AuthMethod>? methods;

  @override
  ConsumerState<_SignIn> createState() => _SignInState();
}

class _SignInState extends ConsumerState<_SignIn> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  Object? _error;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final s = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(accountsProvider.notifier)
          .signIn(_account.text.trim(), _password.text);
    } on SecondFactorRequired catch (required) {
      if (required.takesCode || ref.read(passkeyRelayProvider) != null) {
        navigator.push(SecondFactorPage.route(required));
      } else {
        _error = s.serverSecondFactor;
      }
    } on Object catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final methods = widget.methods;
    if (methods != null && !methods.contains(AuthMethod.AUTH_METHOD_OPAQUE)) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline),
        title: Text(
          methods.contains(AuthMethod.AUTH_METHOD_PASSKEY)
              ? s.serverPasskeyRequired
              : s.serverNoSignIn,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.sm,
      children: [
        _field(_account, s.serverAccount),
        _field(_password, s.serverPassword, secret: true),
        if (_error case final error?)
          _Problem(error, ref.watch(serverProvider).value),
        Wrap(
          spacing: tokens.sm,
          children: [
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: Text(s.serverSignIn),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SetupPage()),
              ),
              child: Text(s.serverSetUp),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SetPasswordPage(),
                ),
              ),
              child: Text(s.serverSetPasswordOpen),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}

/// Sets a new server up: the setup token photolibd logged creates its first
/// administrator, who then sets their password and is signed in.
class SetupPage extends ConsumerStatefulWidget {
  /// The page that sets a new server up.
  const new({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _form = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  var _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final c in [_token, _handle, _name, _email, _password, _again]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountsProvider.notifier)
          .setUp(
            _token.text.trim(),
            User(
              handle: _handle.text.trim(),
              displayName: _name.text.trim(),
              email: _email.text.trim(),
            ),
            _password.text,
          );
      navigator.pop();
      return;
    } on Object catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    String? required(String text) => text.isEmpty ? s.serverRequired : null;
    return _FormPage(
      title: s.serverSetupTitle,
      form: _form,
      busy: _busy,
      error: _error,
      action: s.serverCreateAdmin,
      onSubmit: _create,
      fields: [
        _field(
          _token,
          s.serverSetupToken,
          help: s.serverSetupTokenHelp,
          check: required,
        ),
        _field(
          _handle,
          s.adminHandle,
          help: s.serverHandleHelp,
          check: required,
        ),
        _field(_name, s.adminName, check: required),
        _field(_email, s.adminEmail),
        _field(_password, s.serverPassword, secret: true, check: required),
        _field(
          _again,
          s.serverPasswordAgain,
          secret: true,
          check: (text) =>
              _again.text == _password.text ? null : s.serverPasswordsDiffer,
        ),
      ],
    );
  }
}

/// Sets a password with a password setup token, then signs in: [handle]'s,
/// with the [token] of a link an administrator sent (ADR-0052), or one typed
/// in, from `photolibd admin password-setup`, filled in for a first
/// administrator whose setup stopped before the password was set.
class SetPasswordPage extends ConsumerStatefulWidget {
  /// For a link's [handle] and [token], or for a token typed in.
  const new({this.handle, this.token, super.key});

  /// The account whose password the link sets.
  final String? handle;

  /// The link's password setup token.
  final String? token;

  @override
  ConsumerState<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends ConsumerState<SetPasswordPage> {
  final _form = GlobalKey<FormState>();
  late final _token = TextEditingController(
    text: widget.token ?? _setup?.token,
  );
  late final _account = TextEditingController(
    text: widget.handle ?? _setup?.account,
  );
  final _password = TextEditingController();
  final _again = TextEditingController();
  var _busy = false;
  Object? _error;

  Setup? get _setup => ref.read(serverProvider).value?.setup;
  bool get _link => widget.token != null;

  @override
  void dispose() {
    for (final c in [_token, _account, _password, _again]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Whether to set a password that leaves private libraries locked.
  Future<bool> _reset(AppLocalizations s) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.serverPrivateLibrariesTitle),
          content: Text(s.serverPrivateLibrariesBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.serverPrivateLibrariesGo),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _set() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final s = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(accountsProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await notifier.setPassword(
        _token.text.trim(),
        _account.text.trim(),
        _password.text,
        reset: () => _reset(s),
      );
      if (ref.read(serverProvider).value?.account != null) {
        if (_link) {
          navigator.pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const ServerPage()),
          );
        } else {
          navigator.pop();
        }
        return;
      }
    } on SecondFactorRequired catch (required) {
      navigator.pushReplacement(SecondFactorPage.route(required));
      return;
    } on Object catch (error) {
      _error = switch (error) {
        ServerError(:final detail)
            when !_link && detail?.code == 'password_setup.invalid' =>
          s.serverPasswordSetupInvalid,
        _ => error,
      };
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final server = ref.watch(serverProvider).value?.name ?? '';
    String? required(String text) => text.isEmpty ? s.serverRequired : null;
    return _FormPage(
      title: s.serverSetPasswordTitle,
      form: _form,
      busy: _busy,
      error: _error,
      action: s.serverSetPassword,
      onSubmit: _set,
      fields: [
        if (widget.handle case final handle? when _link)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.serverSetPasswordFor(handle, server)),
          )
        else ...[
          _field(
            _token,
            s.serverPasswordSetupToken,
            help: s.serverPasswordSetupTokenHelp,
            check: required,
          ),
          _field(_account, s.serverAccount, check: required),
        ],
        _field(_password, s.serverPassword, secret: true, check: required),
        _field(
          _again,
          s.serverPasswordAgain,
          secret: true,
          check: (text) =>
              _again.text == _password.text ? null : s.serverPasswordsDiffer,
        ),
      ],
    );
  }
}
