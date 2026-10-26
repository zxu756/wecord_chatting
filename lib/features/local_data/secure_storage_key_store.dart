import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wecord/features/local_data/aes_gcm_local_cipher.dart';

/// The device key in the system's Keychain (iPhone and Mac).
///
/// - It is stored "this device only", available after the first unlock, so
///   it is not part of a backup and does not move to another device: a copy
///   of the app's files taken from a backup cannot be read.
/// - On the Mac the older, file-based keychain is used: the newer one needs a
///   Keychain Sharing entitlement and a provisioning profile, which the free
///   signing the Mac build uses does not give.
class SecureStorageKeyStore implements LocalKeyStore {
  SecureStorageKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const keyName = 'wecord.local_data.key.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> read() async {
    final text = await _storage.read(key: keyName);
    if (text == null) {
      return null;
    }
    try {
      return base64.decode(text);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(Uint8List key) {
    return _storage.write(key: keyName, value: base64.encode(key));
  }

  @override
  Future<void> delete() => _storage.delete(key: keyName);
}
