import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/platform_chat_cache_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/chats/offline/platform_chat_cache_web.dart'
    as platform;
import 'package:wecord/features/local_data/local_cipher.dart';

/// Opens the platform's offline chat cache: SQLite on iOS and macOS,
/// IndexedDB on the web, with what it holds encrypted by [cipher] and the
/// offline search index kept beside it. Null when it cannot be opened, or
/// when [cipher] has no key (the app then works without one: nothing is
/// ever kept in the clear).
Future<ChatCache?> openPlatformChatCache(LocalCipher cipher) async {
  if (cipher.protection == LocalProtection.unavailable) {
    return null;
  }
  try {
    return await platform.openChatCache(cipher);
  } catch (_) {
    return null;
  }
}
