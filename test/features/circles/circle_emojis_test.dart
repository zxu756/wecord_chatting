import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circle_emojis_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/circle_role.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import '../chats/emoji_fixtures.dart';
import 'circle_detail_screen_test.dart' as circle_fakes;

const partyParrotId = '00000000-0000-4000-8000-000000000001';
const blobWaveId = '00000000-0000-4000-8000-000000000002';
const catThumbsId = '00000000-0000-4000-8000-000000000003';
const waveStickerId = '00000000-0000-4000-8000-000000000004';
const shipItStickerId = '00000000-0000-4000-8000-000000000005';

CircleEmoji testEmoji(
  String id,
  String name, {
  String circleId = 'circle-1',
  String circleName = 'Book Club',
  CircleEmojiKind kind = CircleEmojiKind.emoji,
}) {
  return CircleEmoji(
    id: id,
    circleId: circleId,
    circleName: circleName,
    name: name,
    kind: kind,
    storagePath: '$circleId/$id.png',
    mimeType: 'image/png',
    createdBy: 'user-1',
    creatorName: 'Ada',
    createdAt: DateTime.utc(2026, 10, 14),
  );
}

/// Emoji and stickers of circle-1 (the current circle in tests) and of a
/// second circle.
List<CircleEmoji> testEmojis() {
  return [
    testEmoji(partyParrotId, 'party_parrot'),
    testEmoji(blobWaveId, 'blob_wave'),
    testEmoji(waveStickerId, 'wave', kind: CircleEmojiKind.sticker),
    testEmoji(
      catThumbsId,
      'cat_thumbs',
      circleId: 'circle-2',
      circleName: 'Hiking',
    ),
    testEmoji(
      shipItStickerId,
      'ship_it',
      circleId: 'circle-2',
      circleName: 'Hiking',
      kind: CircleEmojiKind.sticker,
    ),
  ];
}

/// The test images, by emoji id.
final testEmojiImages = <String, Uint8List>{
  partyParrotId: partyParrotPng,
  blobWaveId: blobWavePng,
  catThumbsId: catThumbsPng,
  waveStickerId: waveStickerPng,
  shipItStickerId: shipItStickerPng,
};

/// Serves [testEmojiImages] for storage paths ending in their id.
Override testEmojiImageOverride() {
  return circleEmojiImageProvider.overrideWith((ref, storagePath) async {
    for (final MapEntry(:key, :value) in testEmojiImages.entries) {
      if (storagePath.contains(key)) {
        return MemoryImage(value);
      }
    }
    return null;
  });
}

class FakeCircleEmojiRepository implements CircleEmojiRepository {
  FakeCircleEmojiRepository([List<CircleEmoji>? emojis])
    : emojis = emojis ?? testEmojis();

  List<CircleEmoji> emojis;
  final added = <({String circleId, String name, CircleEmojiKind kind})>[];
  final renamed = <(String, String)>[];
  final deleted = <String>[];
  Object? addError;

  /// Emits a change another client made; see [emojiChanges].
  final changes = StreamController<void>.broadcast();

  /// The circle of every [emojiChanges] call; null for every circle.
  final watched = <String?>[];

  @override
  Future<List<CircleEmoji>> listCircleEmojis(String circleId) async {
    return [
      for (final emoji in emojis)
        if (emoji.circleId == circleId) emoji,
    ];
  }

  @override
  Future<List<CircleEmoji>> listUsableEmojis() async => emojis;

  @override
  Future<CircleEmoji> addCircleEmoji({
    required String circleId,
    required String name,
    required CircleEmojiKind kind,
    required Uint8List bytes,
  }) async {
    if (addError case final error?) {
      throw error;
    }
    added.add((circleId: circleId, name: name, kind: kind));
    final emoji = testEmoji(
      '00000000-0000-4000-8000-0000000001${added.length.toString().padLeft(2, '0')}',
      name,
      circleId: circleId,
      kind: kind,
    );
    emojis = [...emojis, emoji];
    return emoji;
  }

