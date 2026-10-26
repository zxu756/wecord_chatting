import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Text this app encrypted for its own storage starts with this; the stored
/// forms from before the encryption (JSON) never do, which is how the two
/// are told apart while old data is moved over.
const sealedPrefix = 'wc1.';

/// The first bytes of encrypted bytes (wallpaper photos), for the same
/// reason. No picture format starts with it.
const sealedMagic = <int>[0x57, 0x43, 0x31, 0x01];

bool isSealedText(String? text) =>
    text != null && text.startsWith(sealedPrefix);

bool isSealedBytes(Uint8List bytes) {
  if (bytes.length < sealedMagic.length) {
    return false;
  }
  for (var index = 0; index < sealedMagic.length; index++) {
    if (bytes[index] != sealedMagic[index]) {
      return false;
    }
  }
  return true;
}

/// How well the key that protects the local data is kept on this device.
enum LocalProtection {
  /// The key lives in the system's Keychain (iPhone, Mac), never in the
  /// app's own files, and is not copied to backups or other devices.
  keychain,

  /// The web: a key the browser makes and will not hand out, kept in the
  /// browser's own database. Scripts of this site can still use it.
  browserKey,

  /// Only for this run (tests): the key is not kept anywhere.
  session,

  /// The key could not be opened (for example the Keychain refused). Nothing
  /// is kept on this device then.
  unavailable,
}

/// Encrypts what the app keeps on this device (the offline chat cache, texts
/// read from pictures and voice messages, drafts, the search index). One key
/// per device, made on first use and thrown away when the person signs out,
/// which makes everything that was encrypted with it unreadable at once.
abstract interface class LocalCipher {
  LocalProtection get protection;

  /// Encrypted [plain]: a format marker, a fresh nonce, the cipher text and
  /// its tag (AES-256-GCM).
  Future<Uint8List> sealBytes(Uint8List plain);

  /// What [sealBytes] made, or null when it was made with another key or was
  /// changed.
  Future<Uint8List?> openBytes(Uint8List sealed);

  /// Makes sure the key can be read or made now; throws when it cannot.
  Future<void> ensureReady();

  /// Forgets the key, here and in the system's store. A new one is made the
  /// next time something is encrypted.
  Future<void> destroyKey();
}

/// Text in and out of a [LocalCipher].
extension LocalCipherText on LocalCipher {
  /// `wc1.` and the encrypted text in base64.
  Future<String> seal(String plain) async {
    final sealed = await sealBytes(Uint8List.fromList(utf8.encode(plain)));
    return '$sealedPrefix${base64.encode(sealed)}';
  }

  /// The text [seal] made; null when it cannot be read with this key.
  Future<String?> open(String sealed) async {
    if (!isSealedText(sealed)) {
      return null;
    }
    try {
      final bytes = base64.decode(sealed.substring(sealedPrefix.length));
      final plain = await openBytes(bytes);
      return plain == null ? null : utf8.decode(plain);
    } on Object {
      return null;
    }
  }

  /// A stored value read back: sealed text is opened, text from before the
  /// encryption is returned as it is with `legacy` set, so the caller can
  /// write it back sealed. `text` is null when there is nothing to read or
  /// it cannot be opened.
  Future<({String? text, bool legacy})> read(String? stored) async {
    if (stored == null) {
      return (text: null, legacy: false);
    }
    if (isSealedText(stored)) {
      return (text: await open(stored), legacy: false);
    }
    return (text: stored, legacy: true);
  }
}

/// The AES-GCM framing both implementations share: they only differ in how
/// they hold the key and run the cipher.
abstract class FramedLocalCipher implements LocalCipher {
  static const nonceLength = 12;
  static const tagLength = 16;

  static final _random = Random.secure();

  /// The cipher text with the tag appended.
  Future<Uint8List> encryptRaw(Uint8List plain, Uint8List nonce);

  /// Null when the tag does not fit.
  Future<Uint8List?> decryptRaw(Uint8List nonce, Uint8List cipherAndTag);

  @override
  Future<Uint8List> sealBytes(Uint8List plain) async {
    final nonce = Uint8List(nonceLength);
    for (var index = 0; index < nonceLength; index++) {
      nonce[index] = _random.nextInt(256);
    }
    final body = await encryptRaw(plain, nonce);
    final out = Uint8List(sealedMagic.length + nonceLength + body.length);
    out.setRange(0, sealedMagic.length, sealedMagic);
    out.setRange(sealedMagic.length, sealedMagic.length + nonceLength, nonce);
    out.setRange(sealedMagic.length + nonceLength, out.length, body);
    return out;
  }

  @override
  Future<Uint8List?> openBytes(Uint8List sealed) async {
    final header = sealedMagic.length + nonceLength;
    if (!isSealedBytes(sealed) || sealed.length < header + tagLength) {
      return null;
    }
    try {
      return await decryptRaw(
        Uint8List.sublistView(sealed, sealedMagic.length, header),
        Uint8List.sublistView(sealed, header),
      );
    } on Object {
      return null;
    }
  }
}

/// Used when no key can be had: nothing is encrypted, so nothing is kept.
class UnavailableLocalCipher implements LocalCipher {
  const UnavailableLocalCipher([this.reason]);

  final Object? reason;

  @override
  LocalProtection get protection => LocalProtection.unavailable;

  @override
  Future<Uint8List> sealBytes(Uint8List plain) =>
      Future.error(StateError('The key for local data is not available.'));

  @override
  Future<Uint8List?> openBytes(Uint8List sealed) async => null;

  @override
  Future<void> ensureReady() =>
      Future.error(StateError('The key for local data is not available.'));

  @override
  Future<void> destroyKey() async {}
}
