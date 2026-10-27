import 'dart:async';

import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_search/local_search_index.dart';
import 'package:wecord/features/local_search/search_text.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/search_query.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

/// Message search over what this device has cached (L3), for when there is
/// no connection. It answers the same questions as the server's search
/// (words, "phrases", -exclusions, `from:`, `in:`, `has:`, dates, `pinned:`,
/// where it looks, how results are sorted) with the same result types, but
/// only over the messages the offline cache holds.
class LocalMessageSearch {
  LocalMessageSearch({
    required this.cache,
    required this.index,
    required this.userId,
    this.excludedConversations,
    DateTime Function()? clock,
    Future<void> Function()? pause,
  }) : _clock = clock ?? DateTime.now,
       _pause = pause ?? _yieldToApp;

  /// The offline cache the results are read from.
  final ChatCache cache;
  final LocalSearchIndex index;

  /// The signed-in user's id, or null.
  final String? Function() userId;

  /// Conversations a search across places must not return, whatever they
  /// hold: the chats the person locked (G2), and the ones whose privacy
  /// setting keeps their content out of search and AI (G6, when it lands).
  /// A search inside one conversation is left alone, as on the server.
  final Set<String> Function()? excludedConversations;

  final DateTime Function() _clock;
  final Future<void> Function() _pause;

  static Future<void> _yieldToApp() => Future<void>.delayed(Duration.zero);

  /// How many messages are looked at before the app gets a turn.
  static const _slice = 2000;

  Future<SearchPage> search(MessageSearchRequest request) async {
    final user = userId();
    if (user == null) {
      return const SearchPage(hits: [], total: 0, offline: true);
    }
    final parsed = ParsedSearchQuery.parse(request.text);
    final include = <String>[];
    final exclude = <String>[];
    for (final token in parsed.textTokens) {
      final folded = foldSearchText(token.value.trim());
      if (folded.isEmpty) {
        continue;
      }
      (token.negated ? exclude : include).add(folded);
    }
    final filters = request.filters.toJson();
    final fromIds = {...?(filters['from'] as List<String>?)};
    final mentionIds = {...?(filters['mentions'] as List<String>?)};
    final placeIds = {...?(filters['in'] as List<String>?)};
    final has = request.filters.has;
    final wantMask = has.fold<int>(0, (mask, kind) => mask | hasBit(kind));
    final before = DateTime.tryParse('${filters['before'] ?? ''}');
    final after = DateTime.tryParse('${filters['after'] ?? ''}');
    final beforeMs = before?.millisecondsSinceEpoch;
    final afterMs = after?.millisecondsSinceEpoch;
    final pinned = request.filters.pinned;

    final conversations = await _conversationRows(user);
    final scoped = _scopeConversationIds(request.scope, conversations);
    final excluded = request.scope is ConversationScope
        ? const <String>{}
        : (excludedConversations?.call() ?? const <String>{});

    final loaded = await index.load(user, pause: _pause);
    final matches = <_Match>[];
    var looked = 0;
    for (final MapEntry(key: conversationId, value: indexed) in loaded.entries) {
      if (excluded.contains(conversationId) ||
          (scoped != null && !scoped.contains(conversationId)) ||
          (placeIds.isNotEmpty && !placeIds.contains(conversationId))) {
        continue;
      }
      for (final message in indexed.messages) {
        if (++looked % _slice == 0) {
          await _pause();
        }
        if ((fromIds.isNotEmpty && !fromIds.contains(message.senderId)) ||
            (wantMask != 0 && message.hasMask & wantMask != wantMask) ||
            (pinned != null && message.pinned != pinned) ||
            (beforeMs != null && message.createdAtMs >= beforeMs) ||
            (afterMs != null && message.createdAtMs <= afterMs)) {
          continue;
        }
        if (mentionIds.isNotEmpty &&
            !message.mentionIds.any(mentionIds.contains)) {
          continue;
        }
        final folded = message.folded;
        var score = 0;
        var all = true;
        for (final term in include) {
          final count = _occurrences(folded, term);
          if (count == 0) {
            all = false;
            break;
          }
          score += count;
        }
        if (!all || exclude.any(folded.contains)) {
          continue;
        }
        matches.add(_Match(conversationId, message, score));
      }
    }

    matches.sort(switch (request.sort) {
      MessageSearchSort.newest => (a, b) => _newest(a, b),
      MessageSearchSort.oldest => (a, b) => _newest(b, a),
      MessageSearchSort.relevance => (a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : _newest(a, b);
      },
    });

    final offset = ((request.cursor?['local_offset']) as num?)?.toInt() ?? 0;
    final end = offset + request.pageSize;
    final page = matches.sublist(
      offset.clamp(0, matches.length),
      end.clamp(0, matches.length),
    );
    final counts = <String, int>{};
    if (offset == 0) {
      for (final match in matches) {
        counts[match.conversationId] = (counts[match.conversationId] ?? 0) + 1;
      }
    }
    final hits = await _hits(user, page, conversations);
    return SearchPage(
      hits: hits,
      nextCursor: end < matches.length ? {'local_offset': end} : null,
      total: offset == 0 ? matches.length : null,
      conversationCounts: counts,
      offline: true,
    );
  }

  static int _newest(_Match a, _Match b) {
    final byTime = b.message.createdAtMs.compareTo(a.message.createdAtMs);
    return byTime != 0 ? byTime : b.message.id.compareTo(a.message.id);
  }

  static int _occurrences(String text, String term) {
    var count = 0;
    var from = 0;
    while (true) {
      final at = text.indexOf(term, from);
      if (at < 0) {
        return count;
      }
      count++;
      from = at + term.length;
    }
  }

  Future<List<Map<String, dynamic>>> _conversationRows(String user) async {
    try {
      return await cache.readConversations(user) ?? const [];
    } on Object {
      return const [];
    }
  }

