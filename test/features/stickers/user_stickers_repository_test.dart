import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/stickers/sticker_formats.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';

import 'sticker_fakes.dart';

const _owner = '00000000-0000-4000-8000-0000000000a1';
const _chat = '11111111-1111-4111-8111-111111111111';

class _DataSource implements UserStickersDataSource {
  final calls = <String>[];
  final rows = <Map<String, dynamic>>[];
  Object? insertError;
  Object? rpcError;
  Object? rpcResult = 'message-1';
  Object? noticeResult;
  Object? copyError;
  Map<String, dynamic>? lastRpcParams;
  Map<String, dynamic>? lastInsert;

  @override
  String get currentUserId => _owner;

  @override
  Future<List<Map<String, dynamic>>> selectAll() async {
    calls.add('selectAll');
    return rows;
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    calls.add('insert');
    lastInsert = row;
    final error = insertError;
    if (error != null) {
      throw error;
    }
    return {
      'id': 'row-1',
      'sort_key': -1,
      'created_at': '2026-10-22T10:00:00Z',
      ...row,
    };
  }

  @override
  Future<void> deleteRow(String id) async => calls.add('deleteRow:$id');

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add('rpc:$functionName');
    if (functionName == 'take_automod_notice') {
      return noticeResult;
    }
    lastRpcParams = params;
    final error = rpcError;
    if (error != null) {
      throw error;
    }
    return rpcResult;
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    calls.add('upload:$bucket/$path:$mimeType');
  }

  @override
  Future<void> remove({required String bucket, required String path}) async {
    calls.add('remove:$bucket/$path');
  }

  @override
  Future<void> copy({
    required String fromBucket,
    required String fromPath,
    required String toBucket,
    required String toPath,
  }) async {
    calls.add('copy:$fromBucket/$fromPath>$toBucket/$toPath');
    final error = copyError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) async => 'https://signed.test/$bucket/$path?h=${expiresIn.inHours}';

  @override
  Future<Uint8List> download({
    required String bucket,
    required String path,
  }) async {
    calls.add('download:$bucket/$path');
    return Uint8List.fromList([1, 2, 3]);
  }
}

PreparedSticker _prepared({bool animated = false}) => PreparedSticker(
  bytes: Uint8List.fromList([1, 2, 3]),
  format: animated ? StickerFormat.gif : StickerFormat.png,
  width: 200,
  height: 100,
  animated: animated,
);

