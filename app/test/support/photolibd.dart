import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:photolib_harness/testing.dart';

/// photolibd as an operator runs it, on a throwaway PostgreSQL cluster, as the
/// server's own tests start them (`photolib_db::testpg`, tests/photolibd.rs):
/// built from this checkout with cargo, its API on a loopback port, and the
/// one-time setup token it logs.
class Photolibd {
  Photolibd._(this._dir, this._pg, this._process, this.url, this.setupToken);

  final Directory _dir;
  final String _pg;
  final Process _process;
  final Uri url;
  final String setupToken;

  /// Builds photolibd with cargo and returns the binary; call it in `main`
  /// ([untimed]).
  static String build() {
    untimed('cargo build');
    final build = Process.runSync(
      'cargo',
      [
        'build',
        '--locked',
        '-p',
        'photolib-server',
        '--bin',
        'photolibd',
        '--message-format=json',
      ],
      workingDirectory: Directory.current.uri
          .resolve('../server/')
          .toFilePath(),
    );
    if (build.exitCode != 0) throw StateError('cargo: ${build.stderr}');
    return [
      for (final line in LineSplitter.split(build.stdout as String))
        if (jsonDecode(line) case {
          'reason': 'compiler-artifact',
          'executable': final String executable,
        })
          executable,
    ].single;
  }

  /// Starts [binary], from [build]; with [workers], those of photos too, and
  /// external libraries under [externalRoot].
  static Future<Photolibd> start(
    String binary, {
    bool workers = false,
    String? externalRoot,
  }) async {
    final pg = _postgresBin();
    final dir = await Directory.systemTemp.createTemp('photolib-pg-');
    Future<void> run(String program, List<String> arguments) async {
      final result = await Process.run('$pg/$program', arguments);
      if (result.exitCode != 0) throw StateError('$program: ${result.stderr}');
    }

    await run('initdb', [
      ...['-U', 'postgres', '-A', 'trust', '-E', 'UTF8', '--no-sync'],
      ...['--locale=C', '-D', '${dir.path}/data'],
    ]);
    await run('pg_ctl', [
      ...['-w', '-D', '${dir.path}/data', '-l', '${dir.path}/log'],
      ...['-o', "-c listen_addresses='' -k ${dir.path} -c fsync=off", 'start'],
    ]);
    final config = File('${dir.path}/photolib.yaml')
      ..writeAsStringSync(
        'config_version: 1\nlisten: 127.0.0.1:0\n'
        'roles: [api${workers ? ', scheduler, worker:cpu, worker:io' : ''}]\n'
        '${externalRoot == null ? '' : 'external_roots: [$externalRoot]\n'}'
        'data_dir: ${dir.path}/photolibd\ndatabase:\n'
        '  url: "postgres://postgres@localhost/postgres?host=${dir.path}"\n',
      );
    Directory('${dir.path}/photolibd').createSync();
    final process = await Process.start(
      binary,
      ['--config', config.path],
      environment: {},
      includeParentEnvironment: false,
    );
    final lines = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    String? token;
    await for (final line in lines.timeout(const Duration(minutes: 1))) {
      final fields = (jsonDecode(line) as Map)['fields'] as Map;
      token ??= fields['setup_token'] as String?;
      if (fields['message'] == 'listening') {
        lines.listen(null);
        return Photolibd._(
          dir,
          pg,
          process,
          Uri.parse('http://${fields['addr']}/'),
          token!,
        );
      }
    }
    throw StateError('photolibd did not start');
  }

  /// What psql prints for [query], one row a line, unaligned.
  Future<String> sql(String query) async {
    final result = await Process.run('$_pg/psql', [
      ...['-h', _dir.path, '-U', 'postgres', '-d', 'postgres', '-At'],
      ...['-c', query],
    ]);
    if (result.exitCode != 0) throw StateError('psql: ${result.stderr}');
    return (result.stdout as String).trim();
  }

  Future<void> stop() async {
    _process.kill();
    await _process.exitCode;
    await Process.run('$_pg/pg_ctl', [
      ...['-D', '${_dir.path}/data', '-m', 'immediate', 'stop'],
    ]);
    await _dir.delete(recursive: true);
  }
}

/// `TEST_PG_BIN`, else the directory with `pg_ctl` on `PATH`, else the newest
/// `/usr/lib/postgresql/<major>/bin`, as `photolib_db::testpg::bin_dir`.
String _postgresBin() {
  if (Platform.environment['TEST_PG_BIN'] case final dir?) return dir;
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (File('$dir/pg_ctl').existsSync()) return dir;
  }
  final majors = [
    for (final entry in Directory('/usr/lib/postgresql').listSync())
      ?int.tryParse(entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty)),
  ]..sort();
  return '/usr/lib/postgresql/${majors.last}/bin';
}
