import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_models.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/offline_session.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/local_data/aes_gcm_local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';
import 'package:wecord/features/local_data/local_data_wipe.dart';
import 'package:wecord/features/local_data/sealed_wallpaper_photo_store.dart';
import 'package:wecord/features/search/recent_searches.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

import '../chats/chat_thread_screen_test.dart' as thread_test;
import '../local_search/local_search_fakes.dart';

const _secret = 'my card number is 4242 4242 4242 4242';

Future<String?> _stored(String key) async =>
    (await SharedPreferences.getInstance()).getString(key);

AesGcmLocalCipher _cipher([MemoryKeyStore? keys]) =>
    AesGcmLocalCipher(keys ?? MemoryKeyStore());

Future<void> _settle() async {
  for (var turn = 0; turn < 20; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('transcripts and texts read from pictures', () {
    test('are stored sealed and read back', () async {
      final cipher = _cipher();
      await SharedPreferencesTranscriptCache(
        userId: 'user-1',
        cipher: cipher,
      ).write(
        'm1',
        CachedTranscript(
          text: _secret,
          engine: TranscribeEngine.onDevice,
          savedAt: DateTime.utc(2026, 10, 1),
        ),
      );
      await SharedPreferencesImageTextCache(
        userId: 'user-1',
        cipher: cipher,
      ).write(
        'm:1',
        CachedImageText(text: _secret, savedAt: DateTime.utc(2026, 10, 1)),
      );

      for (final key in ['wecord.transcripts.user-1', 'wecord.image_text.user-1']) {
        final stored = await _stored(key);
        expect(stored, startsWith(sealedPrefix), reason: key);
        expect(stored, isNot(contains('4242')));
      }
      expect(
        (await SharedPreferencesTranscriptCache(
          userId: 'user-1',
          cipher: cipher,
        ).read('m1'))?.text,
        _secret,
      );
      expect(
        (await SharedPreferencesImageTextCache(
          userId: 'user-1',
          cipher: cipher,
        ).read('m:1'))?.text,
        _secret,
      );
      // Another key reads nothing.
      expect(
        await SharedPreferencesTranscriptCache(
          userId: 'user-1',
          cipher: _cipher(),
        ).read('m1'),
        isNull,
      );
    });

    test('from before the encryption are read, then written back sealed', () async {
      SharedPreferences.setMockInitialValues({
        'wecord.transcripts.user-1': jsonEncode({
          'm1': {'t': _secret, 'e': 'onDevice', 'at': 1},
        }),
        'wecord.image_text.user-1': jsonEncode({
          'm:1': {'t': _secret, 'at': 1},
        }),
      });
      final cipher = _cipher();

      expect(
        (await SharedPreferencesTranscriptCache(
          userId: 'user-1',
          cipher: cipher,
        ).read('m1'))?.text,
        _secret,
      );
      expect(
        (await SharedPreferencesImageTextCache(
          userId: 'user-1',
          cipher: cipher,
        ).read('m:1'))?.text,
        _secret,
      );
      await _settle();

      for (final key in ['wecord.transcripts.user-1', 'wecord.image_text.user-1']) {
        expect(await _stored(key), startsWith(sealedPrefix), reason: key);
      }
    });

    test('video captions are sealed too', () async {
      final cipher = _cipher();
      final cache = SharedPreferencesVideoCaptionCache(
        userId: 'user-1',
        cipher: cipher,
      );
      await cache.write(
        'chat-files/a/v.mp4',
        VideoCaptions(
          cues: [
            CaptionCue(
              start: Duration.zero,
              end: const Duration(seconds: 2),
              text: _secret,
            ),
          ],
          savedAt: DateTime.utc(2026, 10, 1),
        ),
      );

      final stored = await _stored('wecord.video_captions.user-1');
      expect(stored, startsWith(sealedPrefix));
      expect(stored, isNot(contains('4242')));
      expect(
        (await SharedPreferencesVideoCaptionCache(
          userId: 'user-1',
          cipher: cipher,
        ).read('chat-files/a/v.mp4'))?.cues.single.text,
        _secret,
      );
    });
  });

  group('drafts and recent searches', () {
    test('drafts are stored sealed; old ones are read and sealed', () async {
      final cipher = _cipher();
      final store = SharedPreferencesComposerDraftStore(cipher: cipher);
      await store.save('user-1', {'c1': const ComposerDraft(text: _secret)});

      final stored = await _stored('wecord.chats.user-1.drafts');
      expect(stored, startsWith(sealedPrefix));
      expect(stored, isNot(contains('4242')));
      expect((await store.load('user-1'))['c1']?.text, _secret);

      SharedPreferences.setMockInitialValues({
        'wecord.chats.user-2.drafts': encodeComposerDrafts({
          'c9': const ComposerDraft(text: 'old draft'),
        }),
      });
      expect(
        (await SharedPreferencesComposerDraftStore(cipher: cipher).load(
          'user-2',
        ))['c9']?.text,
        'old draft',
      );
      expect(
        await _stored('wecord.chats.user-2.drafts'),
        startsWith(sealedPrefix),
      );
    });

    test('recent searches are stored sealed; the old list moves over', () async {
      final cipher = _cipher();
      final store = SharedPreferencesRecentSearchesStore(cipher: cipher);
      await store.save(['salary', '体检报告']);

      final stored = await _stored('wecord.search.recent.v2');
      expect(stored, startsWith(sealedPrefix));
      expect(stored, isNot(contains('salary')));
      expect(await store.load(), ['salary', '体检报告']);

      SharedPreferences.setMockInitialValues({
        'wecord.search.recent': ['old search'],
      });
      expect(await store.load(), ['old search']);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('wecord.search.recent'), isFalse);
      expect(
        preferences.getString('wecord.search.recent.v2'),
        startsWith(sealedPrefix),
      );
      expect(await store.load(), ['old search']);
    });
  });

  group('wallpaper photos', () {
    test('are stored sealed, and an old photo is read and sealed', () async {
      final inner = InMemoryWallpaperPhotoStore();
      final cipher = _cipher();
      final store = SealedWallpaperPhotoStore(inner, cipher);
      final photo = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3, 4, 5]);

      await store.write('a.jpg', photo);

      expect(isSealedBytes(inner.photos['a.jpg']!), isTrue);
      expect(await store.read('a.jpg'), photo);

      inner.photos['old.jpg'] = photo;
      expect(await store.read('old.jpg'), photo);
      await _settle();
      expect(isSealedBytes(inner.photos['old.jpg']!), isTrue);
      expect(await store.read('old.jpg'), photo);

      expect(
        await SealedWallpaperPhotoStore(inner, _cipher()).read('a.jpg'),
        isNull,
        reason: 'another key: fetched again',
      );
      expect(await store.read('missing'), isNull);
    });
  });

  group('signing out', () {
    late MemoryKeyStore keys;
    late AesGcmLocalCipher cipher;
    late thread_test.FakeAuthRepository auth;
    late LocalSearchWorld world;
    late StreamController<AuthUser?> authChanges;

    ProviderContainer containerOf() {
      final container = ProviderContainer(
        overrides: [
          chatCacheProvider.overrideWithValue(world.cache),
          localCipherProvider.overrideWithValue(cipher),
          authRepositoryProvider.overrideWithValue(auth),
          authStateProvider.overrideWith((ref) => authChanges.stream),
          wallpaperPhotoStoreProvider.overrideWithValue(
            InMemoryWallpaperPhotoStore({'w.jpg': Uint8List(3)}),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(offlineSessionGuardProvider, (_, _) {});
      return container;
    }

    setUp(() async {
      keys = MemoryKeyStore();
      cipher = _cipher(keys);
      auth = thread_test.FakeAuthRepository()
        ..user = const AuthUser(id: 'user-1');
      authChanges = StreamController<AuthUser?>.broadcast();
      addTearDown(authChanges.close);
      world = LocalSearchWorld();
      SharedPreferences.setMockInitialValues({
        'wecord.search.recent.v2': await cipher.seal('["x"]'),
        'wecord.transcripts.user-1': await cipher.seal('{}'),
        'wecord.image_text.user-1': 'old',
        'wecord.video_captions.user-1': 'old',
        'wecord.chats.user-1.drafts': 'old',
        'wecord.theme_mode': 'dark',
      });
      await world.cacheChat('c1', [messageRow('m1', 'c1', 'findable words')]);
      await world.cache.writeOutbox(meId, [
        {'client_id': 'x'},
      ]);
    });

    test('forgets the chats, the texts, the index and the key', () async {
      final sealedBefore = await cipher.seal('about the old key');
      expect(await keys.read(), isNotNull);
      containerOf();
      authChanges.add(const AuthUser(id: 'user-1'));
      await _settle();
      expect(await world.ids('findable'), ['m1']);

      auth.user = null;
      authChanges.add(null);
      await _settle();

      expect(await world.ids('findable'), isEmpty);
      expect(await world.indexStore.keys(), isEmpty);
      expect(await world.cache.readOutbox(meId), isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {'wecord.theme_mode'});
      expect(await keys.read(), isNull, reason: 'the key is deleted');
      expect(await cipher.open(sealedBefore), isNull);
    });

    test('forgets them at start-up too when nobody is signed in', () async {
      auth.user = null;
      containerOf();
      await _settle();

      expect(await keys.read(), isNull);
      expect(await world.ids('findable'), isEmpty);
      expect((await SharedPreferences.getInstance()).getKeys(), {
        'wecord.theme_mode',
      });
    });

    test('keeps the key when someone else has signed in by then', () async {
      containerOf();
      authChanges.add(const AuthUser(id: 'user-1'));
      await _settle();
      auth.user = const AuthUser(id: 'user-2');
      authChanges.add(const AuthUser(id: 'user-2'));
      await _settle();

      expect(await world.ids('findable'), isEmpty);
      expect(await keys.read(), isNotNull);
    });

    test('knows which preferences hold chat content', () {
      for (final key in [
        'wecord.transcripts.u',
        'wecord.image_text.u',
        'wecord.video_captions.u',
        'wecord.search.recent',
        'wecord.search.recent.v2',
        'wecord.chats.u.drafts',
      ]) {
        expect(isChatContentPreferenceKey(key), isTrue, reason: key);
      }
      for (final key in [
        'wecord.theme_mode',
        'wecord.chats.u.quick_reaction',
        'wecord.storage.auto_clean',
      ]) {
        expect(isChatContentPreferenceKey(key), isFalse, reason: key);
      }
    });
  });
}
