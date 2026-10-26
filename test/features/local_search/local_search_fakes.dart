import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_data/aes_gcm_local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/sealed_key_value_store.dart';
import 'package:wecord/features/local_search/indexed_chat_cache.dart';
import 'package:wecord/features/local_search/local_message_search.dart';
import 'package:wecord/features/local_search/local_search_index.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/search_query.dart';

const meId = 'me';
const userBart = 'u-bart';
const userAda = 'u-ada';

Map<String, dynamic> profile(String id, String username, String name) => {
  'id': id,
  'username': username,
  'display_name': name,
  'bio': '',
  'created_at': '2026-01-01T00:00:00.000Z',
  'updated_at': '2026-01-01T00:00:00.000Z',
};

/// A message row as the server sent it and the cache keeps it.
Map<String, dynamic> messageRow(
  String id,
  String chat,
  String body, {
  String sender = userBart,
  int minute = 0,
  int day = 1,
  String type = 'text',
  Map<String, dynamic>? attachment,
  String? recalledAt,
  String? reviewState,
  String? expiresAt,
  bool pinned = false,
  List<Map<String, dynamic>>? mentions,
}) {
  return {
    'id': id,
    'conversation_id': chat,
    'sender_id': sender,
    'type': type,
    'body': body,
    // Midday on that day where the test runs, so day filters do not depend on its time zone.
    'created_at': DateTime(2026, 10, day, 12, minute).toUtc().toIso8601String(),
    'sender': sender == userBart
        ? profile(userBart, 'bart', 'Bart')
        : profile(userAda, 'ada', 'Ada'),
    'attachment': ?attachment,
    'recalled_at': ?recalledAt,
    'review_state': ?reviewState,
    'expires_at': ?expiresAt,
    'is_pinned': pinned,
    'mentions': ?mentions,
  };
}

Map<String, dynamic> conversationRow(
  String id,
  String title, {
  String type = 'group',
  String? circleId,
  String? parent,
}) {
  return {
    'id': id,
    'type': type,
    'title': title,
    'unread_count': 0,
    'circle_id': ?circleId,
    'parent_conversation_id': ?parent,
  };
}

MessageSearchRequest request(
  String input, {
  MessageSearchScope scope = const EverywhereScope(),
  MessageSearchSort sort = MessageSearchSort.newest,
  MessageSearchFilters filters = const MessageSearchFilters(),
  int pageSize = 25,
  Map<String, dynamic>? cursor,
}) {
  return MessageSearchRequest(
    text: ParsedSearchQuery.parse(input).text,
    filters: filters,
    scope: scope,
    sort: sort,
    pageSize: pageSize,
    cursor: cursor,
  );
}

/// The offline cache with its search index, all in memory, sealed with a key
/// of its own.
class LocalSearchWorld {
  LocalSearchWorld({
    this.excluded = const {},
    DateTime? now,
    LocalSearchWorld? reopening,
  }) : clockNow = now ?? DateTime.utc(2026, 10, 27, 12) {
    // Reopening: the same stored values and key, a search that has read
    // nothing yet (the first search after the app starts).
    cipher = reopening?.cipher ?? AesGcmLocalCipher(MemoryKeyStore());
    inner = reopening?.inner ?? KeyValueChatCache.memory();
    indexStore = reopening?.indexStore ?? MemoryKeyValueStore();
    index = LocalSearchIndex(SealedKeyValueStore(indexStore, cipher));
    cache = IndexedChatCache(inner, index, clock: () => clockNow);
    search = LocalMessageSearch(
      cache: cache,
      index: index,
      userId: () => meId,
      excludedConversations: () => excluded,
      clock: () => clockNow,
      pause: () async {},
    );
  }

  late final LocalCipher cipher;
  DateTime clockNow;
  late final KeyValueChatCache inner;
  late final MemoryKeyValueStore indexStore;
  late final LocalSearchIndex index;
  late final IndexedChatCache cache;
  late final LocalMessageSearch search;
  Set<String> excluded;

  Future<void> cacheChat(
    String chat,
    List<Map<String, dynamic>> rows,
  ) => cache.writeMessages(meId, chat, rows);

  /// The ids found by [input].
  Future<List<String>> ids(
    String input, {
    MessageSearchScope scope = const EverywhereScope(),
    MessageSearchSort sort = MessageSearchSort.newest,
    MessageSearchFilters filters = const MessageSearchFilters(),
  }) async {
    final page = await search.search(
      request(input, scope: scope, sort: sort, filters: filters),
    );
    return [for (final hit in page.hits) hit.id];
  }
}
