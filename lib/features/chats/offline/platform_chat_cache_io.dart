import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/sqlite_chat_cache.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/sealed_key_value_store.dart';
import 'package:wecord/features/local_data/sqlite_key_value_store.dart';
import 'package:wecord/features/local_search/indexed_chat_cache.dart';
import 'package:wecord/features/local_search/local_search_index.dart';

Future<ChatCache?> openChatCache(LocalCipher cipher) async {
  if (!Platform.isIOS && !Platform.isMacOS && !Platform.isAndroid) {
    return null;
  }
  // Support files are kept with backups off the user's Documents.
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final cache = await SqliteChatCache.open(
    '${directory.path}/chat_cache.sqlite',
    cipher: cipher,
  );
  final index = LocalSearchIndex(
    SealedKeyValueStore(
      await SqliteKeyValueStore.open('${directory.path}/search_index.sqlite'),
      cipher,
    ),
  );
  // What an earlier version stored in the clear is encrypted in the
  // background, a little at a time and after the app is up; until then it is
  // read as it is, so nothing waits and nothing is lost.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 3), () async {
      try {
        await cache.migrateLegacy(
          pause: () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      } catch (_) {
        // Tried again at the next start.
      }
    }),
  );
  return IndexedChatCache(cache, index);
}
