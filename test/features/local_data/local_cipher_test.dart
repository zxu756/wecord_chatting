import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_data/aes_gcm_local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/sealed_key_value_store.dart';

AesGcmLocalCipher _cipher([LocalKeyStore? store]) =>
    AesGcmLocalCipher(store ?? MemoryKeyStore());

void main() {
  group('LocalCipher', () {
    test('seals text so that it does not show and opens it again', () async {
      final cipher = _cipher();
      const secret = '今天晚上八点，老地方见 / meet at eight';
      final sealed = await cipher.seal(secret);

      expect(sealed, startsWith(sealedPrefix));
      expect(sealed, isNot(contains('老地方')));
      expect(sealed, isNot(contains('meet')));
      expect(await cipher.open(sealed), secret);
    });

    test('seals the same text differently every time', () async {
      final cipher = _cipher();
      expect(await cipher.seal('hello'), isNot(await cipher.seal('hello')));
    });

    test('another key, a changed value or plain text do not open', () async {
      final cipher = _cipher();
      final sealed = await cipher.seal('private');

      expect(await _cipher().open(sealed), isNull);
      expect(await cipher.open('{"body":"private"}'), isNull);

      final bytes = base64.decode(sealed.substring(sealedPrefix.length));
      bytes[bytes.length - 1] ^= 1;
      expect(
        await cipher.open('$sealedPrefix${base64.encode(bytes)}'),
        isNull,
        reason: 'the tag no longer fits',
      );
      expect(await cipher.open('${sealedPrefix}AAAA'), isNull);
      expect(await cipher.openBytes(Uint8List(0)), isNull);
    });

    test('keeps the key between sessions through its store', () async {
      final store = MemoryKeyStore();
      final sealed = await _cipher(store).seal('kept');

      expect(await _cipher(store).open(sealed), 'kept');
      expect((await store.read())!.length, 32);
    });

    test('forgets the key: what was sealed can not be read again', () async {
      final store = MemoryKeyStore();
      final cipher = _cipher(store);
      final sealed = await cipher.seal('gone with the key');

      await cipher.destroyKey();

      expect(await store.read(), isNull);
      expect(await cipher.open(sealed), isNull);
      // A new key is made the next time something is sealed.
      final later = await cipher.seal('new');
      expect(await cipher.open(later), 'new');
      expect(await cipher.open(sealed), isNull);
    });

    test('reads plain text from before the encryption as it is', () async {
      final cipher = _cipher();
      final old = await cipher.read('{"a":1}');
      expect(old.text, '{"a":1}');
      expect(old.legacy, isTrue);

      final sealed = await cipher.read(await cipher.seal('x'));
      expect(sealed.text, 'x');
      expect(sealed.legacy, isFalse);

      final missing = await cipher.read(null);
      expect(missing.text, isNull);
      expect(missing.legacy, isFalse);
    });

    test('a failing key store is reported, and retried later', () async {
      final store = _FlakyKeyStore();
      final cipher = _cipher(store);

      await expectLater(cipher.ensureReady(), throwsStateError);
      store.broken = false;
      await cipher.ensureReady();
      expect(await cipher.open(await cipher.seal('ok')), 'ok');
    });

    test('an unavailable cipher keeps nothing', () async {
      const cipher = UnavailableLocalCipher();
      await expectLater(cipher.seal('x'), throwsStateError);
      expect(cipher.protection, LocalProtection.unavailable);
    });

    test('seals a chat\'s worth of rows quickly enough', () async {
      final cipher = _cipher();
      final text = List.filled(600, '消息 message ').join();
      final watch = Stopwatch()..start();
      for (var index = 0; index < 100; index++) {
        await cipher.open(await cipher.seal(text));
      }
      watch.stop();
      // 100 rows of ~8 KB each way; far below a frame budget per row even
      // unoptimised (the debug VM is several times slower than a phone).
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('SealedKeyValueStore', () {
    test('keeps values sealed and the keys as they are', () async {
      final inner = MemoryKeyValueStore();
      final store = SealedKeyValueStore(inner, _cipher());
      await store.write('u/1/messages/c', '[{"body":"top secret"}]');

      expect(inner.values.keys, ['u/1/messages/c']);
      expect(inner.values['u/1/messages/c'], startsWith(sealedPrefix));
      expect(inner.values['u/1/messages/c'], isNot(contains('secret')));
      expect(await store.read('u/1/messages/c'), '[{"body":"top secret"}]');
    });

    test('reads old plain values and moves them over', () async {
      final inner = MemoryKeyValueStore();
      inner.values['a'] = '[{"body":"old"}]';
      inner.values['b'] = '[{"body":"older"}]';
      final store = SealedKeyValueStore(inner, _cipher());

      expect(await store.read('a'), '[{"body":"old"}]');
      expect(await store.migrateLegacy(), 2);

      expect(inner.values.values.every(isSealedText), isTrue);
      expect(await store.read('a'), '[{"body":"old"}]');
      expect(await store.read('b'), '[{"body":"older"}]');
      expect(await store.migrateLegacy(), 0);
    });

    test('a value of another key reads as missing', () async {
      final inner = MemoryKeyValueStore();
      await SealedKeyValueStore(inner, _cipher()).write('k', 'v');
      expect(await SealedKeyValueStore(inner, _cipher()).read('k'), isNull);
    });

    test('stops moving values over when asked', () async {
      final inner = MemoryKeyValueStore();
      for (var index = 0; index < 5; index++) {
        inner.values['k$index'] = '[]';
      }
      final store = SealedKeyValueStore(inner, _cipher());
      var calls = 0;
      final moved = await store.migrateLegacy(shouldStop: () => ++calls > 2);
      expect(moved, 2);
    });
  });
}

class _FlakyKeyStore implements LocalKeyStore {
  var broken = true;
  Uint8List? key;

  @override
  Future<Uint8List?> read() async {
    if (broken) {
      throw StateError('keychain locked');
    }
    return key;
  }

  @override
  Future<void> write(Uint8List value) async => key = value;

  @override
  Future<void> delete() async => key = null;
}
