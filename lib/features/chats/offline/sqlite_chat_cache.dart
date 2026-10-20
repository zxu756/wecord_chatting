import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';

/// The offline cache on iOS and macOS: a SQLite database in the app's
/// support directory, with one table per kind of row.
class SqliteChatCache implements ChatCache {
  SqliteChatCache._(this._db);

  static const schemaVersion = 1;

  /// Opens (and creates or upgrades) the database at [path].
  static Future<SqliteChatCache> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _createSchema(db),
        // A newer layout of a cache: start it over.
        onDowngrade: (db, oldVersion, newVersion) async {
          await _dropSchema(db);
          await _createSchema(db);
        },
      ),
    );
    return SqliteChatCache._(db);
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

  static Map<String, dynamic>? _decode(Object? text) {
    if (text is! String) {
      return null;
    }
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
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
    return [for (final row in rows) ?_decode(row['row_json'])];
  }

  @override
  Future<void> writeConversations(
    String userId,
    List<Map<String, dynamic>> rows,
  ) {
    return _db.transaction((txn) async {
      await txn.delete(
        'conversations',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final batch = txn.batch();
      for (final (index, row) in rows.indexed) {
        final id = row['id'];
        if (id is! String) {
          continue;
        }
        batch.insert('conversations', {
          'user_id': userId,
          'position': index,
          'id': id,
          'row_json': jsonEncode(row),
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
    return [for (final row in rows) ?_decode(row['row_json'])];
  }

  @override
  Future<void> writeMessages(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) {
    final kept = rows.length <= cachedMessagesPerConversation
        ? rows
        : rows.sublist(rows.length - cachedMessagesPerConversation);
    return _db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'user_id = ? and conversation_id = ?',
        whereArgs: [userId, conversationId],
      );
      final batch = txn.batch();
      for (final row in kept) {
        final id = row['id'];
        final createdAt = row['created_at'];
        if (id is! String || createdAt is! String) {
          continue;
        }
        batch.insert('messages', {
          'user_id': userId,
          'conversation_id': conversationId,
          'id': id,
          // ISO 8601 in UTC sorts as text.
          'created_at': DateTime.parse(createdAt).toUtc().toIso8601String(),
          'row_json': jsonEncode(row),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    return [for (final row in rows) ?_decode(row['entry_json'])];
  }

  @override
  Future<void> writeOutbox(String userId, List<Map<String, dynamic>> entries) {
    return _db.transaction((txn) async {
      await txn.delete('outbox', where: 'user_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final (index, entry) in entries.indexed) {
        final clientId = entry['client_id'];
        if (clientId is! String) {
          continue;
        }
        batch.insert('outbox', {
          'user_id': userId,
          'position': index,
          'client_id': clientId,
          'entry_json': jsonEncode(entry),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<ChatCacheSizes> measure(String userId) async {
    // Bytes of the stored JSON (`length` of text counts characters).
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
    // Only rows that carry a time to expire at are worth decoding.
    final candidates = await _db.query(
      'messages',
      columns: ['conversation_id', 'id', 'row_json'],
      where: 'user_id = ? and row_json like ?',
      whereArgs: [userId, '%"expires_at":"%'],
    );
    final removed = <Map<String, dynamic>>[];
    final batch = _db.batch();
    for (final candidate in candidates) {
      final row = _decode(candidate['row_json']);
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

  Future<void> close() => _db.close();
}
