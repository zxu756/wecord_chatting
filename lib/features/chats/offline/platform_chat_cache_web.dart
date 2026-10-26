import 'dart:async';

import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/indexed_db_store.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/sealed_key_value_store.dart';
import 'package:wecord/features/local_search/indexed_chat_cache.dart';
import 'package:wecord/features/local_search/local_search_index.dart';

Future<ChatCache?> openChatCache(LocalCipher cipher) async {
  final store = SealedKeyValueStore(
    await IndexedDbKeyValueStore.open('wecord_chat_cache'),
    cipher,
  );
  final index = LocalSearchIndex(
    SealedKeyValueStore(
      await IndexedDbKeyValueStore.open('wecord_search_index'),
      cipher,
    ),
  );
  // What an earlier version stored in the clear is encrypted in the
  // background (see the phone and Mac cache).
  unawaited(
    Future<void>.delayed(const Duration(seconds: 3), () async {
      try {
        await store.migrateLegacy(
          pause: () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      } catch (_) {
        // Tried again at the next start.
      }
    }),
  );
  return IndexedChatCache(KeyValueChatCache(store), index);
}
