import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/features/desktop/file_drag.dart';
import 'package:photolib/features/servers/server_pages.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/servers/setup_link.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';
import '../support/tiles.dart';

/// A password setup link an administrator sent (ADR-0052), pasted into *Add a
/// server*.
void main() {
  late FakeServer server;
  late MemoryStore store;
  setUp(() => store = MemoryStore());

  Future<void> pump(WidgetTester tester, {List<String> opened = const []}) =>
      pumpApp(
        tester,
        serverStore: store,
        overrides: [
          openedFilesProvider.overrideWithValue(opened),
          connectProvider.overrideWithValue((config, instance) => server),
          certificateProvider.overrideWithValue((config, url) async => null),
          opaqueProvider.overrideWithValue(
            (method, request) async =>
                kernel.OpaqueClientResponse(message: [1]),
          ),
          stretchProvider.overrideWithValue(
            (params) async => const Duration(seconds: 1),
          ),
        ],
      );

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  SavedServer? saved() => store.value == null
      ? null
      : Accounts.fromJson(jsonDecode(store.value!) as Map).server;

  Future<void> addServer(WidgetTester tester, String link) async {
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('Add a server'));
    await tester.enterText(field('Addresses'), link);
    await tester.tapAndSettle(find.text('Connect'));
  }

  ServerError refused(String code, String reason) =>
      ServerError(code, ErrorDetail(code: reason));

  Map<String, Object Function(GeneratedMessage)> login() => {
    'AuthService/StartLogin': (_) => StartLoginResponse(
      loginId: 'login-1',
      ke2: [9],
      ksfParams: List.generate(26, (i) => i),
    ),
    'AuthService/FinishLogin': (_) => FinishLoginResponse(
      session: Session(token: 'token-1', deviceId: 'device-1'),
    ),
  };

  const link =
      'https://photos.example.org/photolib/'
      '#/password-setup?handle=ann&token=ab12';

  // The progress bar runs while a dialog asks.
  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Set password'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> setPassword(WidgetTester tester) async {
    await tester.enterText(field('Password'), 'correct horse');
    await tester.enterText(field('Password again'), 'correct horse');
    await submit(tester);
  }

  testWidgets(
    'pasted as the address adds its server, sets the password and signs in, '
    'and a reset says first that private libraries stay locked',
    (tester) async {
      server = FakeServer({
        'AuthService/StartPasswordSetup': (_) => StartPasswordSetupResponse(
          registrationResponse: [7],
          registrationId: [8],
          privateLibraries: true,
        ),
        ...login(),
      });
      await pump(tester);
      await addServer(tester, link);
      await tester.pumpAndSettle();
      expect(saved()!.endpoints, [
        Uri.parse('https://photos.example.org/photolib/'),
      ]);
      expect(find.text('Set your password'), findsOneWidget);
      expect(find.textContaining('ann'), findsWidgets);
      await setPassword(tester);
      expect(find.text('Your private libraries stay locked'), findsOneWidget);
      await tester.tapAndSettle(find.text('Cancel'));
      expect(
        server.requests<GeneratedMessage>('AuthService/FinishPasswordSetup'),
        isEmpty,
        reason: 'nothing changes unless they go on',
      );
      await submit(tester);
      await tester.tapAndSettle(find.text('Set the password'));
      expect(
        server
            .requests<FinishPasswordSetupRequest>(
              'AuthService/FinishPasswordSetup',
            )
            .single
            .passwordSetupToken,
        'ab12',
      );
      expect(
        server
            .requests<StartLoginRequest>('AuthService/StartLogin')
            .single
            .handle,
        'ann',
      );
      expect(saved()!.account!.name, 'ann');
      expect(find.text('Signed in as ann'), findsOneWidget);
    },
  );

  testWidgets('that expired or was used says to ask for a new one', (
    tester,
  ) async {
    server = FakeServer({
      'AuthService/StartPasswordSetup': (_) =>
          refused('permission_denied', 'password_setup.invalid'),
    });
    await pump(tester);
    await addServer(tester, link);
    await tester.pumpAndSettle();
    await setPassword(tester);
    expect(find.text('This link has expired or was used.'), findsOneWidget);
    expect(find.text('Ask your administrator for a new one.'), findsOneWidget);
    expect(saved()!.account, isNull);
  });

  /// What photolibd's page at the link's address hands the app (ADR-0243).
  const appLink =
      'photolib:/password-setup?handle=ann&token=ab12'
      '&server=https%3A%2F%2Fphotos.example.org%2Fphotolib%2F';

  /// Opens [location] as Android and iOS do a link the app registered.
  Future<void> follow(WidgetTester tester, String location) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {'location': location}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  const here = 'https://photos.example.org/photolib/';
  void keep(String at, {Account? account}) => store.value = jsonEncode(
    SavedServer(
      endpoints: [Uri.parse(at)],
      instance: 'instance-a',
      account: account,
    ).toJson(),
  );

  Future<void> addsTheServer(WidgetTester tester) async {
    expect(find.widgetWithText(AppBar, 'Add a server'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field('Addresses')).controller?.text,
      link,
    );
    await tester.tapAndSettle(find.text('Connect'));
    expect(find.text('Set your password'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Settings'), findsOneWidget, reason: 'the library');
  }

  testWidgets("followed from photolibd's page fills Add a server", (
    tester,
  ) async {
    server = FakeServer({});
    await pump(tester);
    await follow(tester, appLink);
    await addsTheServer(tester);
  });

  testWidgets('opened with on a desktop fills Add a server', (tester) async {
    server = FakeServer({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      fileDragChannel,
      (_) async => null,
    );
    await pump(tester, opened: [openedArg(appLink)]);
    await tester.pumpAndSettle();
    await addsTheServer(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('handed over by a later start on a desktop fills Add a server, '
      'and the log only counts it', (tester) async {
    server = FakeServer({});
    final heard = <LogRecord>[];
    addTearDown(Log.records.listen(heard.add).cancel);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      fileDragChannel,
      (_) async => null,
    );
    await pump(tester);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      fileDragChannel.name,
      fileDragChannel.codec.encodeMethodCall(
        const MethodCall('dropped', [appLink]),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(
      [for (final r in heard) '${r.fields}'],
      everyElement(isNot(contains('ab12'))),
      reason: 'the setup token',
    );
    expect(
      [
        for (final r in heard)
          if (r.message == 'dropped') r.fields,
      ],
      [
        {'files': <String>[], 'links': 1},
      ],
    );
    await addsTheServer(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('followed for the saved server, signed out, sets the password', (
    tester,
  ) async {
    server = FakeServer({});
    keep(here);
    await pump(tester);
    await follow(tester, appLink);
    expect(find.text('Set your password'), findsOneWidget);
    expect(find.textContaining('ann'), findsWidgets);
    expect(tester.tileStarts(find.byType(SetPasswordPage)), {
      'For ann on photos.example.org': tester.getTopLeft(field('Password')).dx,
    });
  });

  for (final (name, account, at) in [
    ('signed in', const Account(name: 'bob', token: 't', deviceId: 'd'), here),
    ('to another server', null, 'https://other.example.org'),
  ]) {
    testWidgets('followed while $name says what to do first', (tester) async {
      server = FakeServer({});
      keep(at, account: account);
      await pump(tester);
      await follow(tester, appLink);
      expect(find.text('Set your password'), findsNothing);
      expect(find.text('Add a server'), findsNothing);
      expect(
        find.text(
          'To use this setup link, sign out of this server first, '
          'or remove it if the link is for another one.',
        ),
        findsOneWidget,
      );
    });
  }

  test("the link a route brings: photolibd's page's, or the web app's "
      'own address', () {
    expect(setupLink(Uri.parse(appLink)), Uri.parse(link));
    expect(
      setupLink(Uri.parse(appLink.replaceFirst(':/', ':///'))),
      Uri.parse(link),
      reason: 'as GVfs hands it from a later start to the running app',
    );
    expect(
      setupLink(
        Uri.parse('/password-setup?handle=ann&token=ab12'),
        page: Uri.parse(link),
      ),
      Uri.parse(link),
    );
    for (final route in [
      '/password-setup?handle=ann&token=ab12',
      'photolib:/password-setup?handle=ann&server=https://a.example',
      'photolib:/password-setup?handle=ann&token=1&server=javascript:x',
    ]) {
      expect(setupLink(Uri.parse(route)), isNull, reason: route);
    }
  });

  test('desktops hand the app links as they are, files as paths', () {
    expect(openedArg(appLink), appLink);
    expect(openedArg('file:///photos/a%20b.jpg'), '/photos/a b.jpg');
    expect(openedArg('/photos/a.jpg'), '/photos/a.jpg');
    expect(openedArg('a.jpg'), File('a.jpg').absolute.path);
  });

  group('every app takes photolib: links', () {
    String read(String path) => File(path).readAsStringSync();
    test('Android', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('<data android:scheme="photolib" />'));
      expect(
        manifest,
        contains(
          '<meta-data android:name="flutter_deeplinking_enabled" '
          'android:value="true" />',
        ),
      );
    });
    for (final platform in ['ios', 'macos']) {
      test(platform, () {
        final plist = read('$platform/Runner/Info.plist');
        expect(
          plist.replaceAll(RegExp(r'\s'), ''),
          contains(
            '<key>CFBundleURLSchemes</key><array><string>photolib</string>',
          ),
        );
        if (platform == 'ios') {
          expect(plist, contains('<key>FlutterDeepLinkingEnabled</key>'));
        }
      });
    }
    test("macOS hands them to Dart as Finder's files", () {
      expect(
        read('macos/Runner/FileDrag.swift'),
        contains('url.scheme == "photolib" ? url.absoluteString'),
      );
    });
    test('Linux', () {
      final entry = read('linux/packaging/org.photolib.photolib.desktop');
      expect(entry, contains('\nExec=photolib %U\n'));
      expect(entry, contains(';x-scheme-handler/photolib;'));
    });
    test('Windows', () {
      expect(
        read('windows/packaging/AppxManifest.xml'),
        contains(
          '<uap3:Protocol Name="photolib" Parameters="&quot;%1&quot;" />',
        ),
      );
    });
  });
}