void main() {
  late _DataSource source;
  late SupabaseUserStickersRepository repository;
  final sent = <String>[];

  setUp(() {
    source = _DataSource();
    sent.clear();
    var counter = 0;
    repository = SupabaseUserStickersRepository(
      source,
      onSent: (id) async => sent.add(id),
      newId: () => 'id${++counter}',
    );
  });

  group('the library', () {
    test('list reads the rows in order', () async {
      source.rows.add({
        'id': 's1',
        'owner_id': _owner,
        'path': '$_owner/a.gif',
        'width': 120,
        'height': 90,
        'animated': true,
        'sort_key': -5,
        'created_at': '2026-10-20T08:00:00Z',
      });
      final stickers = await repository.list();
      expect(stickers.single.id, 's1');
      expect(stickers.single.animated, isTrue);
      expect(stickers.single.mimeType, 'image/gif');
      expect(source.calls, ['selectAll']);
    });

    test('add uploads into the owner folder, then adds the row', () async {
      final sticker = await repository.add(_prepared());
      expect(source.calls, [
        'upload:user-stickers/$_owner/id1.png:image/png',
        'insert',
      ]);
      expect(source.lastInsert, {
        'owner_id': _owner,
        'path': '$_owner/id1.png',
        'width': 200,
        'height': 100,
        'animated': false,
      });
      expect(sticker.path, '$_owner/id1.png');
    });

    test('an animated sticker keeps its format', () async {
      await repository.add(_prepared(animated: true));
      expect(
        source.calls.first,
        'upload:user-stickers/$_owner/id1.gif:image/gif',
      );
      expect(source.lastInsert!['animated'], isTrue);
    });

    test('a refused row removes the image again', () async {
      source.insertError = const PostgrestException(
        message: 'You can keep at most 300 stickers',
        code: '54000',
      );
      await expectLater(
        repository.add(_prepared()),
        throwsA(isA<UserStickerException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(source.calls, contains('remove:user-stickers/$_owner/id1.png'));
    });

    test('the animated ceiling comes back as its own message', () async {
      source.insertError = const PostgrestException(
        message: 'Animated stickers can be at most 1 MB',
        code: '22023',
      );
      await expectLater(
        repository.add(_prepared(animated: true)),
        throwsA(
          isA<UserStickerException>().having(
            (e) => e.message,
            'message',
            contains('1 MB'),
          ),
        ),
      );
    });

    test('delete drops the row, then the image', () async {
      await repository.delete(userSticker('s1'));
      expect(source.calls, [
        'deleteRow:s1',
        'remove:user-stickers/user-1/s1.png',
      ]);
    });

    test('reorder sends the ids to the function', () async {
      await repository.reorder(['b', 'a']);
      expect(source.calls, ['rpc:reorder_user_stickers']);
      expect(source.lastRpcParams, {
        'sticker_ids': ['b', 'a'],
      });
    });

    test('urls are signed for a day and files downloaded', () async {
      expect(
        await repository.createUrl(
          const StickerFile('user-stickers', 'a/b.png'),
        ),
        'https://signed.test/user-stickers/a/b.png?h=24',
      );
      await repository.download(const StickerFile('chat-images', 'c/d.png'));
      expect(source.calls, ['download:chat-images/c/d.png']);
    });
  });

  group('sending', () {
    final sticker = userSticker('s1', animated: true);

    test('copies the file into the chat folder, then sends the copy', () async {
      await repository.send(conversationId: _chat, sticker: sticker);
      expect(source.calls, [
        'copy:user-stickers/user-1/s1.gif>chat-images/$_chat/sticker-id1.gif',
        'rpc:send_personal_sticker',
      ]);
      expect(source.lastRpcParams, {
        'target_conversation_id': _chat,
        'target_sticker_id': 's1',
        'chat_path': '$_chat/sticker-id1.gif',
      });
      await Future<void>.delayed(Duration.zero);
      expect(sent, ['message-1']);
    });

    test('every send makes a copy of its own', () async {
      await repository.send(conversationId: _chat, sticker: sticker);
      await repository.send(conversationId: _chat, sticker: sticker);
      final copies = source.calls.where((call) => call.startsWith('copy:'));
      expect(copies.toSet().length, 2);
    });

    test('a copy that cannot be made sends nothing', () async {
      source.copyError = const StorageException('forbidden');
      await expectLater(
        repository.send(conversationId: _chat, sticker: sticker),
        throwsA(isA<StorageException>()),
      );
      expect(source.calls.where((c) => c.startsWith('rpc:')), isEmpty);
    });

    test('slowmode comes back as slowmode', () async {
      source.rpcError = const PostgrestException(
        message: 'Slowmode is on',
        code: 'P0001',
        details: 'slowmode_remaining_seconds=12',
      );
      await expectLater(
        repository.send(conversationId: _chat, sticker: sticker),
        throwsA(
          isA<SlowmodeException>().having(
            (e) => e.remainingSeconds,
            'seconds',
            12,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        source.calls,
        contains('remove:chat-images/$_chat/sticker-id1.gif'),
      );
    });

    test('a quiet AutoMod refusal reads its note', () async {
      source.rpcResult = null;
      source.noticeResult = {'reason': 'Links are not allowed'};
      await expectLater(
        repository.send(conversationId: _chat, sticker: sticker),
        throwsA(isA<AutoModBlockedException>()),
      );
      expect(sent, isEmpty);
      expect(source.calls, contains('rpc:take_automod_notice'));
    });

    test('other server errors pass through', () async {
      source.rpcError = const PostgrestException(
        message: 'Sticker not found',
        code: '42501',
      );
      await expectLater(
        repository.send(conversationId: _chat, sticker: sticker),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  test('the uninitialized repository is empty and refuses to write', () async {
    const repository = UninitializedUserStickersRepository();
    expect(await repository.list(), isEmpty);
    expect(
      () => repository.send(conversationId: _chat, sticker: userSticker('x')),
      throwsStateError,
    );
  });
}
