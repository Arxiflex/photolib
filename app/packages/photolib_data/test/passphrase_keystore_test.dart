@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

import 'kernel.dart';

void main() {
  final kernel = testKernel();
  late Directory dir;
  late String store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-passphrase-');
    store = '${dir.path}/store';
  });
  tearDown(() => dir.delete(recursive: true));

  /// What the user types, in turn, and what each prompt asked.
  final typed = <String>[];
  final asked = <({bool create, bool retry})>[];
  setUp(() {
    typed.clear();
    asked.clear();
  });
  Vault open() => Vault(
    location: store,
    keystore: PassphraseKeystore(storeFiles(store), kernel.keyring, ({
      required create,
      required retry,
    }) async {
      asked.add((create: create, retry: retry));
      return typed.removeAt(0);
    }),
    files: storeFiles(store),
    keyring: kernel.keyring,
  );

  test('the store opens again with the passphrase chosen, asking again '
      'after a wrong one', () async {
    typed.add('correct horse battery');
    var vault = open();
    await vault.unlock();
    await vault.write('note', utf8.encode('kept'));
    await vault.write('locked', utf8.encode('class B'), keyClass: KeyClass.b);
    await vault.lock();
    expect(asked, [(create: true, retry: false)]);

    asked.clear();
    typed.addAll(['correct horse', 'correct horse battery']);
    vault = open();
    await vault.unlock();
    expect(utf8.decode((await vault.read('note'))!), 'kept');
    expect(
      utf8.decode((await vault.read('locked', keyClass: KeyClass.b))!),
      'class B',
    );
    await vault.lock();
    expect(asked, [
      (create: false, retry: false),
      (create: false, retry: true),
    ]);
  });

  test('its file holds neither the passphrase nor a key', () async {
    final files = storeFiles(store);
    final keystore = PassphraseKeystore(
      files,
      kernel.keyring,
      ({required create, required retry}) async => 'correct horse battery',
    );
    final key = Uint8List.fromList(await keystore.create('dev'));
    final file = (await files.read('keystore'))!;

    bool holds(List<int> bytes) =>
        String.fromCharCodes(file).contains(String.fromCharCodes(bytes));
    expect(holds(utf8.encode('correct horse battery')), isFalse);
    expect(holds(key), isFalse);
    expect(holds(base64.encode(key).codeUnits), isFalse);
    // The vault zeroes what it imports: each read is a copy.
    (await keystore.read('dev'))!.fillRange(0, 32, 0);
    expect(await keystore.read('dev'), key);
  });

  test('erasing the store deletes its keys', () async {
    typed.add('correct horse battery');
    final vault = open();
    await vault.unlock();
    await vault.erase();
    expect(await storeFiles(store).read('keystore'), isNull);
    expect(File('$store/keystore').existsSync(), isFalse);
  });
}
