import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_data/local_cipher.dart';

/// The offline cache on iOS and macOS: a SQLite database in the app's
/// support directory, with one table per kind of row.
///
/// What was said is encrypted (G8): the JSON of every row is sealed with the
/// device key before it is written. The columns that place a row (user,
/// conversation, message id, time, when a disappearing message ends) stay
/// plain, so the cache can order, page and sweep without opening every row.
/// A database from before the encryption is read as it is and moved over
/// by [migrateLegacy].
class SqliteChatCache implements ChatCache {
  SqliteChatCache._(this._db, this._cipher);

  static const schemaVersion = 2;

  /// Opens (and creates or upgrades) the database at [path].
  static Future<SqliteChatCache> open(
    String path, {
    required LocalCipher cipher,
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          // Deleted text is written over, not left in free pages.
          await db.rawQuery('PRAGMA secure_delete = ON');
        },
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // The time a disappearing message ends, kept apart from the
            // (now encrypted) row.
            await db.execute('alter table messages add column expires_at text');
          }
        },
        // A newer layout of a cache: start it over.
        onDowngrade: (db, oldVersion, newVersion) async {
          await _dropSchema(db);
          await _createSchema(db);
        },
      ),
    );
    return SqliteChatCache._(db, cipher);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      create table if not exists conversations (
        user_id text not null,
        position integer not null,
        id text not null,
        row_json text not null,
        primary key (user_id, id)
      )
    ''');
    await db.execute('''
      create table if not exists messages (
        user_id text not null,
        conversation_id text not null,
        id text not null,
        created_at text not null,
        expires_at text,
        row_json text not null,
        primary key (user_id, conversation_id, id)
      )
    ''');
    await db.execute('''
      create index if not exists messages_conversation_created_idx
        on messages (user_id, conversation_id, created_at, id)
    ''');
    await db.execute('''
      create table if not exists outbox (
        user_id text not null,
        position integer not null,
        client_id text not null,
        entry_json text not null,
        primary key (user_id, client_id)
      )
    ''');
  }

  static Future<void> _dropSchema(DatabaseExecutor db) async {
    for (final table in ['conversations', 'messages', 'outbox']) {
      await db.execute('drop table if exists $table');
    }
  }

  final Database _db;
  final LocalCipher _cipher;

  /// A stored row, opened: sealed text is decrypted, plain JSON from before
  /// the encryption is read as it is. Null when it cannot be read (another
  /// key, damage), so the row is just missing from the cache.
  Future<Map<String, dynamic>?> _decode(Object? text) async {
    if (text is! String) {
      return null;
    }
    try {
      final json = (await _cipher.read(text)).text;
      if (json == null) {
        return null;
      }
      final decoded = jsonDecode(json);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object {
      return null;
    }
  }

  Future<String> _encode(Map<String, dynamic> row) =>
      _cipher.seal(jsonEncode(row));

  /// When a disappearing message ends, as UTC text that sorts, or null.
  static String? _expiresAt(Map<String, dynamic> row) {
    final value = row['expires_at'];
    if (value is! String) {
      return null;
    }
    final at = DateTime.tryParse(value);
    return at?.toUtc().toIso8601String();
  }


  @override
  Future<List<Map<String, dynamic>>?> readConversations(String userId) async {
    final rows = await _db.query(
      'conversations',
      columns: ['row_json'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'position',
    );
    if (rows.isEmpty) {
      return null;
    }
    return [for (final row in rows) ?await _decode(row['row_json'])];
  }

  @override
  Future<void> writeConversations(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    // Sealed before the transaction opens, which then only writes.
    final sealed = <(int, String, String)>[];
    for (final (index, row) in rows.indexed) {
      final id = row['id'];
      if (id is String) {
        sealed.add((index, id, await _encode(row)));
      }
    }
    await _db.transaction((txn) async {
      await txn.delete(
        'conversations',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final batch = txn.batch();
      for (final (index, id, json) in sealed) {
        batch.insert('conversations', {
          'user_id': userId,
          'position': index,
          'id': id,
          'row_json': json,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> readMessages(
    String userId,
    String conversationId,
  ) async {
    final rows = await _db.query(
      'messages',
      columns: ['row_json'],
      where: 'user_id = ? and conversation_id = ?',
      whereArgs: [userId, conversationId],
      orderBy: 'created_at, id',
    );
    return [for (final row in rows) ?await _decode(row['row_json'])];
  }

  @override
  Future<void> writeMessages(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) async {
    final kept = rows.length <= cachedMessagesPerConversation
        ? rows
        : rows.sublist(rows.length - cachedMessagesPerConversation);
    final sealed = <Map<String, Object?>>[];
    for (final row in kept) {
      final id = row['id'];
      final createdAt = row['created_at'];
      if (id is! String || createdAt is! String) {
        continue;
      }
      sealed.add({
        'user_id': userId,
        'conversation_id': conversationId,
        'id': id,
        // ISO 8601 in UTC sorts as text.
        'created_at': DateTime.parse(createdAt).toUtc().toIso8601String(),
        'expires_at': _expiresAt(row),
        'row_json': await _encode(row),
      });
    }
    await _db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'user_id = ? and conversation_id = ?',
        whereArgs: [userId, conversationId],
      );
      final batch = txn.batch();
      for (final values in sealed) {
        batch.insert(
          'messages',
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> readOutbox(String userId) async {
    final rows = await _db.query(
      'outbox',
      columns: ['entry_json'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'position',
    );
    return [for (final row in rows) ?await _decode(row['entry_json'])];
  }

  @override
  Future<void> writeOutbox(
    String userId,
    List<Map<String, dynamic>> entries,
  ) async {
    final sealed = <(int, String, String)>[];
    for (final (index, entry) in entries.indexed) {
      final clientId = entry['client_id'];
      if (clientId is String) {
        sealed.add((index, clientId, await _encode(entry)));
      }
    }
    await _db.transaction((txn) async {
      await txn.delete('outbox', where: 'user_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final (index, clientId, json) in sealed) {
        batch.insert('outbox', {
          'user_id': userId,
          'position': index,
          'client_id': clientId,
          'entry_json': json,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<ChatCacheSizes> measure(String userId) async {
    // Bytes of the stored text, as it sits in the file (sealed text is a
    // third bigger than what it holds).
    final messages = await _db.rawQuery(
      'select conversation_id, sum(length(cast(row_json as blob))) as bytes '
      'from messages where user_id = ? group by conversation_id',
      [userId],
    );
    final conversations = await _db.rawQuery(
      'select sum(length(cast(row_json as blob))) as bytes '
      'from conversations where user_id = ?',
      [userId],
    );
    final outbox = await _db.rawQuery(
      'select sum(length(cast(entry_json as blob))) as bytes '
      'from outbox where user_id = ?',
      [userId],
    );
    int bytes(List<Map<String, Object?>> rows) =>
        (rows.firstOrNull?['bytes'] as num?)?.toInt() ?? 0;
    return ChatCacheSizes(
      conversationList: bytes(conversations),
      outbox: bytes(outbox),
      messages: {
        for (final row in messages)
          if (row['conversation_id'] is String)
            row['conversation_id']! as String:
                (row['bytes'] as num?)?.toInt() ?? 0,
      },
    );
  }

  @override
  Future<void> removeMessages(
    String userId,
    String conversationId, {
    Set<String>? ids,
  }) {
    if (ids == null) {
      return _db.delete(
        'messages',
        where: 'user_id = ? and conversation_id = ?',
        whereArgs: [userId, conversationId],
      );
    }
    return _db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in ids) {
        batch.delete(
          'messages',
          where: 'user_id = ? and conversation_id = ? and id = ?',
          whereArgs: [userId, conversationId, id],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> clearMessages(String userId) {
    return _db.transaction((txn) async {
      for (final table in ['conversations', 'messages']) {
        await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      }
    });
  }

  @override
  Future<List<Map<String, dynamic>>> removeExpired(
    String userId,
    DateTime now,
  ) async {
    // The end time is kept beside the sealed row; a row from before the
    // encryption that has none yet is found by its text.
    final candidates = await _db.query(
      'messages',
      columns: ['conversation_id', 'id', 'row_json'],
      where:
          'user_id = ? and ((expires_at is not null and expires_at <= ?) or '
          "(expires_at is null and row_json like '{%' and row_json like ?))",
      whereArgs: [userId, now.toUtc().toIso8601String(), '%"expires_at":"%'],
    );
    final removed = <Map<String, dynamic>>[];
    final batch = _db.batch();
    for (final candidate in candidates) {
      final row = await _decode(candidate['row_json']);
      if (row == null || !cachedRowExpired(row, now)) {
        continue;
      }
      removed.add(row);
      batch.delete(
        'messages',
        where: 'user_id = ? and conversation_id = ? and id = ?',
        whereArgs: [userId, candidate['conversation_id'], candidate['id']],
      );
    }
    if (removed.isNotEmpty) {
      await batch.commit(noResult: true);
    }
    return removed;
  }

  @override
  Future<void> clear() {
    return _db.transaction((txn) async {
      for (final table in ['conversations', 'messages', 'outbox']) {
        await txn.delete(table);
      }
    });
  }

  /// Encrypts what an earlier version stored as plain JSON and returns how
  /// many rows that was. The unsent messages come first. A row that cannot
  /// be encrypted stays as it was (the next start tries again), so nothing
  /// that waits to be sent is ever dropped. When anything was moved the file
  /// is rebuilt, so the plain text is not left in it. [pause] gives the app
  /// a turn between batches.
  Future<int> migrateLegacy({
    Future<void> Function()? pause,
    bool Function()? shouldStop,
    int batchSize = 100,
  }) async {
    var migrated = 0;
    const tables = [
      ('outbox', 'entry_json', ['user_id', 'client_id']),
      ('conversations', 'row_json', ['user_id', 'id']),
      ('messages', 'row_json', ['user_id', 'conversation_id', 'id']),
    ];
    for (final (table, column, keys) in tables) {
      // Rows that could not be sealed this time are skipped, not retried in
      // a loop.
      final skipped = <String>{};
      while (!(shouldStop?.call() ?? false)) {
        final batch = await _db.query(
          table,
          columns: [...keys, column],
          where: "substr($column, 1, 1) = '{'",
          limit: batchSize + skipped.length,
        );
        final fresh = [
          for (final stored in batch)
            if (!skipped.contains(_identity(stored, keys))) stored,
        ].take(batchSize).toList();
        if (fresh.isEmpty) {
          break;
        }
        final updates = <(Map<String, Object?>, String?, String?)>[];
        for (final stored in fresh) {
          try {
            final row = await _decode(stored[column]);
            if (row == null) {
              // Not JSON that can be read: nothing worth keeping.
              updates.add((stored, null, null));
            } else {
              updates.add((
                stored,
                await _encode(row),
                table == 'messages' ? _expiresAt(row) : null,
              ));
            }
          } on Object {
            skipped.add(_identity(stored, keys));
          }
        }
        if (updates.isNotEmpty) {
          await _db.transaction((txn) async {
            for (final (stored, sealed, expiresAt) in updates) {
              final where =
                  "${[for (final key in keys) '$key = ?'].join(' and ')}"
                  " and substr($column, 1, 1) = '{'";
              final args = [for (final key in keys) stored[key]];
              if (sealed == null) {
                await txn.delete(table, where: where, whereArgs: args);
                continue;
              }
              // Only a row still plain: one written meanwhile is newer.
              final changed = await txn.update(
                table,
                {column: sealed, 'expires_at': ?expiresAt},
                where: where,
                whereArgs: args,
              );
              migrated += changed;
            }
          });
        }
        await pause?.call();
      }
    }
    if (migrated > 0) {
      try {
        // Rebuilds the file: no plain text is left in free pages.
        await _db.execute('VACUUM');
      } on Object {
        // Space is short or the file is busy; the text was written over as
        // it was replaced (secure_delete) anyway.
      }
    }
    return migrated;
  }

  static String _identity(Map<String, Object?> stored, List<String> keys) =>
      [for (final key in keys) '${stored[key]}'].join('\u0000');

  /// How many rows are still plain JSON.
  Future<int> legacyRowCount() async {
    var count = 0;
    for (final (table, column) in [
      ('outbox', 'entry_json'),
      ('conversations', 'row_json'),
      ('messages', 'row_json'),
    ]) {
      final rows = await _db.rawQuery(
        "select count(*) as n from $table where substr($column, 1, 1) = '{'",
      );
      count += (rows.first['n'] as num?)?.toInt() ?? 0;
    }
    return count;
  }

  Future<void> close() => _db.close();
}
