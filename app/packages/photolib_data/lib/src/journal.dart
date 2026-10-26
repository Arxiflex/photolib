import 'package:photolib_data/src/replica.dart';

/// Merges what an extension appended to its [journal] since the last merge. Extensions never open the replica
/// (app/tool/single_writer_lint.dart): they append one entry per line to a journal file that only grows, whose
/// [contents] the data isolate hands here. Each new complete line goes to [apply] in the transaction that advances the
/// journal's cursor, so no entry is applied twice or skipped, whatever fails. Returns how many were applied.
Future<int> mergeJournal(
  Replica db,
  String journal,
  String contents,
  Future<void> Function(String entry) apply,
) => db.transaction(() async {
  final entries = contents.split('\n')..removeLast();
  final cursor = await (db.select(
    db.extJournalCursor,
  )..where((c) => c.journal.equals(journal))).getSingleOrNull();
  final merged = cursor?.merged ?? 0;
  if (entries.length <= merged) return 0;
  for (final entry in entries.skip(merged)) {
    await apply(entry);
  }
  await db
      .into(db.extJournalCursor)
      .insertOnConflictUpdate(
        ExtJournalCursorCompanion.insert(
          journal: journal,
          merged: entries.length,
        ),
      );
  return entries.length - merged;
});
