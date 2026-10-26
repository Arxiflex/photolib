import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/accounts.dart';
import 'package:photolib/features/servers/ksf.dart';
import 'package:photolib/features/servers/link.dart';
import 'package:photolib/features/servers/opaque.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError, KeyClass;
import 'package:protobuf/protobuf.dart';

export 'package:photolib/features/servers/accounts.dart';
export 'package:photolib/features/servers/ksf.dart';
export 'package:photolib/features/servers/link.dart';
export 'package:photolib/features/servers/opaque.dart';

/// Every server and its session: a class B object of the vault (docs/21 §3,
/// ADR-0209), which needs no platform keystore when the store fell back to a
/// passphrase (ADR-0154). Earlier builds kept it in the keystore.
final serverStoreProvider = Provider<SecretStore>((ref) {
  final vault = ref.watch(vaultProvider.future);
  return _Moved(
    const KeystoreEntry('server'),
    VaultText(() => vault, 'server', KeyClass.b),
  );
});

/// [_to], which takes over what [_from] held at the first read that finds
/// nothing in it.
class _Moved implements SecretStore {
  const new(this._from, this._to);

  final SecretStore _from;
  final SecretStore _to;

  @override
  Future<String?> read() async {
    if (await _to.read() case final value?) return value;
    final String? held;
    try {
      held = await _from.read();
    } on KeystoreUnavailable {
      return null;
    }
    if (held != null) {
      await _to.write(held);
      await _from.write(null);
    }
    return held;
  }

  @override
  Future<void> write(String? value) => _to.write(value);
}

/// The servers, with the sessions this install keeps there across restarts
/// until a server ends one, and the one in use.
final accountsProvider = AsyncNotifierProvider<AccountsNotifier, Accounts>(
  AccountsNotifier.new,
);

/// The server in use, if any.
final serverProvider = Provider<AsyncValue<SavedServer?>>(
  (ref) => ref.watch(accountsProvider).whenData((a) => a.server),
);

/// The replica in use, once the accounts are read: the account's, else the
/// device's own, as when they cannot be read.
final replicaNameProvider = FutureProvider<String>((ref) async {
  try {
    return await ref.watch(accountsProvider.selectAsync((a) => a.replica));
  } on Object {
    return standaloneReplica;
  }
});

/// The server answered the password sign-in of [account] with a second
/// factor [challenge] (ADR-0088), which [AccountsNotifier.finishSecondFactor]
/// answers.
class SecondFactorRequired implements Exception {
  /// The challenge of [account] to answer.
  const new(this.account, this.challenge);

  /// The handle or email that signs in.
  final String account;

  /// The factors that answer it, and the sign-in's id.
  final SecondFactorChallenge challenge;

  /// Whether a code answers it.
  bool get takesCode => challenge.factors.any(
    (factor) => factor != SecondFactor.SECOND_FACTOR_PASSKEY,
  );
}

/// Six digits are an authenticator's code, anything else a recovery code.
bool isTotpCode(String code) => RegExp(r'^\d{6}$').hasMatch(code);

/// Whether [password] opens the PKCS#12 bundle [identity].
bool opensIdentity(Uint8List identity, String password) {
  try {
    SecurityContext()
      ..useCertificateChainBytes(identity, password: password)
      ..usePrivateKeyBytes(identity, password: password);
    return true;
  } on TlsException {
    return false;
  }
}

/// How long before its end a session is renewed at a start (ADR-0125).
const _renewal = Duration(days: 60);

/// Adds, switches, signs in and out of and removes accounts, keeping each
/// change in [serverStoreProvider]. What a sign-in or a revocation brings
/// lands on its own account, in use or not by then (ADR-0234).
class AccountsNotifier extends AsyncNotifier<Accounts> {
  /// The replicas whose account renewed its session this start.
  final _rotated = <String>{};
  final _refreshing = <String, Future<void>>{};
  var _writing = Future<void>.value();

