import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A private CA with a server certificate for localhost, one that expired, and a client certificate (PKCS#12), a client
/// certificate from another CA, and two self-signed server certificates; made with openssl for one test run, so no key
/// is ever committed.
class Pki {
  Pki._(this._dir);
  final Directory _dir;

  static const password = 'photolib';

  static Future<Pki> create() async {
    final pki = Pki._(await Directory.systemTemp.createTemp('photolib-pki-'));
    const key = '-newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2';
    const host = 'subjectAltName=DNS:localhost,IP:127.0.0.1';
    Future<void> signed(
      String name,
      String ca,
      String usage, {
      String validity = '-days 2',
    }) async {
      File('${pki._dir.path}/$name.ext').writeAsStringSync(usage);
      await pki._openssl(
        'req $key -keyout $name.key -out $name.csr -subj /CN=$name',
      );
      await pki._openssl(
        'x509 -req -in $name.csr -CA $ca.pem -CAkey $ca.key -CAcreateserial $validity -out $name.pem -extfile $name.ext',
      );
    }

    for (final ca in ['ca', 'other-ca']) {
      await pki._openssl(
        'req -x509 $key -keyout $ca.key -out $ca.pem -subj /CN=$ca',
      );
    }
    await signed('server', 'ca', '$host\nextendedKeyUsage=serverAuth');
    // Valid for a day that ended yesterday: expired. OpenSSL 3.5 refuses
    // -days -1, which LibreSSL and OpenSSL before 3.4 (no -not_before) take.
    final help = await Process.run('openssl', ['x509', '-help']);
    final start = DateTime.now().toUtc().subtract(const Duration(days: 2));
    String stamp(DateTime t) =>
        t.toIso8601String().replaceAll(RegExp(r'[-:T]|\.\d+'), '');
    await signed(
      'expired',
      'ca',
      '$host\nextendedKeyUsage=serverAuth',
      validity: '${help.stdout}${help.stderr}'.contains('-not_before')
          ? '-not_before ${stamp(start)} '
                '-not_after ${stamp(start.add(const Duration(days: 1)))}'
          : '-days -1',
    );
    await signed('client', 'ca', 'extendedKeyUsage=clientAuth');
    await signed('stranger', 'other-ca', 'extendedKeyUsage=clientAuth');
    for (final name in ['client', 'stranger']) {
      await pki._openssl(
        'pkcs12 -export -inkey $name.key -in $name.pem -out $name.p12 -passout pass:$password',
      );
    }
    for (final name in ['self-signed', 'self-signed-2']) {
      await pki._openssl(
        'req -x509 $key -keyout $name.key -out $name.pem -subj /CN=localhost -addext $host',
      );
    }
    return pki;
  }

  Future<void> _openssl(String command) async {
    final run = await Process.run(
      'openssl',
      command.split(' '),
      workingDirectory: _dir.path,
    );
    if (run.exitCode != 0) throw StateError('openssl $command:\n${run.stderr}');
  }

  /// The bytes of a file: `ca.pem`, `client.p12`, `server.key`…
  List<int> operator [](String file) =>
      File('${_dir.path}/$file').readAsBytesSync();

  /// The SHA-256 of the DER of certificate `name`, as the user confirms it on first use.
  String fingerprint(String name) {
    final pem = utf8
        .decode(this['$name.pem'])
        .split('\n')
        .where((line) => !line.startsWith('-----'))
        .join();
    return sha256.convert(base64.decode(pem)).toString();
  }

  /// A server context for the certificate `name`, trusting client certificates signed by `ca`.
  SecurityContext serverContext(String name, {String? ca}) {
    final context = SecurityContext()
      ..useCertificateChainBytes(this['$name.pem'])
      ..usePrivateKeyBytes(this['$name.key']);
    if (ca != null) context.setTrustedCertificatesBytes(this['$ca.pem']);
    return context;
  }

  void delete() => _dir.deleteSync(recursive: true);
}
