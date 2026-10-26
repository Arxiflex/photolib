import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/main.dart' as app;

void main() {
  testWidgets('main starts the app with the error handlers installed', (
    tester,
  ) async {
    final onError = FlutterError.onError;
    final platformOnError = PlatformDispatcher.instance.onError;
    final builder = ErrorWidget.builder;
    void restore() {
      FlutterError.onError = onError;
      PlatformDispatcher.instance.onError = platformOnError;
      ErrorWidget.builder = builder;
    }

    addTearDown(restore);
    final heard = <LogRecord>[];
    addTearDown(Log.records.listen(heard.add).cancel);

    unawaited(app.main());
    // A widget test opens no vault: the app starts once it gives up waiting
    // for the settings.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsWidgets);
    expect(FlutterError.onError, isNot(same(onError)));
    expect(PlatformDispatcher.instance.onError, isNotNull);
    restore();

    final start = heard.firstWhere((r) => r.message == 'starting');
    expect(start.logger, 'photolib.app');
    expect(start.fields, containsPair('build', 'debug'));
    expect(start.fields, containsPair('app', '0.1.0+1'));
    expect(start.fields['os'], isNotNull);
    expect(
      heard
          .where((r) => r.logger == 'photolib.navigation')
          .map((r) => r.fields['route']),
      contains('/library'),
    );
    expect(
      heard.where((r) => r.logger == 'photolib.state').map((r) => r.message),
      contains('provider added'),
    );

    final roboto = await tester.runAsync(
      () => LicenseRegistry.licenses
          .where((entry) => entry.packages.contains('Roboto'))
          .toList(),
    );
    expect(roboto!.single.paragraphs.first.text, contains('Apache License'));
  });
}