  @override
  Future<Accounts> build() async {
    final saved = await ref.watch(serverStoreProvider).read();
    if (saved == null) return const Accounts([]);
    final accounts = Accounts.fromJson(jsonDecode(saved) as Map);
    for (final server in accounts.servers) {
      if (server.account != null) Future(() => refresh(server)).ignore();
    }
    return accounts;
  }

  /// Renews [server]'s session once a start when fewer than 60 of its 90
  /// days are left, so that a device in use never reaches its end; until the
  /// new token is used the server takes the old one too (ADR-0052,
  /// ADR-0125). Asks again whether its account administers the server, which
  /// an administrator may have changed since. Offline, everything stays as it
  /// is, and so it does once the app let go of the accounts meanwhile.
  Future<void> refresh(SavedServer server) =>
      _refreshing[server.replica] ??= _refresh(server).whenComplete(
        // Never waited for: it is this very refresh.
        () => unawaited(_refreshing.remove(server.replica)),
      );

  Future<void> _refresh(SavedServer saved) async {
    if (!ref.mounted) return;
    var server = saved;
    final old = server.account;
    if (old == null) return;
    try {
      final due = old.expires?.isBefore(DateTime.now().add(_renewal));
      if ((due ?? true) && _rotated.add(server.replica)) {
        final link = ref.read(connectProvider)(server.config, server.instance);
        final Session renewed;
        try {
          renewed = (await AuthServiceApi(
            link,
          ).rotateSession(null, RotateSessionRequest())).session;
        } finally {
          link.close();
        }
        if (!ref.mounted || _find(server)?.account?.token != old.token) return;
        if (renewed.token.isNotEmpty) {
          final account = _account(old.name, renewed, admin: old.admin);
          await _update(server, (s) => s.signedIn(account));
          server = server.signedIn(account);
        }
      }
      final token = server.config.session;
      final admin = await _administers(server);
      if (!ref.mounted) return;
      if (_find(server)?.account case final now?
          when now.token == token && now.admin != admin) {
        await _update(server, (s) => s.signedIn(now.copyWith(admin: admin)));
      }
    } on CallError catch (error) {
      if (error.logsOut && ref.mounted) await ended(old.token);
    }
  }

  Accounts get _accounts => state.requireValue;

  /// The server in use, which every action but [add] and [use] needs.
  SavedServer get _server =>
      _accounts.server ?? (throw StateError('no server in use'));

  /// The account on [server]'s replica as it is now, unless it was removed.
  SavedServer? _find(SavedServer server) => state.value?.servers
      .where((s) => s.replica == server.replica)
      .firstOrNull;

  /// Shows [accounts] at once, which makes a switch instant, and keeps them
  /// after every change before.
  Future<void> _save(Accounts accounts) {
    state = AsyncData(accounts);
    final store = ref.read(serverStoreProvider);
    final json = accounts.servers.isEmpty
        ? null
        : jsonEncode(accounts.toJson());
    return _writing = _writing
        .then((_) {}, onError: (_) {})
        .then((_) => store.write(json));
  }

  /// Replaces the account on [server]'s replica with what [change] makes of
  /// it, unless it was removed.
  Future<void> _update(
    SavedServer server,
    SavedServer Function(SavedServer) change,
  ) async {
    final Accounts(:servers, :current) = _accounts;
    final at = servers.indexWhere((s) => s.replica == server.replica);
    if (at < 0) return;
    await _save(
      Accounts([...servers]..[at] = change(servers[at]), current: current),
    );
  }

  /// Adds [server], signed out, and switches to it: on the device's replica
  /// when no account has it, else on a new one.
  Future<void> add(SavedServer server) {
    final servers = _accounts.servers;
    final id = [
      for (final b in randomBytes(8)) b.toRadixString(16).padLeft(2, '0'),
    ];
    final replica = servers.any((s) => s.replica == standaloneReplica)
        ? 'replica-${id.join()}'
        : standaloneReplica;
    return _save(
      Accounts([...servers, server.on(replica)], current: servers.length),
    );
  }

