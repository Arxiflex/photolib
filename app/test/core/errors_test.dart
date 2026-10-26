import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/errors.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/l10n/app_localizations.dart';

Widget app(Widget home) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

class Boom extends StatelessWidget {
  const Boom({super.key});

  @override
  Widget build(BuildContext context) => throw StateError('broken build');
}

void main() {
  final logged = <LogRecord>[];

  void Function() install() {
    final onError = FlutterError.onError;
    final platformOnError = PlatformDispatcher.instance.onError;
    final builder = ErrorWidget.builder;
    void restore() {
      FlutterError.onError = onError;
      PlatformDispatcher.instance.onError = platformOnError;
      ErrorWidget.builder = builder;
      logged.clear();
    }

    addTearDown(restore);
    installErrorHandlers(Logger('test', sink: logged.add));
    return restore;
  }

  test('a framework error is logged as an error', () {
    install();
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('x'),
        stack: StackTrace.fromString('#0 here'),
        library: 'photos',
      ),
    );
    expect(logged.single.level, LogLevel.error);
    expect(logged.single.error, isA<StateError>());
    expect(logged.single.stackTrace.toString(), '#0 here');
    expect(logged.single.fields['library'], 'photos');
  });

  test('an uncaught async error is logged and counted as handled', () {
    install();
    final handled = PlatformDispatcher.instance.onError!(
      StateError('late'),
      StackTrace.empty,
    );
    expect(handled, isTrue);
    expect(logged.single.level, LogLevel.error);
    expect(logged.single.error, isA<StateError>());
  });

  testWidgets('a widget that fails to build shows the error view', (
    tester,
  ) async {
    final restore = install();
    await tester.pumpWidget(app(const Boom()));
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(logged.map((r) => r.level), contains(LogLevel.error));
    restore();
  });

  testWidgets('the error view still shows without localizations', (
    tester,
  ) async {
    final restore = install();
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: Boom()),
    );
    expect(find.text('Something went wrong'), findsOneWidget);
    restore();
  });

  group('ErrorView', () {
    testWidgets('offers a retry only when it is given one', (tester) async {
      await tester.pumpWidget(app(const ErrorView()));
      expect(find.text('Try again'), findsNothing);

      var retried = 0;
      await tester.pumpWidget(app(ErrorView(onRetry: () => retried++)));
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('can show a specific message', (tester) async {
      await tester.pumpWidget(app(const ErrorView(message: 'Not here')));
      expect(find.text('Not here'), findsOneWidget);
    });

    testWidgets('keeps a long message off the edges', (tester) async {
      await tester.pumpWidget(app(ErrorView(message: 'word ' * 100)));
      final text = tester.getRect(find.byType(Text).first);
      final screen = tester.getRect(find.byType(ErrorView));
      expect(text.left - screen.left, greaterThanOrEqualTo(16));
      expect(screen.right - text.right, greaterThanOrEqualTo(16));
    });
  });
}
