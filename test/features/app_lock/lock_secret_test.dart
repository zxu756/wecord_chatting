import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/lock_secret.dart';

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // The well known vectors for the password "password" and the salt "salt".
    const salt = 'c2FsdA=='; // base64 of "salt"
    test('matches the published vectors', () {
      expect(
        LockSecret.hash('password', salt, rounds: 1),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
      expect(
        LockSecret.hash('password', salt, rounds: 2),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
      expect(
        LockSecret.hash('password', salt, rounds: 4096),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  test('salts are random and long enough', () {
    final a = LockSecret.newSalt();
    final b = LockSecret.newSalt();
    expect(a, isNot(b));
    expect(a.length, greaterThanOrEqualTo(22));
  });

  test('the same secret over the same salt hashes the same', () {
    final salt = LockSecret.newSalt(Random(7));
    expect(LockSecret.hash('123456', salt), LockSecret.hash('123456', salt));
    expect(
      LockSecret.hash('123456', salt),
      isNot(LockSecret.hash('123457', salt)),
    );
    expect(
      LockSecret.hash('123456', salt),
      isNot(LockSecret.hash('123456', LockSecret.newSalt(Random(8)))),
    );
  });

  group('StoredSecret', () {
    test('accepts the secret and nothing else', () {
      final stored = StoredSecret.of('482913', random: Random(1));
      expect(stored.accepts('482913'), isTrue);
      expect(stored.accepts('482914'), isFalse);
      expect(stored.accepts(''), isFalse);
      expect(stored.accepts('4829130'), isFalse);
    });

    test('is never the secret itself', () {
      final stored = StoredSecret.of('482913');
      expect(stored.encode(), isNot(contains('482913')));
      expect(stored.hash, isNot(contains('482913')));
    });

    test('survives being kept as text', () {
      final stored = StoredSecret.of('482913');
      final back = StoredSecret.decode(stored.encode());
      expect(back, isNotNull);
      expect(back!.accepts('482913'), isTrue);
      expect(back.accepts('000000'), isFalse);
    });

    test('rubbish decodes to nothing', () {
      expect(StoredSecret.decode(null), isNull);
      expect(StoredSecret.decode(''), isNull);
      expect(StoredSecret.decode('abc'), isNull);
      expect(StoredSecret.decode('a:b:c'), isNull);
      expect(StoredSecret.decode(':b'), isNull);
    });
  });
}
