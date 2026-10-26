import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'an item is backed up once its backup state says so, as it changes',
    () async {
      final db = Replica(NativeDatabase.memory());
      addTearDown(db.close);
      final id = Uint8List(16)..[15] = 1;
      final seen = <bool>[];
      final heard = backedUp(db, id).listen(seen.add);
      await pumpEventQueue();
      for (final state in ['uploading', 'backed_up']) {
        await db
            .into(db.backupState)
            .insertOnConflictUpdate(
              BackupStateCompanion.insert(
                localAssetId: id,
                state: state,
                updatedAt: 0,
              ),
            );
        await pumpEventQueue();
      }
      await heard.cancel();
      expect(seen, [false, false, true]);
    },
  );
}