  @override
  Future<CircleEmoji> renameCircleEmoji({
    required String emojiId,
    required String name,
  }) async {
    renamed.add((emojiId, name));
    final emoji = emojis.firstWhere((emoji) => emoji.id == emojiId);
    final next = emoji.copyWith(name: name);
    emojis = [for (final other in emojis) other.id == emojiId ? next : other];
    return next;
  }

  @override
  Future<void> deleteCircleEmoji(String emojiId) async {
    deleted.add(emojiId);
    emojis = [
      for (final emoji in emojis)
        if (emoji.id != emojiId) emoji,
    ];
  }

  @override
  Future<String> createEmojiUrl(String storagePath) async {
    return 'https://emoji.test/$storagePath';
  }

  @override
  Stream<void> emojiChanges({String? circleId}) {
    watched.add(circleId);
    return changes.stream;
  }
}

class _FakeEmojiDataSource implements CircleEmojiDataSource {
  final rpcCalls = <(String, Map<String, dynamic>)>[];
  final uploads = <({String bucket, String path, String mimeType})>[];
  final removed = <String>[];
  final watched = <String?>[];
  Object? rpcError;
  Object? rpcResult;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    rpcCalls.add((functionName, params));
    if (rpcError case final error?) {
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
    uploads.add((bucket: bucket, path: path, mimeType: mimeType));
  }

  @override
  Future<void> remove({required String bucket, required String path}) async {
    removed.add('$bucket/$path');
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) async {
    return 'https://signed.test/$bucket/$path?ttl=${expiresIn.inHours}h';
  }

  @override
  Stream<void> emojiChanges({String? circleId}) {
    watched.add(circleId);
    return const Stream.empty();
  }
}

Map<String, dynamic> _emojiJson({
  String id = partyParrotId,
  String name = 'party_parrot',
  String kind = 'emoji',
}) {
  return {
    'id': id,
    'circle_id': 'circle-1',
    'circle_name': 'Book Club',
    'name': name,
    'kind': kind,
    'storage_path': 'circle-1/$id.png',
    'mime_type': 'image/png',
    'created_by': 'user-1',
    'creator_name': 'Ada',
    'created_at': '2026-10-14T09:00:00Z',
  };
}

