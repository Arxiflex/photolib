// Backs the replica at args[0] up to the server at args[1], every folder
// chosen, signed in with the session args[2] if given, args[3] uploads at
// once (one by default), until a test kills it: up to ten runs a second apart,
// as the app schedules them, so that a run a loaded machine's stall stopped as
// offline is resumed by the next, as in the app.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/backup_native.dart';

Future<void> main(List<String> args) async {
  final db = Replica(
    NativeDatabase(
      File(args[0]),
      setup: (db) => db.execute('PRAGMA journal_mode = WAL'),
    ),
  );
  final server = Server(
    NetworkConfig(
      endpoints: [Uri.parse(args[1])],
      session: args.elementAtOrNull(2),
    ),
  );
  final folders = {for (final f in await backupFolders(db)) f.key: true};
  for (var n = 0; n < 10; n++) {
    final run = await BackupEngine(
      db,
      server,
      hash: hashFile,
      read: readMedia,
      parallel: int.parse(args.elementAtOrNull(3) ?? '1'),
    ).run(BackupSelection(folders: folders), const BackupConditions());
    stdout.writeln(run);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}
