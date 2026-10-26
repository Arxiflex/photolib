import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:photolib_api/photolib_api.dart';

/// Where this install is signed in on its server: the session's bearer and
/// device (ADR-0052), what the person signed in with, and whether the account
/// administers the server.
@immutable
class Account {
  /// The session [token] of [deviceId], signed in as [name].
  const new({
    required this.name,
    required this.token,
    required this.deviceId,
    this.admin = false,
    this.expires,
    this.userId,
  });

  /// The handle or email signed in with.
  final String name;

  /// The session's bearer.
  final String token;

  /// The device the session is bound to.
  final String deviceId;

  /// Whether the account administers the server.
  final bool admin;

  /// When the session ends unless renewed; null for one an earlier version
  /// kept, which did not say.
  final DateTime? expires;

  /// The account's id; null for one an earlier version kept.
  final String? userId;

  /// This account with another role, end or id.
  Account copyWith({bool? admin, DateTime? expires, String? userId}) => Account(
    name: name,
    token: token,
    deviceId: deviceId,
    admin: admin ?? this.admin,
    expires: expires ?? this.expires,
    userId: userId ?? this.userId,
  );
}

/// The replica of an install without a server, which the first account to
/// connect adopts (docs/05 §7).
const standaloneReplica = 'replica';

/// A server this install talks to: the network configuration of
/// docs/admin/clients.md, the instance its addresses must answer as (ADR-0032),
/// the account signed in there, kept in the vault, and the replica that holds
/// what it syncs (ADR-0234).
@immutable
class SavedServer {
  /// The server at [endpoints] that answer as [instance].
  const new({
    required this.endpoints,
    required this.instance,
    this.ca,
    this.identity,
    this.identityPassword,
    this.pin,
    this.proxy,
    this.headers = const {},
    this.account,
    this.ended = false,
    this.deviceId,
    this.deviceSecret,
    this.setup,
    this.replica = standaloneReplica,
  });

  /// The server [toJson] wrote; a build before several accounts kept no
  /// replica.
  factory fromJson(Map<dynamic, dynamic> json) => SavedServer(
    endpoints: [for (final e in json['endpoints'] as List) Uri.parse('$e')],
    instance: json['instance'] as String,
    ca: json['ca'] as String?,
    identity: switch (json['identity']) {
      final String identity => base64.decode(identity),
      _ => null,
    },
    identityPassword: json['identity_password'] as String?,
    pin: json['pin'] as String?,
    proxy: json['proxy'] as String?,
    headers: (json['headers'] as Map).cast(),
    deviceId: json['deviceId'] as String?,
    deviceSecret: json['deviceSecret'] as String?,
    account: switch (json['account']) {
      {
            'name': final String name,
            'token': final String token,
            'device': final String device,
            'admin': final bool admin,
          } &&
          final a =>
        Account(
          name: name,
          token: token,
          deviceId: device,
          admin: admin,
          expires: switch (a['expires']) {
            final int ms => DateTime.fromMillisecondsSinceEpoch(
              ms,
              isUtc: true,
            ),
            _ => null,
          },
          userId: a['user'] as String?,
        ),
      _ => null,
    },
    ended: json['ended'] == true,
    setup: switch (json['setup']) {
      {'token': final String token, 'account': final String account} => (
        token: token,
        account: account,
      ),
      _ => null,
    },
    replica: json['replica'] as String? ?? standaloneReplica,
  );

  /// Its addresses, the fastest that answers as [instance] in use.
  final List<Uri> endpoints;

  /// The instance id of the first answer (ADR-0032).
  final String instance;

  /// PEM certificates of a private CA.
  final String? ca;

  /// The PKCS#12 bundle of a client certificate, for mutual TLS.
  final Uint8List? identity;

  /// The password that opens [identity].
  final String? identityPassword;

  /// The SHA-256 of the self-signed certificate its user confirmed.
  final String? pin;

  /// An HTTP proxy for every request.
  final String? proxy;

  /// Headers of every HTTPS request.
  final Map<String, String> headers;

  /// Where this install is signed in, if it is.
  final Account? account;

  /// The server ended the session, which the app says until the next sign-in.
  final bool ended;

  /// This install as a device of the server, kept across sign-outs.
  final String? deviceId;

