import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/indexed_db_store.dart';

Future<ChatCache?> openChatCache() async {
  return KeyValueChatCache(
    await IndexedDbKeyValueStore.open('wecord_chat_cache'),
  );
}