  /// Keeps [server] in place of the account on its replica, as when its
  /// certificate is trusted.
  Future<void> put(SavedServer server) => _update(server, (_) => server);

  /// Switches to the account at [index].
  Future<void> use(int index) =>
      _save(Accounts(_accounts.servers, current: index));

  /// Forgets the account in use, after signing out of it; the first left is
  /// then in use.
  Future<void> remove() async {
    final gone = _server.replica;
    await signOut();
    await _save(
      Accounts([
        for (final s in _accounts.servers)
          if (s.replica != gone) s,
      ]),
    );
  }

  /// Signs in to the server in use with OPAQUE through the kernel: [account]
  /// is a handle or an email.
  Future<void> signIn(String account, String password) => _anonymously((
    server,
    link,
  ) async {
    await _keep(server, account, await _login(link, server, account, password));
  });

  /// Creates the first administrator of the server in use with the [token]
  /// photolibd logged, sets their password and signs them in. Once created,
  /// they are kept on that server's account until their password is set,
  /// also across restarts.
  Future<void> setUp(String token, User user, String password) async {
    final server = _server;
    var created = server.setup;
    if (created == null) {
      created = await _anonymously<Setup>((server, link) async {
        final answer = await SetupServiceApi(link).createFirstAdmin(
          null,
          CreateFirstAdminRequest(setupToken: token, user: user),
        );
        return (token: answer.passwordSetup.token, account: user.handle);
      });
      final setup = created;
      await _update(server, (s) => s.settingUp(setup));
    }
    // A first administrator has no private libraries.
    await _setPasswordOn(
      server,
      created.token,
      created.account,
      password,
      reset: () async => true,
    );
  }

  /// Signs [account] in to the server in use with [answer], a TOTP code, a
  /// recovery code or a passkey's credential for its challenge.
  Future<void> finishSecondFactor(
    String account,
    FinishSecondFactorRequest answer,
  ) => _anonymously((server, link) async {
    final answered = await AuthServiceApi(link)
        .finishSecondFactor(null, answer);
    await _keep(server, account, answered.session);
  });

  /// Sets the password of [account] on the server in use with a password
  /// setup token, from an administrator's link or `photolibd admin
  /// password-setup`, and signs in. For an account with private libraries,
  /// which a new password does not reopen, [reset] is asked first; nothing
  /// changes unless it agrees (ADR-0052).
  Future<void> setPassword(
    String token,
    String account,
    String password, {
    required Future<bool> Function() reset,
  }) => _setPasswordOn(_server, token, account, password, reset: reset);

  Future<void> _setPasswordOn(
    SavedServer server,
    String token,
    String account,
    String password, {
    required Future<bool> Function() reset,
  }) => _anonymously(on: server, (server, link) async {
    if (await _setPassword(link, token, password, reset: reset)) {
      await _keep(
        server,
        account,
        await _login(link, server, account, password),
      );
    }
  });

  /// Ends this device's session on the server in use; offline, the app
  /// forgets it all the same.
  Future<void> signOut() async {
    final server = _server;
    if (server.account case final account?) {
      final link = ref.read(connectProvider)(server.config, server.instance);
      try {
        await AuthServiceApi(
          link,
        ).revokeDevice(null, RevokeDeviceRequest(deviceId: account.deviceId));
      } on CallError {
        // Unreachable, or ended already.
      } finally {
        link.close();
      }
    }
    await _update(server, (s) => s.signedIn(null));
  }

  /// Renews the session in use when it has less than a month left, as one the
  /// app keeps running for weeks has, so that backup never meets an expired
  /// session or a sign-in with its second factor (ING-25, ADR-0226): the
  /// start's [refresh], once more.
  Future<void> renew() async {
    final server = _server;
    await _refreshing[server.replica];
    if (!ref.mounted) return;
    final now = _find(server);
    final left = now?.account?.expires?.difference(DateTime.now());
    if (now == null || left != null && left > const Duration(days: 30)) {
      return;
    }
    _rotated.remove(server.replica);
    await refresh(now);
  }

