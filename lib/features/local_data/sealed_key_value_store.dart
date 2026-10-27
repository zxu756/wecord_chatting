import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_data/local_cipher.dart';

/// A [KeyValueStore] that keeps every value encrypted. The keys stay as they
/// are (they name a user and a conversation, never what was said).
///
/// A value from before the encryption (plain JSON) is still read, and
/// [migrateLegacy] writes those back encrypted.
class SealedKeyValueStore implements KeyValueStore {
  SealedKeyValueStore(this.inner, this.cipher);

  final KeyValueStore inner;
  final LocalCipher cipher;

  @override
  Future<String?> read(String key) async {
    return (await cipher.read(await inner.read(key))).text;
  }

  @override
  Future<void> write(String key, String value) async {
    await inner.write(key, await cipher.seal(value));
  }

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<List<String>> keys() => inner.keys();

  @override
  Future<void> clear() => inner.clear();

  /// Encrypts the values that are still plain and returns how many there
  /// were. A value that cannot be encrypted stays as it is (it is tried
  /// again next time), so nothing is lost. [pause] gives the app a turn
  /// between values.
  Future<int> migrateLegacy({
    Future<void> Function()? pause,
    bool Function()? shouldStop,
  }) async {
    var migrated = 0;
    for (final key in await inner.keys()) {
      if (shouldStop?.call() ?? false) {
        break;
      }
      try {
        final raw = await inner.read(key);
        if (raw == null || isSealedText(raw)) {
          continue;
        }
        await inner.write(key, await cipher.seal(raw));
        migrated++;
      } on Object {
        // Left as it is; tried again next start.
      }
      await pause?.call();
    }
    return migrated;
  }
}
