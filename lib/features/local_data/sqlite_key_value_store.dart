import 'package:sqflite/sqflite.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';

/// Strings by key in a SQLite file: where the search index lives on the
/// phone and the Mac. (Encrypting the values is [SealedKeyValueStore]'s
/// job.)
class SqliteKeyValueStore implements KeyValueStore {
  SqliteKeyValueStore._(this._db);

  static Future<SqliteKeyValueStore> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          // Deleted text is written over, not left in the file.
          await db.rawQuery('PRAGMA secure_delete = ON');
        },
        onCreate: (db, version) => db.execute(
          'create table if not exists kv (key text primary key, value text not null)',
        ),
      ),
    );
    return SqliteKeyValueStore._(db);
  }

  final Database _db;

  @override
  Future<String?> read(String key) async {
    final rows = await _db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    final value = rows.firstOrNull?['value'];
    return value is String ? value : null;
  }

  @override
  Future<void> write(String key, String value) {
    return _db.insert('kv', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String key) {
    return _db.delete('kv', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<List<String>> keys() async {
    final rows = await _db.query('kv', columns: ['key']);
    return [for (final row in rows) row['key']! as String];
  }

  @override
  Future<void> clear() => _db.delete('kv');

  Future<void> close() => _db.close();
}