  /// A server ended the session of [token] (ADR-0032), unless it was renewed
  /// meanwhile: its account is signed out, in use or not.
  Future<void> ended(String token) async {
    final servers = state.value?.servers ?? const [];
    for (final server in servers) {
      if (server.account?.token == token) {
        await _update(server, (s) => s.signedIn(null, ended: true));
      }
    }
  }

  /// Whether [password] is the signed-in account's: the kernel opens the
  /// server's OPAQUE answer only with it, before any session opens.
  Future<bool> checkPassword(String password) =>
      _anonymously((server, link) async {
        try {
          await _ke3(link, server, server.account?.name ?? '', password);
          return true;
        } on KernelError catch (error) {
          if (error.reason == 'envelope_recovery') return false;
          rethrow;
        }
      });

  /// [work] on a session-less link to [on], else the server in use.
  Future<T> _anonymously<T>(
    Future<T> Function(SavedServer server, Link link) work, {
    SavedServer? on,
  }) async {
    final server = on ?? _server;
    final link = ref.read(connectProvider)(
      server.signedIn(null).config,
      server.instance,
    );
    try {
      return await work(server, link);
    } finally {
      link.close();
    }
  }

  /// Signs [account] in to [server], as the device it knows this install as.
  Future<Session> _login(
    Link link,
    SavedServer server,
    String account,
    String password,
  ) async {
    final (loginId, ke3) = await _ke3(link, server, account, password);
    final finished = await AuthServiceApi(link).finishLogin(
      null,
      FinishLoginRequest(
        loginId: loginId,
        ke3: ke3,
        device: thisDevice()..deviceId = server.deviceId ?? '',
      ),
    );
    if (finished.hasSession()) return finished.session;
    throw SecondFactorRequired(account, finished.secondFactor);
  }

  /// The first OPAQUE round of signing in to [server] as [account]: its login
  /// id and the client's KE3.
  Future<(String, List<int>)> _ke3(
    Link link,
    SavedServer server,
    String account,
    String password,
  ) async {
    var loginId = '';
    final ke3 = await opaqueKe3(ref.read(opaqueProvider), password, (
      ke1,
    ) async {
      final started = await AuthServiceApi(link).startLogin(
        null,
        StartLoginRequest(
          handle: account,
          ke1: ke1,
          deviceId: server.deviceId,
          deviceSecret: server.deviceSecret,
        ),
      );
      loginId = started.loginId;
      return (started.ksfParams, started.ke2);
    });
    return (loginId, ke3);
  }

  Future<bool> _setPassword(
    Link link,
    String token,
    String password, {
    Future<bool> Function()? reset,
  }) async {
    final opaque = ref.read(opaqueProvider);
    final params = await newPasswordParams(ref.read(stretchProvider));
    final randomness = randomBytes(96);
    kernel.OpaqueRegisterRequest step([List<int>? response]) =>
        kernel.OpaqueRegisterRequest(
          password: password,
          params: params,
          randomness: randomness,
          response: response,
        );
    const register = kernel.Method.METHOD_OPAQUE_REGISTER;
    final auth = AuthServiceApi(link);
    final request = await opaque(register, step());
    final started = await auth.startPasswordSetup(
      null,
      StartPasswordSetupRequest(
        registrationRequest: request.message,
        passwordSetupToken: token,
      ),
    );
    if (started.privateLibraries && !(await reset?.call() ?? true)) {
      return false;
    }
    final record = await opaque(register, step(started.registrationResponse));
    await auth.finishPasswordSetup(
      null,
      FinishPasswordSetupRequest(
        registrationRecord: record.message,
        ksfParams: params,
        passwordSetupToken: token,
        registrationId: started.registrationId,
      ),
    );
    return true;
  }

  /// Keeps [session] on [server]'s account, once it knows whether it
  /// administers the server.
  Future<void> _keep(SavedServer server, String name, Session session) async {
    final account = _account(name, session);
    final admin = await _administers(server.signedIn(account));
    await _update(
      server,
      (s) => s.signedIn(account.copyWith(admin: admin), session: session),
    );
  }

