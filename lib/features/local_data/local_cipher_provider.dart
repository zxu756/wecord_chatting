import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/local_data/aes_gcm_local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/platform_local_cipher_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/local_data/platform_local_cipher_web.dart'
    as platform;

/// A cipher with a key that lives only for this run.
LocalCipher createSessionLocalCipher() =>
    AesGcmLocalCipher(MemoryKeyStore(), protection: LocalProtection.session);

/// The one session cipher of this run: what the stores use when nothing
/// gave them the platform's, so tests and previews never write anything
/// readable, and stores made one after the other still read each other.
final LocalCipher sessionLocalCipher = createSessionLocalCipher();

/// The cipher for what this device keeps. The app's bootstrap replaces it
/// with [openPlatformLocalCipher]'s.
final localCipherProvider = Provider<LocalCipher>((ref) => sessionLocalCipher);

/// The platform's cipher (key in the Keychain on iPhone and Mac, a key the
/// browser will not hand out on the web), checked to work now; when its key
/// cannot be had the result is an [UnavailableLocalCipher] and the app keeps
/// nothing on the device.
Future<LocalCipher> openPlatformLocalCipher() async {
  try {
    final cipher = platform.createPlatformCipher();
    await cipher.ensureReady();
    return cipher;
  } on Object catch (error) {
    return UnavailableLocalCipher(error);
  }
}
