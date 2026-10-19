import 'package:flutter/foundation.dart';
import 'package:wecord/features/search/message_search_models.dart';

/// Why Ask AI did not give an answer even though nothing went wrong.
enum AskNotFoundReason {
  /// No message matched the question's words.
  noMatches,

  /// Messages matched but did not answer the question.
  notInMessages,

  /// A message it used was recalled or removed while it was reading.
  sourcesChanged,

  /// The question had nothing to look for.
  noKeywords;

  static AskNotFoundReason fromCode(Object? code) => switch (code) {
    'not_in_messages' => AskNotFoundReason.notInMessages,
    'sources_changed' => AskNotFoundReason.sourcesChanged,
    'no_keywords' => AskNotFoundReason.noKeywords,
    _ => AskNotFoundReason.noMatches,
  };
}

/// A message an answer is based on.
@immutable
class AskSource {
  const AskSource({
    required this.n,
    required this.messageId,
    required this.conversationId,
    required this.sender,
    required this.snippet,
    required this.createdAt,
    this.place,
  });

  /// The number the answer cites it by ("[1]").
  final int n;
  final String messageId;
  final String conversationId;
  final String sender;

  /// The start of the message as one line.
  final String snippet;
  final DateTime createdAt;

  /// Where it was sent, to open it there.
  final SearchPlace? place;

  /// Null when the server's row is not a source.
  static AskSource? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final messageId = json['message_id'];
    final conversationId = json['conversation_id'];
    final created = DateTime.tryParse('${json['created_at']}');
    if (messageId is! String || conversationId is! String || created == null) {
      return null;
    }
    final place = json['place'];
    return AskSource(
      n: (json['n'] as num?)?.toInt() ?? 0,
      messageId: messageId,
      conversationId: conversationId,
      sender: (json['sender'] as String?)?.trim() ?? '',
      snippet: (json['snippet'] as String?)?.trim() ?? '',
      createdAt: created.toLocal(),
      place: place is Map && place['id'] is String
          ? SearchPlace.fromJson(place.cast<String, dynamic>())
          : null,
    );
  }
}

/// The answer to a question about the person's chats.
@immutable
class AskAnswer {
  const AskAnswer({
    required this.found,
    this.answer,
    this.sources = const [],
    this.reason,
  });

  /// Nothing was found: [reason] says why.
  const AskAnswer.notFound(AskNotFoundReason this.reason)
    : found = false,
      answer = null,
      sources = const [];

  final bool found;

  /// The answer, with citations like "[1]" that match [sources].
  final String? answer;
  final List<AskSource> sources;
  final AskNotFoundReason? reason;

  /// An answer without a source is never shown.
  bool get isUsable => found && (answer?.trim().isNotEmpty ?? false);

  static AskAnswer fromJson(Map<Object?, Object?> json) {
    final sources = <AskSource>[
      if (json['sources'] is List)
        for (final source in json['sources'] as List)
          ?AskSource.maybeFromJson(source),
    ];
    final answer = (json['answer'] as String?)?.trim();
    if (json['found'] == true &&
        answer != null &&
        answer.isNotEmpty &&
        sources.isNotEmpty) {
      return AskAnswer(found: true, answer: answer, sources: sources);
    }
    return AskAnswer.notFound(AskNotFoundReason.fromCode(json['reason']));
  }
}
