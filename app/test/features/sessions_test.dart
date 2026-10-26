import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';
import '../support/server_app.dart';

void main() {
  setUpServerApp();

  Future<void> settings(WidgetTester tester) async {
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.scrollTo(find.text('Diagnostics'));
  }

  for (final admin in [true, false]) {
    testWidgets(
      'each start asks again whether the account administers the server, '
      'which ${admin ? 'promotes' : 'demotes'} it',
      (tester) async {
        keep(ann.copyWith(admin: !admin));
        server = FakeServer({
          if (!admin)
            'AdminService/GetSettings': (_) =>
                refused('permission_denied', 'user.admin_required'),
        });
        await pumpServerApp(tester);
        await settings(tester);
        expect(saved()!.account!.admin, admin);
        expect(
          find.text('Server administration'),
          admin ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets('the console goes once the server says the account no longer '
      'administers it', (tester) async {
    keep(ann);
    var demoted = false;
    Object answer(GeneratedMessage request, String method) => demoted
        ? refused('permission_denied', 'user.admin_required')
        : FakeServer.standard[method]!(request);
    server = FakeServer({
      for (final method in [
        'AdminService/GetSettings',
        'AdminService/GetStatus',
      ])
        method: (request) => answer(request, method),
    });
    await pumpServerApp(tester);
    await settings(tester);
    demoted = true;
    await tester.tapAndSettle(find.text('Server administration'));
    expect(saved()!.account!.admin, isFalse);
    expect(saved()!.account!.token, 'token-1');
    expect(find.text('Sign in as an administrator'), findsOneWidget);
  });

  // Once fewer than 60 of its 90 days are left (ADR-0125).
  for (final (left, renews) in [
    (const Duration(days: 59), true),
    (null, true),
    (const Duration(days: 61), false),
  ]) {
    testWidgets('a session ${left == null ? 'an earlier version kept' : 'with '
                  '${left.inDays} days left'} is ${renews ? '' : 'not '}'
        'renewed at start', (tester) async {
      keep(
        Account(
          name: 'ann',
          token: 'token-1',
          deviceId: 'device-1',
          expires: left == null ? null : DateTime.now().add(left),
        ),
      );
      server = FakeServer({
        'AuthService/RotateSession': (_) => RotateSessionResponse(
          session: Session(
            token: 'token-2',
            deviceId: 'device-1',
            expiresAt: Timestamp.fromDateTime(renewed),
          ),
        ),
      });
      await pumpServerApp(tester);
      await openServer(tester);
      expect(
        server.requests<GeneratedMessage>('AuthService/RotateSession'),
        hasLength(renews ? 1 : 0),
      );
      final account = saved()!.account!;
      expect(account.token, renews ? 'token-2' : 'token-1');
      if (renews) expect(account.expires, renewed);
      expect(
        links.lastWhere((l) => l.$1.session != null).$1.session,
        account.token,
      );
      expect(find.text('Signed in as ann'), findsOneWidget);
    });
  }

  testWidgets('a call made before the session was renewed, whose old token '
      'is refused, does not sign out', (tester) async {
    keep(ann.copyWith(expires: DateTime.now()));
    final rotated = Completer<Object>();
    final status = Completer<Object>();
    server = FakeServer({
      'AuthService/RotateSession': (_) => rotated.future,
      // The first call, made with the old token, waits.
      'AdminService/GetStatus': (request) =>
          server.requests<GeneratedMessage>('AdminService/GetStatus').length ==
              1
          ? status.future
          : FakeServer.standard['AdminService/GetStatus']!(request),
    });
    await pumpServerApp(tester);
    await settings(tester);
    await tester.tap(find.text('Server administration'));
    await tester.pump();
    rotated.complete(
      RotateSessionResponse(
        session: Session(token: 'token-2', deviceId: 'device-1'),
      ),
    );
    await tester.pump();
    status.complete(refused('unauthenticated', 'session.required'));
    await tester.pumpAndSettle();
    expect(saved()!.account!.token, 'token-2');
    expect(saved()!.ended, isFalse);
  });

  testWidgets('any account lists its devices on the server page and signs '
      'one out', (tester) async {
    keep(ann.copyWith(admin: false));
    server = FakeServer({
      'AdminService/GetSettings': (_) =>
          refused('permission_denied', 'user.admin_required'),
      'AuthService/ListDevices': (_) => ListDevicesResponse(
        devices: [
          Device(deviceId: 'device-1', name: 'laptop', current: true),
          Device(
            deviceId: 'device-2',
            name: "Ann's Pixel",
            platform: 'android',
            lastSeenAt: FakeServer.at,
          ),
        ],
      ),
    });
    await pumpServerApp(tester);
    await openServer(tester);
    await tester.tapAndSettle(find.text('Your devices'));
    expect(find.text('laptop'), findsOneWidget);
    expect(find.textContaining('android · Last seen '), findsOneWidget);
    await tester.tapAndSettle(find.text('Sign out').last);
    expect(
      server
          .requests<RevokeDeviceRequest>('AuthService/RevokeDevice')
          .single
          .deviceId,
      'device-2',
    );
    expect(
      server.requests<GeneratedMessage>('AuthService/ListDevices'),
      hasLength(2),
      reason: 'listed again',
    );
    expect(saved()!.account!.token, 'token-1');
  });

  testWidgets('signing this device out from the list signs the app out', (
    tester,
  ) async {
    keep(ann);
    var revoked = false;
    server = FakeServer({
      'AuthService/ListDevices': (_) => revoked
          ? refused('unauthenticated', 'session.required')
          : ListDevicesResponse(
              devices: [
                Device(deviceId: 'device-1', name: 'laptop', current: true),
              ],
            ),
      'AuthService/RevokeDevice': (_) {
        revoked = true;
        return RevokeDeviceResponse();
      },
    });
    await pumpServerApp(tester);
    await openServer(tester);
    await tester.tapAndSettle(find.text('Your devices'));
    await tester.tapAndSettle(find.text('Sign out'));
    expect(saved()!.account, isNull);
    expect(find.text('You are signed out of the server.'), findsOneWidget);
  });
}