  /// The conversations a scope covers, or null for all of them.
  Set<String>? _scopeConversationIds(
    MessageSearchScope scope,
    List<Map<String, dynamic>> conversations,
  ) {
    return switch (scope) {
      EverywhereScope() => null,
      ConversationScope(:final conversationId) => {
        conversationId,
        for (final row in conversations)
          if (row['parent_conversation_id'] == conversationId &&
              row['id'] is String)
            row['id'] as String,
      },
      CircleScope(:final circleId) => {
        for (final row in conversations)
          if (row['circle_id'] == circleId && row['id'] is String)
            row['id'] as String,
      },
    };
  }

  Future<List<SearchHit>> _hits(
    String user,
    List<_Match> page,
    List<Map<String, dynamic>> conversations,
  ) async {
    final places = {
      for (final row in conversations)
        if (row['id'] is String) row['id'] as String: _placeOf(row),
    };
    final rowsByConversation = <String, Map<String, Map<String, dynamic>>>{};
    final hits = <SearchHit>[];
    for (final match in page) {
      final rows = rowsByConversation[match.conversationId] ??= {
        for (final row in await cache.readMessages(user, match.conversationId))
          if (row['id'] is String) row['id'] as String: row,
      };
      final row = rows[match.message.id];
      if (row == null) {
        continue;
      }
      final hit = _hitOf(
        row,
        places[match.conversationId],
        (await index.load(user))[match.conversationId]?.people,
        score: match.score.toDouble(),
      );
      if (hit != null) {
        hits.add(hit);
      }
    }
    return hits;
  }

  SearchHit? _hitOf(
    Map<String, dynamic> row,
    SearchPlace? place,
    Map<String, IndexedPerson>? people, {
    double score = 0,
  }) {
    try {
      final message = ChatMessage.fromJson(row);
      final person = people?[message.senderId];
      final name =
          message.webhookName ??
          message.senderNickname ??
          message.sender?.displayName ??
          person?.displayName ??
          '';
      return SearchHit(
        message: message,
        senderName: name,
        senderAvatarUrl:
            message.senderCircleAvatarUrl ?? message.sender?.avatarUrl,
        place: place,
        rank: score,
        pinned: message.isPinned,
      );
    } on Object {
      return null;
    }
  }

  static SearchPlace? _placeOf(Map<String, dynamic> row) {
    try {
      return SearchPlace(
        id: row['id'] as String,
        type: ConversationType.fromJson(row['type'] as String),
        title: row['title'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        directUserId: row['direct_user_id'] as String?,
        circleId: row['circle_id'] as String?,
        parentConversationId: row['parent_conversation_id'] as String?,
        parentTitle: row['parent_title'] as String?,
      );
    } on Object {
      return null;
    }
  }

  /// The messages just before and after [messageId] in the cache.
  Future<SearchContext> context(
    String messageId, {
    int before = 1,
    int after = 1,
  }) async {
    final user = userId();
    if (user == null) {
      return const SearchContext();
    }
    final loaded = await index.load(user, pause: _pause);
    final now = _clock().toUtc();
    for (final conversationId in loaded.keys) {
      if (!loaded[conversationId]!.messages.any((m) => m.id == messageId)) {
        continue;
      }
      final rows = [
        for (final row in await cache.readMessages(user, conversationId))
          if (!rowIsRetired(row, now)) row,
      ];
      final at = rows.indexWhere((row) => row['id'] == messageId);
      if (at < 0) {
        break;
      }
      final people = loaded[conversationId]?.people;
      List<SearchHit> take(Iterable<Map<String, dynamic>> part) => [
        for (final row in part) ?_hitOf(row, null, people),
      ];
      return SearchContext(
        before: take(rows.sublist((at - before).clamp(0, at), at)),
        after: take(rows.sublist(at + 1, (at + 1 + after).clamp(0, rows.length))),
      );
    }
    return const SearchContext();
  }

  /// People who wrote cached messages in [scope], for `from:`.
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async {
    final user = userId();
    if (user == null) {
      return const [];
    }
    final scoped = _scopeConversationIds(scope, await _conversationRows(user));
    final needle = foldSearchText(prefix.trim().replaceFirst(RegExp('^@'), ''));
    final found = <String, SearchPerson>{};
    for (final MapEntry(key: conversationId, value: indexed)
        in (await index.load(user, pause: _pause)).entries) {
      if (scoped != null && !scoped.contains(conversationId)) {
        continue;
      }
      for (final MapEntry(key: id, value: person) in indexed.people.entries) {
        if (found.containsKey(id)) {
          continue;
        }
        if (needle.isEmpty ||
            foldSearchText(person.username).contains(needle) ||
            foldSearchText(person.displayName).contains(needle)) {
          found[id] = SearchPerson(
            id: id,
            username: person.username,
            displayName: person.displayName,
          );
        }
      }
    }
    return found.values.take(limit).toList();
  }

  /// Cached conversations in [scope] named like [prefix], for `in:`.
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async {
    final user = userId();
    if (user == null) {
      return const [];
    }
    final rows = await _conversationRows(user);
    final scoped = _scopeConversationIds(scope, rows);
    final needle = foldSearchText(prefix.trim().replaceFirst(RegExp('^#'), ''));
    return [
      for (final row in rows)
        if (row['id'] is String &&
            (scoped == null || scoped.contains(row['id'])) &&
            (needle.isEmpty ||
                foldSearchText('${row['title'] ?? ''}').contains(needle)))
          ?_placeOf(row),
    ].take(limit).toList();
  }
}

class _Match {
  const _Match(this.conversationId, this.message, this.score);

  final String conversationId;
  final IndexedMessage message;
  final int score;
}
