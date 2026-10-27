import 'dart:async';

import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/draft_reply/draft_reply_repository.dart';

/// A [DraftReplyRepository] for tests: replies are set up front, calls
/// recorded.
class FakeDraftReplyRepository implements DraftReplyRepository {
  var replies = const [
    'Sure, Friday works!',
    'Yes, I can do Friday. What time were you thinking?',
    'Can we make it Saturday instead?',
  ];

  /// Thrown by [suggest] when set.
  Object? error;

  /// Holds the next answer until completed (for the loading state).
  Completer<void>? gate;

  final calls = <({String conversationId, String? intent, AiLanguage? lang})>[];

  @override
  Future<List<String>> suggest({
    required String conversationId,
    String? intent,
    AiLanguage? language,
  }) async {
    calls.add((conversationId: conversationId, intent: intent, lang: language));
    await gate?.future;
    if (error case final error?) {
      throw error;
    }
    return replies;
  }
}
