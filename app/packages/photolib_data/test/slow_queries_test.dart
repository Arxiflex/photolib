@TestOn('vm')
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/keyed.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:test/test.dart';

void main() {
  test(
    'statements slower than the limit are logged without their values',
    () async {
      final heard = <LogRecord>[];
      addTearDown(Log.records.listen(heard.add).cancel);
      Future<void> select(Duration limit) async {
        final db = Replica(
          NativeDatabase.memory().interceptWith(SlowQueries(limit)),
        );
        await db
            .customSelect('SELECT ? AS n', variables: [Variable('secret')])
            .get();
        await db.close();
      }

      await select(const Duration(hours: 1));
      expect(heard.where((r) => r.message == 'slow query'), isEmpty);
      await select(Duration.zero);
      final slow = heard.lastWhere((r) => r.fields['sql'] == 'SELECT ? AS n');
      expect(slow.logger, 'photolib.database');
      expect(slow.message, 'slow query');
      expect(slow.fields['rows'], 1);
      expect(slow.toJson(), isNot(contains('secret')));
    },
  );
}
