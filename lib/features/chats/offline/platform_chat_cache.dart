import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/platform_chat_cache_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/chats/offline/platform_chat_cache_web.dart'
    as platform;

/// Opens the platform's offline chat cache: SQLite on iOS and macOS,
/// IndexedDB on the web. Null when it cannot be opened (the app then works
/// without one).
Future<ChatCache?> openPlatformChatCache() async {
  try {
    return await platform.openChatCache();
  } catch (_) {
    return null;
  }
}
