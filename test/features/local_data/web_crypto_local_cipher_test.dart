@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/web_crypto_local_cipher.dart';

// Runs only in a browser: `flutter test --platform chrome <this file>`.
void main() {
  test('seals with a key the browser keeps, and a new instance reads it back', () async {
    final first = WebCryptoLocalCipher('wecord_test_key_a');
    await first.ensureReady();
    final sealed = await first.seal('银行卡 9527 / hunter2');

    expect(isSealedText(sealed), isTrue);
    expect(sealed, isNot(contains('hunter2')));
    expect(await first.open(sealed), '银行卡 9527 / hunter2');

    // The key came from IndexedDB, not from this object.
    final second = WebCryptoLocalCipher('wecord_test_key_a');
    expect(await second.open(sealed), '银行卡 9527 / hunter2');
    expect(first.protection, LocalProtection.browserKey);
  });

  test('another database has another key; destroying the key makes data unreadable', () async {
    final owner = WebCryptoLocalCipher('wecord_test_key_b');
    final sealed = await owner.seal('secret');

    expect(await WebCryptoLocalCipher('wecord_test_key_c').open(sealed), isNull);

    await owner.destroyKey();
    final fresh = WebCryptoLocalCipher('wecord_test_key_b');
    expect(await fresh.open(sealed), isNull);
    // And it can seal again, with a new key.
    expect(await fresh.open(await fresh.seal('again')), 'again');
  });
}
