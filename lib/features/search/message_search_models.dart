import 'package:wecord/features/search/search_query.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

/// Where a search looks.
sealed class MessageSearchScope {
  const MessageSearchScope();

  Map<String, Object?> toJson();
}

class EverywhereScope extends MessageSearchScope {
  const EverywhereScope();

  @override
  Map<String, Object?> toJson() => const {'type': 'everywhere'};

  @override
  bool operator ==(Object other) => other is EverywhereScope;

  @override
  int get hashCode => 0;
}

/// A circle's channels and their threads.
class CircleScope extends MessageSearchScope {
  const CircleScope({required this.circleId, this.name});

  final String circleId;
  final String? name;

  @override
  Map<String, Object?> toJson() => {'type': 'circle', 'id': circleId};

  @override
  bool operator ==(Object other) =>
      other is CircleScope && other.circleId == circleId;

  @override
  int get hashCode => circleId.hashCode;
}

/// One conversation (a chat, group or channel) and its threads.
class ConversationScope extends MessageSearchScope {
  const ConversationScope({
    required this.conversationId,
    this.title,
    this.type,
  });

  final String conversationId;
  final String? title;
  final ConversationType? type;

  @override
  Map<String, Object?> toJson() => {
    'type': 'conversation',
    'id': conversationId,
  };

  @override
  bool operator ==(Object other) =>
      other is ConversationScope && other.conversationId == conversationId;

  @override
  int get hashCode => conversationId.hashCode;
}

enum MessageSearchSort {
  newest,
  oldest,
  relevance;

  String get label => switch (this) {
    MessageSearchSort.newest => trIn('search', 'Newest'),
    MessageSearchSort.oldest => tr('Oldest'),
    MessageSearchSort.relevance => tr('Most relevant'),
  };
}

/// The filters of a search, resolved to ids.
class MessageSearchFilters {
  const MessageSearchFilters({
    this.fromIds = const [],
    this.mentionIds = const [],
    this.placeIds = const [],
    this.has = const {},
    this.before,
    this.after,
    this.during,
    this.pinned,
  });

  final List<String> fromIds;
  final List<String> mentionIds;
  final List<String> placeIds;
  final Set<SearchHas> has;
  final SearchDate? before;
  final SearchDate? after;
  final SearchDate? during;
  final bool? pinned;

  /// Days become instants on this device: before a day is before it starts,
  /// after a day is after it ends, during is the day itself.
  Map<String, Object?> toJson() {
    final before = this.before;
    final after = this.after;
    final during = this.during;
    return {
      if (fromIds.isNotEmpty) 'from': fromIds,
      if (mentionIds.isNotEmpty) 'mentions': mentionIds,
      if (placeIds.isNotEmpty) 'in': placeIds,
      if (has.isNotEmpty) 'has': [for (final kind in has) kind.name],
      if (before != null || during != null)
        'before': _earliest(
          before?.startLocal,
          during?.endLocal,
        )!.toUtc().toIso8601String(),
      if (after != null || during != null)
        'after': _latest(
          after?.endLocal,
          during?.startLocal,
        )!.toUtc().toIso8601String(),
      if (pinned != null) 'pinned': pinned,
    };
  }

  static DateTime? _earliest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }

  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

/// A search for messages.
class MessageSearchRequest {
  const MessageSearchRequest({
    required this.text,
    this.filters = const MessageSearchFilters(),
    this.scope = const EverywhereScope(),
    this.sort = MessageSearchSort.newest,
    this.pageSize = 25,
    this.cursor,
  });

  /// Free text: words, "phrases" and -exclusions.
  final String text;
  final MessageSearchFilters filters;
  final MessageSearchScope scope;
  final MessageSearchSort sort;
  final int pageSize;

  /// The next_cursor of the previous page, or null for the first.
  final Map<String, dynamic>? cursor;

  MessageSearchRequest nextPage(Map<String, dynamic> cursor) {
    return MessageSearchRequest(
      text: text,
      filters: filters,
      scope: scope,
      sort: sort,
      pageSize: pageSize,
      cursor: cursor,
    );
  }

  Map<String, dynamic> toParams() => {
    'query': text,
    'filters': filters.toJson(),
    'scope': scope.toJson(),
    'sort': sort.name,
    'max_results': pageSize,
    'cursor': cursor,
  };
}

/// Where a result lives: a direct chat, group, channel or thread.
class SearchPlace {
  const SearchPlace({
    required this.id,
    required this.type,
    this.title,
    this.avatarUrl,
    this.directUserId,
    this.circleId,
    this.circleName,
    this.channelKind,
    this.parentConversationId,
    this.parentTitle,
  });

