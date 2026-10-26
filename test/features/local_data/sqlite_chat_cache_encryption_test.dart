import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wecord/features/chats/offline/sqlite_chat_cache.dart';
import 'package:wecord/features/local_data/aes_gcm_local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher.dart';

const _secret = '银行卡密码是 9527 / the wifi password is hunter2';

Map<String, dynamic> _row(
  String id,
  String chat, {
  String body = _secret,
  String? expiresAt,
  String at = '2026-10-01T08:00:00.000Z',
}) {
  return {
    'id': id,
    'conversation_id': chat,
    'sender_id': 'u2',
    'type': 'text',
    'body': body,
    'created_at': at,
    'expires_at': ?expiresAt,
  };
}

/// The database an earlier version wrote: version 1, JSON in the clear.
Future<void> _writeVersion1(String path) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          create table conversations (
            user_id text not null, position integer not null, id text not null,
            row_json text not null, primary key (user_id, id))
        ''');
        await db.execute('''
          create table messages (
            user_id text not null, conversation_id text not null,
            id text not null, created_at text not null,
            row_json text not null,
            primary key (user_id, conversation_id, id))
        ''');
        await db.execute('''
          create table outbox (
            user_id text not null, position integer not null,
            client_id text not null, entry_json text not null,
            primary key (user_id, client_id))
        ''');
      },
    ),
  );
  await db.insert('conversations', {
    'user_id': 'u1',
    'position': 0,
    'id': 'c1',
    'row_json': jsonEncode({'id': 'c1', 'title': 'Alice', 'last_message_body': _secret}),
  });
  for (final (id, expires) in [
    ('m1', null),
    ('m2', '2020-01-01T00:00:00.000Z'),
    ('m3', '2999-01-01T00:00:00.000Z'),
  ]) {
    await db.insert('messages', {
      'user_id': 'u1',
      'conversation_id': 'c1',
      'id': id,
      'created_at': '2026-10-01T08:00:0${id.substring(1)}.000Z',
      'row_json': jsonEncode(_row(id, 'c1', expiresAt: expires)),
    });
  }
  await db.insert('outbox', {
    'user_id': 'u1',
    'position': 0,
    'client_id': 'send-1',
    'entry_json': jsonEncode({'client_id': 'send-1', 'body': _secret}),
  });
  await db.insert('outbox', {
    'user_id': 'u1',
    'position': 1,
    'client_id': 'send-2',
    'entry_json': jsonEncode({'client_id': 'send-2', 'body': 'second'}),
  });
  await db.close();
}

Future<List<Map<String, Object?>>> _raw(String path, String table) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    return await db.query(table);
  } finally {
    await db.close();
  }
}

bool _fileHolds(String path, String text) {
  final bytes = File(path).readAsBytesSync();
  final needle = utf8.encode(text);
  outer:
  for (var at = 0; at <= bytes.length - needle.length; at++) {
    for (var index = 0; index < needle.length; index++) {
      if (bytes[at + index] != needle[index]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

void main() {
  late Directory directory;
  late String path;
  late LocalCipher cipher;

  setUp(() {
    sqfliteFfiInit();
    directory = Directory.systemTemp.createTempSync('wecord_cache_');
    path = '${directory.path}/chat_cache.sqlite';
    cipher = AesGcmLocalCipher(MemoryKeyStore());
  });

  tearDown(() => directory.deleteSync(recursive: true));

  group('SqliteChatCache encryption', () {
    test('keeps what it is given sealed in the file', () async {
      final cache = await SqliteChatCache.open(
        path,
        cipher: cipher,
        factory: databaseFactoryFfi,
      );
      await cache.writeConversations('u1', [
        {'id': 'c1', 'title': 'Alice', 'last_message_body': _secret},
      ]);
      await cache.writeMessages('u1', 'c1', [_row('m1', 'c1')]);
      await cache.writeOutbox('u1', [
        {'client_id': 'send-1', 'body': _secret},
      ]);

      expect((await cache.readMessages('u1', 'c1')).single['body'], _secret);
      expect((await cache.readConversations('u1'))!.single['title'], 'Alice');
      expect((await cache.readOutbox('u1')).single['body'], _secret);
      await cache.close();

      for (final (table, column) in [
        ('conversations', 'row_json'),
        ('messages', 'row_json'),
        ('outbox', 'entry_json'),
      ]) {
        final rows = await _raw(path, table);
        expect(rows.single[column], startsWith(sealedPrefix), reason: table);
        expect(rows.single[column], isNot(contains('hunter2')));
      }
      expect(_fileHolds(path, 'hunter2'), isFalse);
      expect(_fileHolds(path, '9527'), isFalse);
    });

    test('a cache opened with another key reads as empty', () async {
      final cache = await SqliteChatCache.open(
        path,
        cipher: cipher,
        factory: databaseFactoryFfi,
      );
      await cache.writeMessages('u1', 'c1', [_row('m1', 'c1')]);
      await cache.writeOutbox('u1', [
        {'client_id': 'x'},
      ]);
      await cache.close();

      final other = await SqliteChatCache.open(
        path,
        cipher: AesGcmLocalCipher(MemoryKeyStore()),
        factory: databaseFactoryFfi,
      );
      expect(await other.readMessages('u1', 'c1'), isEmpty);
      expect(await other.readOutbox('u1'), isEmpty);
      await other.close();
    });

    test('sweeps expired messages by the time kept beside the row', () async {
      final cache = await SqliteChatCache.open(
        path,
        cipher: cipher,
        factory: databaseFactoryFfi,
      );
      await cache.writeMessages('u1', 'c1', [
        _row('gone', 'c1', expiresAt: '2020-01-01T00:00:00.000Z'),
        _row('later', 'c1', expiresAt: '2999-01-01T00:00:00.000Z'),
        _row('plain', 'c1'),
      ]);

      final removed = await cache.removeExpired('u1', DateTime.utc(2026, 10, 27));

      expect([for (final row in removed) row['id']], ['gone']);
      expect(
        [for (final row in await cache.readMessages('u1', 'c1')) row['id']],
        unorderedEquals(['later', 'plain']),
      );
      await cache.close();
    });
  });

  group('SqliteChatCache from before the encryption', () {
    test('upgrades, reads the old rows and sweeps the old expired ones', () async {
      await _writeVersion1(path);
      final cache = await SqliteChatCache.open(
        path,
        cipher: cipher,
        factory: databaseFactoryFfi,
      );

      expect(await cache.legacyRowCount(), 6);
      expect(await cache.readMessages('u1', 'c1'), hasLength(3));
      expect((await cache.readOutbox('u1')).map((e) => e['client_id']), [
        'send-1',
        'send-2',
      ]);

      final removed = await cache.removeExpired('u1', DateTime.utc(2026, 10, 27));
      expect([for (final row in removed) row['id']], ['m2']);
      await cache.close();
    });

    test('moves everything over, the unsent messages included, and rebuilds the file', () async {
      await _writeVersion1(path);
      expect(_fileHolds(path, 'hunter2'), isTrue);
      final cache = await SqliteChatCache.open(
        path,
        cipher: cipher,
        factory: databaseFactoryFfi,
      );
      var pauses = 0;

      final moved = await cache.migrateLegacy(
        batchSize: 2,
        pause: () async => pauses++,
      );

      expect(moved, 6);
      expect(pauses, greaterThan(1), reason: 'in small batches');
      expect(await cache.legacyRowCount(), 0);
      // Nothing changed for the reader.
      expect(await cache.readMessages('u1', 'c1'), hasLength(3));
      final outbox = await cache.readOutbox('u1');
      expect(outbox.map((e) => e['client_id']), ['send-1', 'send-2']);
      expect(outbox.first['body'], _secret);
      expect((await cache.readConversations('u1'))!.single['title'], 'Alice');
      expect(await cache.migrateLegacy(), 0);
      await cache.close();

      for (final table in ['conversations', 'messages', 'outbox']) {
        for (final row in await _raw(path, table)) {
          expect(
            (row['row_json'] ?? row['entry_json'])! as String,
            startsWith(sealedPrefix),
          );
        }
      }
      final messages = await _raw(path, 'messages');
      expect(
        {for (final row in messages) row['id']: row['expires_at']},
        {
          'm1': null,
          'm2': '2020-01-01T00:00:00.000Z',
          'm3': '2999-01-01T00:00:00.000Z',
        },
      );
      expect(
        _fileHolds(path, 'hunter2'),
        isFalse,
        reason: 'the plain text is not left behind in the file',
      );
      expect(_fileHolds(path, '银行卡'), isFalse);
    });

    test('keeps rows it cannot encrypt, so nothing waiting to be sent is lost', () async {
      await _writeVersion1(path);
      final cache = await SqliteChatCache.open(
        path,
        cipher: const UnavailableLocalCipher(),
        factory: databaseFactoryFfi,
      );

      expect(await cache.migrateLegacy(), 0);

      expect(await cache.legacyRowCount(), 6);
      expect(await cache.readOutbox('u1'), hasLength(2));
      await cache.close();
    });

    test('a row written meanwhile is not overwritten by the old one', () async {
      await _writeVersion1(path);
      final cache = await SqliteChatCache.open(
        path,
        cipher: cipher,
        factory: databaseFactoryFfi,
      );
      // The chat page rewrites the conversation before the move-over gets to it.
      await cache.writeMessages('u1', 'c1', [_row('m1', 'c1', body: 'newer')]);

      await cache.migrateLegacy();

      expect(
        (await cache.readMessages('u1', 'c1')).map((row) => row['body']),
        ['newer'],
      );
      await cache.close();
    });
  });
}