void main() {
  group('repository', () {
    test('uploads to the circle folder, then registers the emoji', () async {
      final source = _FakeEmojiDataSource()..rpcResult = _emojiJson();
      final repository = SupabaseCircleEmojiRepository(
        source,
        newId: () => 'aaaaaaaa-0000-4000-8000-000000000001',
      );

      final emoji = await repository.addCircleEmoji(
        circleId: 'circle-1',
        name: 'party_parrot',
        kind: CircleEmojiKind.emoji,
        bytes: partyParrotPng,
      );

      expect(emoji.name, 'party_parrot');
      expect(emoji.token, '<:party_parrot:$partyParrotId>');
      expect(emoji.reactionValue, 'custom:$partyParrotId');
      expect(source.uploads.single.bucket, 'circle-emojis');
      expect(
        source.uploads.single.path,
        'circle-1/aaaaaaaa-0000-4000-8000-000000000001.png',
      );
      expect(source.uploads.single.mimeType, 'image/png');
      final (name, params) = source.rpcCalls.single;
      expect(name, 'create_circle_emoji');
      expect(params, {
        'target_circle_id': 'circle-1',
        'emoji_name': 'party_parrot',
        'emoji_kind': 'emoji',
        'storage_path': 'circle-1/aaaaaaaa-0000-4000-8000-000000000001.png',
        'mime_type': 'image/png',
      });
      expect(source.removed, isEmpty);
    });

    test('refuses bad files and names before uploading', () async {
      final source = _FakeEmojiDataSource();
      final repository = SupabaseCircleEmojiRepository(source);
      Future<void> add(String name, Uint8List bytes) {
        return repository.addCircleEmoji(
          circleId: 'circle-1',
          name: name,
          kind: CircleEmojiKind.sticker,
          bytes: bytes,
        );
      }

      await expectLater(
        add('jpeg', Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])),
        throwsA(isA<CircleEmojiException>()),
      );
      await expectLater(
        add(
          'huge',
          Uint8List(maxCircleEmojiBytes + 1)..setAll(0, partyParrotPng),
        ),
        throwsA(isA<CircleEmojiException>()),
      );
      await expectLater(
        add('Bad Name', partyParrotPng),
        throwsA(isA<CircleEmojiException>()),
      );
      expect(source.uploads, isEmpty);
      expect(source.rpcCalls, isEmpty);
    });

    test('removes the upload when the server refuses it', () async {
      final source = _FakeEmojiDataSource()
        ..rpcError = const PostgrestException(
          message: 'This circle has no room for more stickers',
          code: '54000',
        );
      final repository = SupabaseCircleEmojiRepository(
        source,
        newId: () => 'bbbbbbbb-0000-4000-8000-000000000001',
      );

      await expectLater(
        repository.addCircleEmoji(
          circleId: 'circle-1',
          name: 'wave',
          kind: CircleEmojiKind.sticker,
          bytes: waveStickerPng,
        ),
        throwsA(
          isA<CircleEmojiException>().having(
            (error) => error.message,
            'message',
            'This circle already has 20 stickers.',
          ),
        ),
      );
      await pumpEventQueue();
      expect(source.removed, [
        'circle-emojis/circle-1/bbbbbbbb-0000-4000-8000-000000000001.png',
      ]);

      source.rpcError = const PostgrestException(
        message: 'That name is already taken',
        code: '23505',
      );
      await expectLater(
        repository.renameCircleEmoji(emojiId: partyParrotId, name: 'wave'),
        throwsA(
          isA<CircleEmojiException>().having(
            (error) => error.message,
            'message',
            'That name is already taken.',
          ),
        ),
      );
    });

    test('deleting removes the image the server names', () async {
      final source = _FakeEmojiDataSource()
        ..rpcResult = 'circle-1/$partyParrotId.png';
      final repository = SupabaseCircleEmojiRepository(source);

      await repository.deleteCircleEmoji(partyParrotId);

      expect(source.rpcCalls.single.$1, 'delete_circle_emoji');
      expect(source.rpcCalls.single.$2, {'target_emoji_id': partyParrotId});
      expect(source.removed, ['circle-emojis/circle-1/$partyParrotId.png']);
    });

    test('lists emoji and signs image URLs for a day', () async {
      final source = _FakeEmojiDataSource()
        ..rpcResult = [
          _emojiJson(),
          _emojiJson(id: waveStickerId, name: 'wave', kind: 'sticker'),
        ];
      final repository = SupabaseCircleEmojiRepository(source);

      final usable = await repository.listUsableEmojis();
      expect(source.rpcCalls.single.$1, 'list_my_usable_emojis');
      expect(usable.map((emoji) => emoji.kind), [
        CircleEmojiKind.emoji,
        CircleEmojiKind.sticker,
      ]);
      expect(usable.first.circleName, 'Book Club');
      expect(usable.first.creatorName, 'Ada');

      await repository.listCircleEmojis('circle-1');
      expect(source.rpcCalls.last.$2, {'target_circle_id': 'circle-1'});

      expect(
        await repository.createEmojiUrl('circle-1/x.png'),
        'https://signed.test/circle-emojis/circle-1/x.png?ttl=24h',
      );
    });

    test('watches changes in one circle or in all of them', () async {
      final source = _FakeEmojiDataSource();
      final repository = SupabaseCircleEmojiRepository(source);

      await repository.emojiChanges(circleId: 'circle-1').drain<void>();
      await repository.emojiChanges().drain<void>();

      expect(source.watched, ['circle-1', null]);
    });
  });

  group('live updates', () {
    test('the usable list reloads when emoji change elsewhere', () async {
      final emojis = FakeCircleEmojiRepository();
      final container = ProviderContainer(
        overrides: [
          circleEmojiRepositoryProvider.overrideWithValue(emojis),
          authRepositoryProvider.overrideWithValue(
            chat_fakes.FakeAuthRepository()
              ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final listener = container.listen(
        usableEmojisProvider,
        (previous, next) {},
      );
      addTearDown(listener.close);

      expect(await container.read(usableEmojisProvider.future), hasLength(5));
      expect(emojis.watched, [null]);

      // Someone in circle-2 deletes cat_thumbs.
      emojis.emojis = [
        for (final emoji in emojis.emojis)
          if (emoji.id != catThumbsId) emoji,
      ];
      emojis.changes.add(null);
      await Future<void>.delayed(Duration.zero);

      final reloaded = await container.read(usableEmojisProvider.future);
      expect(
        reloaded.map((emoji) => emoji.name),
        isNot(contains('cat_thumbs')),
      );
      expect(reloaded, hasLength(4));
    });

    testWidgets('the management page shows emoji others add', (tester) async {
      final emojis = FakeCircleEmojiRepository();
      await tester.pumpWidget(_page(emojis, canManage: false));
      await tester.pumpAndSettle();
      expect(emojis.watched, contains('circle-1'));
      expect(find.text('2 of 50 emoji'), findsOneWidget);

      emojis.emojis = [
        ...emojis.emojis,
        testEmoji('00000000-0000-4000-8000-000000000099', 'fresh'),
      ];
      emojis.changes.add(null);
      await tester.pumpAndSettle();

      expect(find.text('3 of 50 emoji'), findsOneWidget);
      expect(find.text(':fresh:'), findsOneWidget);
    });
  });

  test('image types are read from the bytes', () {
    expect(circleEmojiImageMimeType(partyParrotPng), 'image/png');
    expect(
      circleEmojiImageMimeType(Uint8List.fromList('GIF89a....'.codeUnits)),
      'image/gif',
    );
    expect(
      circleEmojiImageMimeType(
        Uint8List.fromList('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits),
      ),
      'image/webp',
    );
    expect(
      circleEmojiImageMimeType(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
      isNull,
    );
    expect(circleEmojiExtension('image/webp'), 'webp');
    expect(suggestedCircleEmojiName('Party Parrot!.gif'), 'party_parrot');
    expect(suggestedCircleEmojiName('x.png'), '');
    expect(circleEmojiNamePattern.hasMatch('ok_2'), isTrue);
    expect(circleEmojiNamePattern.hasMatch('No'), isFalse);
  });

  group('management page', () {
    testWidgets('lists emoji and stickers in tabs with counts', (tester) async {
      final emojis = FakeCircleEmojiRepository();
      await tester.pumpWidget(_page(emojis, canManage: false));
      await tester.pumpAndSettle();

      expect(find.text('Emoji & stickers'), findsOneWidget);
      expect(find.text('2 of 50 emoji'), findsOneWidget);
      expect(find.text(':party_parrot:'), findsOneWidget);
      expect(find.text(':blob_wave:'), findsOneWidget);
      expect(find.text(':cat_thumbs:'), findsNothing, reason: 'other circle');
      expect(find.text('Added by Ada'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('circle-emojis-upload-emoji')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('circle-emoji-menu-$partyParrotId')),
        findsNothing,
      );

      await tester.tap(find.text('Stickers'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 20 stickers'), findsOneWidget);
      expect(find.text('wave'), findsOneWidget);
    });

    testWidgets('managers upload, rename and delete', (tester) async {
      final emojis = FakeCircleEmojiRepository();
      final picker = chat_fakes.FakeImagePickerService()
        ..nextImage = ChatImageUpload(
          bytes: catThumbsPng,
          fileName: 'Thumbs Up.png',
          mimeType: 'image/png',
        );
      await tester.pumpWidget(_page(emojis, canManage: true, picker: picker));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('circle-emojis-upload-emoji')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Name emoji'), findsOneWidget);
      final field = find.byKey(const ValueKey('circle-emoji-name-field'));
      expect(tester.widget<TextField>(field).controller!.text, 'thumbs_up');

      await tester.enterText(field, 'no');
      await tester.tap(find.byKey(const ValueKey('circle-emoji-name-submit')));
      await tester.pumpAndSettle();
      expect(emojis.added.single.name, 'no');
      expect(emojis.added.single.kind, CircleEmojiKind.emoji);
      expect(find.text('3 of 50 emoji'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('circle-emoji-menu-$partyParrotId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('circle-emoji-name-field')),
        'Bad Name',
      );
      await tester.tap(find.byKey(const ValueKey('circle-emoji-name-submit')));
      await tester.pump();
      expect(
        find.text('Use 2 to 32 lowercase letters, digits or underscores.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('circle-emoji-name-field')),
        'parrot',
      );
      await tester.tap(find.byKey(const ValueKey('circle-emoji-name-submit')));
      await tester.pumpAndSettle();
      expect(emojis.renamed, [(partyParrotId, 'parrot')]);
      expect(find.text(':parrot:'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('circle-emoji-menu-$blobWaveId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('circle-emoji-delete-confirm')),
      );
      await tester.pumpAndSettle();
      expect(emojis.deleted, [blobWaveId]);
      expect(find.text(':blob_wave:'), findsNothing);
    });

    testWidgets('refuses images that are not PNG, GIF or WebP', (tester) async {
      final emojis = FakeCircleEmojiRepository();
      final picker = chat_fakes.FakeImagePickerService()
        ..nextImage = ChatImageUpload(
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]),
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
        );
      await tester.pumpWidget(_page(emojis, canManage: true, picker: picker));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stickers'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('circle-emojis-upload-sticker')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose a PNG, GIF or WebP image.'), findsOneWidget);
      expect(emojis.added, isEmpty);
    });
  });

  test('audit log reads emoji and sticker entries', () {
    CircleAuditEntry entry(String action, [Map<String, dynamic>? changes]) {
      return CircleAuditEntry(
        id: 'a',
        circleId: 'circle-1',
        action: action,
        targetType: action.split('_').first,
        targetLabel: 'parrot',
        changes: changes ?? const {},
        createdAt: DateTime.utc(2026, 10, 14),
        actor: const CircleAuditActor(
          id: 'user-1',
          username: 'ada',
          displayName: 'Ada',
        ),
      );
    }

    String summary(CircleAuditEntry entry) =>
        circleAuditSummary(entry, null).toPlainText();
    const rename = {
      'name': {'old': 'party_parrot', 'new': 'parrot'},
    };

    expect(summary(entry('emoji_create')), 'Ada added emoji :parrot:');
    expect(
      summary(entry('emoji_update', rename)),
      'Ada renamed emoji :party_parrot: to :parrot:',
    );
    expect(summary(entry('emoji_delete')), 'Ada deleted emoji :parrot:');
    expect(summary(entry('sticker_create')), 'Ada added sticker parrot');
    expect(
      summary(entry('sticker_update', rename)),
      'Ada renamed sticker party_parrot to parrot',
    );
    expect(summary(entry('sticker_delete')), 'Ada deleted sticker parrot');
    expect(circleAuditIcon('emoji_create'), Icons.add_reaction_outlined);
    expect(circleAuditIcon('sticker_delete'), Icons.delete_outline);
    expect(
      CircleAuditActionGroup.of('sticker_update'),
      CircleAuditActionGroup.sticker,
    );
    expect(
      CircleAuditActionGroup.filters,
      containsAll([
        CircleAuditActionGroup.emoji,
        CircleAuditActionGroup.sticker,
      ]),
    );
  });
}

Widget _page(
  FakeCircleEmojiRepository emojis, {
  required bool canManage,
  chat_fakes.FakeImagePickerService? picker,
}) {
  final circles = circle_fakes.FakeCirclesRepository();
  return ProviderScope(
    overrides: [
      circleEmojiRepositoryProvider.overrideWithValue(emojis),
      circlesRepositoryProvider.overrideWithValue(circles),
      chatsRepositoryProvider.overrideWithValue(
        chat_fakes.FakeChatsRepository(),
      ),
      circleDetailProvider.overrideWith(
        (ref, circleId) async => CircleDetail(
          circle: CircleSummary(
            id: circleId,
            name: 'Book Club',
            memberCount: 3,
            channelCount: 1,
            currentUserRole: 'member',
            currentUserPermissions: canManage
                ? CirclePermission.manageEmojis.bit
                : CirclePermission.defaultRolePermissions,
          ),
          members: const [],
          channels: const [],
          posts: const [],
        ),
      ),
      testEmojiImageOverride(),
      if (picker != null) imagePickerServiceProvider.overrideWithValue(picker),
    ],
    child: const MaterialApp(home: CircleEmojisScreen(circleId: 'circle-1')),
  );
}
