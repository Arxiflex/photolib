// The stand-in photolibd of the sync budget, in a process of its own as a server is: building its batches costs the
// test's isolate group nothing. It prints its URL, then reads lines of `<library> <assets>`, each making that library
// Ann's in place of the one before (newLibrary), and answers each with a line.
import 'dart:convert';
import 'dart:io';

import 'package:photolib_api/testing.dart';

import 'sync_rows.dart';

Future<void> main() async {
  final server = await SyncServer.start();
  server.streams.addAll({
    for (final s in ['account', 'libraries', 'albums', 'tags', 'people']) s: [],
  });
  print(server.url);
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final [library, assets] = line.split(' ').map(int.parse).toList();
    newLibrary(library, assets)(server);
    print('ok');
  }
  await server.close();
}