  /// Whether the account signed in to [server] administers it: only
  /// administrators may read its settings.
  Future<bool> _administers(SavedServer server) async {
    final link = ref.read(connectProvider)(server.config, server.instance);
    try {
      await AdminServiceApi(link).getSettings(null, GetSettingsRequest());
      return true;
    } on ServerError catch (error) {
      if (error.code != 'permission_denied') rethrow;
      return false;
    } finally {
      link.close();
    }
  }
}

Account _account(String name, Session session, {bool admin = false}) => Account(
  name: name,
  token: session.token,
  deviceId: session.deviceId,
  admin: admin,
  expires: session.hasExpiresAt() ? session.expiresAt.toDateTime() : null,
  userId: session.userId.isEmpty ? null : session.userId,
);

/// This device as sessions and passkeys name it.
Device thisDevice() {
  final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
  final host = kIsWeb ? '' : Platform.localHostname;
  return Device(
    name: host.isEmpty || host == 'localhost' ? 'Photolib ($platform)' : host,
    platform: platform,
  );
}

/// The signed-in server's API and media, for every call of the session: one
/// that the server answers with a revocation signs its account out
/// (ADR-0032), even once another is in use.
final sessionProvider = Provider<Link?>((ref) {
  final server = ref.watch(serverProvider).value;
  final token = server?.account?.token;
  if (server == null || token == null) return null;
  final link = ref.watch(connectProvider)(server.config, server.instance);
  final changes = ref
      .watch(networkChangesProvider)
      .listen((_) => link.networkChanged());
  ref.onDispose(() {
    unawaited(changes.cancel());
    link.close();
  });
  return _Revocable(link, server, ref.read(accountsProvider.notifier));
});

/// Signs [_server]'s account out when the server revokes its session, and
/// asks again whether the account administers the server when the console is
/// refused for want of it.
class _Revocable implements Link {
  new(this._link, this._server, this._accounts);

  final Link _link;
  final SavedServer _server;
  final AccountsNotifier _accounts;

  @override
  Future<T> invoke<T extends GeneratedMessage>(
    ClientContext? ctx,
    String serviceName,
    String methodName,
    GeneratedMessage request,
    T emptyResponse,
  ) => _guard(
    () => _link.invoke(ctx, serviceName, methodName, request, emptyResponse),
  );

  @override
  Future<Media> media(String path, {Map<String, String> headers = const {}}) =>
      _guard(() => _link.media(path, headers: headers));

  @override
  Future<Uri> sign(String path) => _guard(() => _link.sign(path));

  @override
  Future<String> createUpload(int length, String blake3, {String? path}) =>
      _guard(() => _link.createUpload(length, blake3, path: path));

  @override
  Future<void> sendUpload(
    String path,
    int length,
    Stream<List<int>> Function(int offset) read,
  ) => _guard(() => _link.sendUpload(path, length, read));

  @override
  void networkChanged() => _link.networkChanged();

  @override
  void close() => _link.close();

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on CallError catch (error) {
      if (error.logsOut) {
        unawaited(_accounts.ended(_server.account?.token ?? ''));
      }
      if (error case ServerError(:final detail?)
          when detail.code == 'user.admin_required') {
        unawaited(_accounts.refresh(_server));
      }
      rethrow;
    }
  }
}

/// What the server says of itself, asked again while its page shows; an
/// error while it does not answer, or, signed in, [HttpsRequired] where the
/// session may not go.
final FutureProvider<GetServerInfoResponse> serverInfoProvider =
    FutureProvider.autoDispose((ref) async {
      final server =
          await ref.watch(accountsProvider.selectAsync((a) => a.server)) ??
          (throw StateError('no server in use'));
      final link = ref.watch(connectProvider)(server.config, server.instance);
      ref.onDispose(link.close);
      return await ServerInfoServiceApi(link)
          .getServerInfo(null, GetServerInfoRequest());
    });
