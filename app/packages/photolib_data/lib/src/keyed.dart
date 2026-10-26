import 'package:drift/drift.dart';
import 'package:photolib_data/src/keys.dart';
import 'package:photolib_log/photolib_log.dart';

/// The statements that key a SQLite3MultipleCiphers connection with a 32-byte page key in ChaCha20-Poly1305 with one
/// PBKDF2 round, as the key is already uniform (ADR-0057). [pragma] `hexrekey` encrypts a plaintext database instead.
List<String> keyStatements(Uint8List key, {String pragma = 'hexkey'}) => [
  "PRAGMA cipher = 'chacha20'",
  'PRAGMA kdf_iter = 1',
  "PRAGMA $pragma = '${hex(key)}'",
];

/// Keys an executor opened with drift's migrations off by its first statements, then runs [after]. Nothing may read
/// the file before the key, so it reads the schema version and runs drift's migrations itself.
QueryInterceptor keying(Uint8List key, [List<String> after = const []]) =>
    _Keyed([...keyStatements(key), ...after]);

class _Keyed extends QueryInterceptor {
  _Keyed(this._statements);

  final List<String> _statements;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_KeyedUser(user, _statements));
}

class _KeyedUser implements QueryExecutorUser {
  _KeyedUser(this._user, this._statements);

  final QueryExecutorUser _user;
  final List<String> _statements;

  @override
  int get schemaVersion => _user.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails _) async {
    await executor.ensureOpen(this);
    for (final statement in _statements) {
      await executor.runCustom(statement);
    }
    final [row] = await executor.runSelect('PRAGMA user_version', const []);
    final from = (row.values.single as num).toInt();
    await _user.beforeOpen(
      executor,
      OpeningDetails(from == 0 ? null : from, schemaVersion),
    );
    if (from != schemaVersion) {
      await executor.runCustom('PRAGMA user_version = $schemaVersion');
    }
  }
}

const _database = Logger('photolib.database');

/// Logs every statement slower than [limit] (ADR-0115), never its values.
class SlowQueries extends QueryInterceptor {
  SlowQueries([this.limit = const Duration(milliseconds: 50)]);

  final Duration limit;

  Future<T> _timed<T>(String statement, Future<T> Function() run) async {
    final took = Stopwatch()..start();
    final result = await run();
    if (took.elapsed > limit) {
      _database.info(
        'slow query',
        fields: {
          'sql': statement,
          'ms': took.elapsedMilliseconds,
          if (result is List) 'rows': result.length,
        },
      );
    }
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(statement, () => executor.runSelect(statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(statement, () => executor.runInsert(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(statement, () => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(statement, () => executor.runDelete(statement, args));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(statement, () => executor.runCustom(statement, args));

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _timed(
    statements.statements.join('; '),
    () => executor.runBatched(statements),
  );
}
