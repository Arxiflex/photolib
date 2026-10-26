import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/problems.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/app_localizations_de.dart';
import 'package:photolib/l10n/app_localizations_en.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError;

import '../support/pump_app.dart';

// Plain-language errors (OPS-30): a cause and a next step, the technical
// detail only behind an expander with copy.
void main() {
  final en = AppLocalizationsEn();

  ServerError refused(String code, String reason, [Map<String, String>? p]) =>
      ServerError(code, ErrorDetail(code: reason, params: p?.entries));

  test('every reason photolibd sends has its own words, which never name a '
      'code', () {
    for (final s in [en, AppLocalizationsDe()]) {
      for (final MapEntry(key: reason, value: words) in reasons.entries) {
        final problem = problemOf(s, refused('data_loss', reason));
        expect((problem.cause, problem.next), words(s), reason: reason);
        expect(problem.cause, isNot(contains(reason)), reason: reason);
        expect(problem.next, isNot(contains(reason)), reason: reason);
      }
    }
    expect(problemOf(en, refused('permission_denied', 'login.failed')), (
      cause: 'Wrong email, sign-in name or password.',
      next: 'Check what you entered and try again.',
      detail: 'permission_denied login.failed',
    ));
  });

  test('a failure without a known reason still gets plain words', () {
    Problem of(Object error) => problemOf(en, error);
    expect(
      of(Unreachable('SocketException: refused')).cause,
      'The server does not answer.',
    );
    expect(of(Unreachable('x')).next, 'Check the connection to see why.');
    expect(
      of(ServerError('unavailable', null)).cause,
      'The server is busy or restarting.',
    );
    expect(
      of(refused('not_found', 'album.gone')).cause,
      'It is no longer on the server.',
    );
    expect(
      of(ServerError('data_loss', null)).cause,
      'Something unexpected went wrong.',
    );
    expect(of(StateError('broken')).next, en.nextReport);
    expect(
      of(KernelError(1, 'envelope_recovery')).cause,
      en.problemLoginFailed,
    );
  });

  testWidgets('shows the cause and next step, and the detail only when asked, '
      'with copy', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    var fixed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ProblemView(
            refused('invalid_argument', 'field.invalid', {'field': 'email'}),
            action: ('Fix it', () => fixed++),
          ),
        ),
      ),
    );
    expect(find.text('A value is not valid.'), findsOneWidget);
    expect(find.text('Check what you entered and try again.'), findsOneWidget);
    expect(find.textContaining('field.invalid'), findsNothing);
    await tester.tapAndSettle(find.text('Fix it'));
    expect(fixed, 1);

    await tester.tapAndSettle(find.text('Details'));
    expect(
      find.text('invalid_argument field.invalid field=email'),
      findsOneWidget,
    );
    await tester.tapAndSettle(find.text('Copy details'));
    expect(copied, [
      [
        'A value is not valid.',
        'Check what you entered and try again.',
        'invalid_argument field.invalid field=email',
      ].join('\n'),
    ]);
  });
}
