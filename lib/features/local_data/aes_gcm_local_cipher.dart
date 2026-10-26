import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:wecord/features/local_data/local_cipher.dart';

/// Where the key's bytes are kept.
abstract interface class LocalKeyStore {
  Future<Uint8List?> read();

  Future<void> write(Uint8List key);

  Future<void> delete();
}

class MemoryKeyStore implements LocalKeyStore {
  Uint8List? _key;

  @override
  Future<Uint8List?> read() async => _key;

  @override
  Future<void> write(Uint8List key) async => _key = key;

  @override
  Future<void> delete() async => _key = null;
}

/// AES-256-GCM with a key from a [LocalKeyStore] (the Keychain on iPhone and
/// Mac). The key is read once and held in memory while the app runs.
class AesGcmLocalCipher extends FramedLocalCipher {
  AesGcmLocalCipher(
    this._keyStore, {
    this.protection = LocalProtection.keychain,
  });

  final LocalKeyStore _keyStore;
  final _algorithm = AesGcm.with256bits();
  Future<SecretKey>? _key;

  @override
  final LocalProtection protection;

  Future<SecretKey> _loadKey() async {
    final stored = await _keyStore.read();
    if (stored != null && stored.length == 32) {
      return SecretKey(stored);
    }
    final random = Random.secure();
    final fresh = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await _keyStore.write(fresh);
    return SecretKey(fresh);
  }

  Future<SecretKey> get _secret {
    return _key ??= _loadKey().catchError((Object error) {
      // Try again next time rather than keep a failure.
      _key = null;
      throw error;
    });
  }

  @override
  Future<void> ensureReady() async {
    await _secret;
  }

  @override
  Future<Uint8List> encryptRaw(Uint8List plain, Uint8List nonce) async {
    final box = await _algorithm.encrypt(
      plain,
      secretKey: await _secret,
      nonce: nonce,
    );
    final out = Uint8List(box.cipherText.length + box.mac.bytes.length);
    out.setRange(0, box.cipherText.length, box.cipherText);
    out.setRange(box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  @override
  Future<Uint8List?> decryptRaw(
    Uint8List nonce,
    Uint8List cipherAndTag,
  ) async {
    final split = cipherAndTag.length - FramedLocalCipher.tagLength;
    try {
      final plain = await _algorithm.decrypt(
        SecretBox(
          Uint8List.sublistView(cipherAndTag, 0, split),
          nonce: nonce,
          mac: Mac(Uint8List.sublistView(cipherAndTag, split)),
        ),
        secretKey: await _secret,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  @override
  Future<void> destroyKey() async {
    _key = null;
    await _keyStore.delete();
  }
}