  /// The secret of this device's last sign-in, which proves it at the next
  /// one, so that someone guessing at the account locks out only themselves
  /// (ADR-0052).
  final String? deviceSecret;

  /// The password setup token of a first administrator created whose password
  /// is not set yet, and their handle: kept across restarts, as setup is
  /// closed once an administrator exists.
  final Setup? setup;

  /// The vault's replica of this account, which no other account shares.
  final String replica;

  /// What the app calls it: its first address's host.
  String get name => endpoints.first.host;

  /// Its network configuration, with the session if signed in.
  NetworkConfig get config => NetworkConfig(
    endpoints: endpoints,
    trustedCertificates: switch (ca) {
      final pem? => utf8.encode(pem),
      null => null,
    },
    clientIdentity: identity,
    clientIdentityPassword: identityPassword,
    pinnedCertificate: pin,
    proxy: proxy,
    headers: headers,
    session: account?.token,
  );

  /// This server signed in as [account], which ends any setup, or signed out;
  /// a sign-in's [session] brings this device's id and secret.
  SavedServer signedIn(
    Account? account, {
    bool ended = false,
    Session? session,
  }) => _with(account, ended, account == null ? setup : null, session);

  /// This server, signed out, while its first administrator's password is not
  /// set.
  SavedServer settingUp(Setup setup) => _with(null, false, setup);

  /// This server on [replica].
  SavedServer on(String replica) =>
      SavedServer.fromJson({...toJson(), 'replica': replica});

  SavedServer _with(
    Account? account,
    bool ended,
    Setup? setup, [
    Session? session,
  ]) => SavedServer(
    endpoints: endpoints,
    instance: instance,
    ca: ca,
    identity: identity,
    identityPassword: identityPassword,
    pin: pin,
    proxy: proxy,
    headers: headers,
    account: account,
    ended: ended,
    deviceId: session?.deviceId ?? deviceId,
    deviceSecret: switch (session?.deviceSecret) {
      final String secret when secret.isNotEmpty => secret,
      _ => deviceSecret,
    },
    setup: setup,
    replica: replica,
  );

  /// This server with the certificate whose SHA-256 is [pin] trusted.
  SavedServer pinned(String? pin) =>
      SavedServer.fromJson({...toJson(), 'pin': pin});

  /// As kept in the store.
  Map<String, Object?> toJson() => {
    'endpoints': [for (final e in endpoints) '$e'],
    'instance': instance,
    'ca': ca,
    if (identity case final identity?) 'identity': base64.encode(identity),
    'identity_password': identityPassword,
    'pin': pin,
    'proxy': proxy,
    'headers': headers,
    'ended': ended,
    'deviceId': ?deviceId,
    'deviceSecret': ?deviceSecret,
    if (account case final a?)
      'account': {
        'name': a.name,
        'token': a.token,
        'device': a.deviceId,
        'admin': a.admin,
        'expires': a.expires?.millisecondsSinceEpoch,
        'user': a.userId,
      },
    if (setup case final s?) 'setup': {'token': s.token, 'account': s.account},
    'replica': replica,
  };
}

/// The accounts of this install, each a server and its session with a
/// replica of its own, and the one in use (ADR-0234).
@immutable
class Accounts {
  /// [servers], [current] in use.
  const new(this.servers, {this.current = 0});

  /// What [toJson] made, or the one server a build before several accounts
  /// kept.
  factory fromJson(Map<dynamic, dynamic> json) => json.containsKey('endpoints')
      ? Accounts([SavedServer.fromJson(json)])
      : Accounts([
          for (final s in json['servers'] as List)
            SavedServer.fromJson(s as Map),
        ], current: json['current'] as int);

  /// Every server, in the order they were added.
  final List<SavedServer> servers;

  /// The index of the one in use.
  final int current;

  /// The server in use, if any.
  SavedServer? get server => servers.elementAtOrNull(current);

  /// The replica in use: the server's, else the device's own.
  String get replica => server?.replica ?? standaloneReplica;

  /// As the store keeps it.
  Map<String, Object?> toJson() => {
    'servers': [for (final s in servers) s.toJson()],
    'current': current,
  };
}

/// A first administrator created whose password is not set yet: their
/// password setup token and handle.
typedef Setup = ({String token, String account});