  factory SearchPlace.fromJson(Map<String, dynamic> json) {
    return SearchPlace(
      id: json['id'] as String,
      type: ConversationType.fromJson(json['type'] as String),
      title: json['title'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      directUserId: json['direct_user_id'] as String?,
      circleId: json['circle_id'] as String?,
      circleName: json['circle_name'] as String?,
      channelKind: json['channel_kind'] as String?,
      parentConversationId: json['parent_conversation_id'] as String?,
      parentTitle: json['parent_title'] as String?,
    );
  }

  final String id;
  final ConversationType type;
  final String? title;
  final String? avatarUrl;
  final String? directUserId;
  final String? circleId;
  final String? circleName;
  final String? channelKind;
  final String? parentConversationId;
  final String? parentTitle;

  /// "# general", "Design team", "Ada", or a thread's title.
  String get label {
    final title = this.title?.trim();
    final name = title == null || title.isEmpty ? null : title;
    return switch (type) {
      ConversationType.channel => '# ${name ?? tr('channel')}',
      ConversationType.thread => name ?? tr('Thread'),
      ConversationType.direct ||
      ConversationType.group => name ?? tr('Conversation'),
    };
  }

  /// The circle (and parent channel of a thread) under the label.
  String? get subtitle {
    final parts = <String>[
      if (type == ConversationType.thread &&
          parentTitle?.trim().isNotEmpty == true)
        circleId == null ? parentTitle!.trim() : '# ${parentTitle!.trim()}',
      if (circleName?.trim().isNotEmpty == true) circleName!.trim(),
    ];
    if (parts.isEmpty) {
      return type == ConversationType.group ? tr('Group') : null;
    }
    return parts.join(' · ');
  }

  /// How `in:` names this place in the search box.
  String get filterValue {
    final title = this.title?.trim();
    return title == null || title.isEmpty ? id : title;
  }

  ConversationSummary toSummary() {
    return ConversationSummary(
      id: id,
      type: type,
      unreadCount: 0,
      title: type == ConversationType.channel ? title : label,
      avatarUrl: avatarUrl,
      circleId: circleId,
      directUserId: directUserId,
      parentConversationId: parentConversationId,
      parentTitle: parentTitle,
    );
  }
}

/// A person for `from:` and `mentions:`.
class SearchPerson {
  const SearchPerson({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory SearchPerson.fromJson(Map<String, dynamic> json) {
    return SearchPerson(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
}

/// One matching message.
class SearchHit {
  const SearchHit({
    required this.message,
    required this.senderName,
    this.senderAvatarUrl,
    this.place,
    this.rank = 0,
    this.pinned = false,
  });

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    final place = json['conversation'];
    return SearchHit(
      message: ChatMessage(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        type: MessageType.fromJson(json['type'] as String? ?? 'text'),
        body: json['body'] as String? ?? '',
        attachment: (json['attachment'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.parse(json['created_at'] as String),
        editedAt: json['edited_at'] == null
            ? null
            : DateTime.parse(json['edited_at'] as String),
        isPinned: json['pinned'] as bool? ?? false,
      ),
      senderName: json['sender_name'] as String? ?? '',
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      place: place is Map ? SearchPlace.fromJson(place.cast()) : null,
      rank: (json['rank'] as num?)?.toDouble() ?? 0,
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  final ChatMessage message;
  final String senderName;
  final String? senderAvatarUrl;
  final SearchPlace? place;
  final double rank;
  final bool pinned;

  String get id => message.id;
  String get conversationId => message.conversationId;
}

/// A page of results.
class SearchPage {
  const SearchPage({
    required this.hits,
    this.nextCursor,
    this.total,
    this.totalCapped = false,
    this.conversationCounts = const {},
  });

  factory SearchPage.fromJson(Map<String, dynamic> json) {
    final counts = <String, int>{};
    for (final row in json['conversations'] as List<dynamic>? ?? const []) {
      final map = (row as Map).cast<String, dynamic>();
      counts[map['conversation_id'] as String] = (map['count'] as num).toInt();
    }
    final cursor = json['next_cursor'];
    return SearchPage(
      hits: [
        for (final row in json['results'] as List<dynamic>? ?? const [])
          SearchHit.fromJson((row as Map).cast<String, dynamic>()),
      ],
      nextCursor: cursor is Map ? cursor.cast<String, dynamic>() : null,
      total: (json['total'] as num?)?.toInt(),
      totalCapped: json['total_capped'] as bool? ?? false,
      conversationCounts: counts,
    );
  }

  final List<SearchHit> hits;
  final Map<String, dynamic>? nextCursor;

  /// Matches (up to 1000) on the first page; null on later pages.
  final int? total;

  /// More than [total] matched.
  final bool totalCapped;

  /// Matches per conversation (first page only).
  final Map<String, int> conversationCounts;
}

/// The messages around a result.
class SearchContext {
  const SearchContext({this.before = const [], this.after = const []});

  factory SearchContext.fromJson(Map<String, dynamic> json) {
    List<SearchHit> read(String key) => [
      for (final row in json[key] as List<dynamic>? ?? const [])
        SearchHit.fromJson((row as Map).cast<String, dynamic>()),
    ];
    return SearchContext(before: read('before'), after: read('after'));
  }

  final List<SearchHit> before;
  final List<SearchHit> after;
}
