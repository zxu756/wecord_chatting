import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Everything a new poll can be, beyond a question and its answers.
class PollDraft {
  const PollDraft({
    required this.question,
    required this.options,
    this.multi = false,
    this.durationHours,
    this.closesAt,
    this.quizCorrectIndex,
    this.quizExplanation = '',
    this.anonymous = false,
    this.allowAddOptions = false,
  });

  final String question;
  final List<String> options;
  final bool multi;

  /// Voting ends this many hours from now; [closesAt] wins when both are set.
  final int? durationHours;

  /// Voting ends at this moment (up to 30 days ahead).
  final DateTime? closesAt;

  /// 0-based index of the right answer; null for a poll that is not a quiz.
  final int? quizCorrectIndex;
  final String quizExplanation;

  /// Counts show, who voted does not.
  final bool anonymous;

  /// Any member can add an answer.
  final bool allowAddOptions;

  bool get isQuiz => quizCorrectIndex != null;

  /// Whether sending needs the newer poll features (older servers and the
  /// plain path know none of them).
  bool get usesNewFeatures =>
      isQuiz || anonymous || allowAddOptions || closesAt != null;
}

/// The poll features past what [ChatsRepository] offers: quizzes,
/// anonymous votes, a chosen deadline and answers added by members.
abstract interface class PollsRepository {
  Future<void> createPoll(String conversationId, PollDraft draft);

  /// Adds an answer to a poll that lets members do so; returns its id.
  Future<String> addOption(String messageId, String text);
}

class SupabasePollsRepository implements PollsRepository {
  const SupabasePollsRepository(this._client, this._chats);

  final SupabaseClient _client;
  final ChatsRepository _chats;

  @override
  Future<void> createPoll(String conversationId, PollDraft draft) async {
    final Object? id;
    try {
      id = await _client.rpc<Object?>(
        'create_poll',
        params: {
          'target_conversation_id': conversationId,
          'question': draft.question.trim(),
          'options': [for (final option in draft.options) option.trim()],
          'multi': draft.multi,
          'duration_hours': draft.durationHours,
          'quiz_correct_option': draft.quizCorrectIndex == null
              ? null
              : draft.quizCorrectIndex! + 1,
          'quiz_explanation': draft.quizExplanation.trim().isEmpty
              ? null
              : draft.quizExplanation.trim(),
          'anonymous': draft.anonymous,
          'allow_add_options': draft.allowAddOptions,
          'closes_at': draft.closesAt?.toUtc().toIso8601String(),
        },
      );
    } on PostgrestException catch (error) {
      throw SlowmodeException.fromPostgrest(error) ??
          SendRefusedException.fromPostgrest(error) ??
          error;
    }
    final sender = _chats;
    if (id is String && sender is MediaMessageSender) {
      await (sender as MediaMessageSender).notifyMessageSent(id);
    }
  }

  @override
  Future<String> addOption(String messageId, String text) async {
    final id = await _client.rpc<Object?>(
      'add_poll_option',
      params: {'target_message_id': messageId, 'option_text': text.trim()},
    );
    return id as String;
  }
}

class _UninitializedPollsRepository implements PollsRepository {
  const _UninitializedPollsRepository();

  @override
  Future<void> createPoll(String conversationId, PollDraft draft) {
    throw StateError('Supabase must be initialized before creating polls.');
  }

  @override
  Future<String> addOption(String messageId, String text) {
    throw StateError('Supabase must be initialized before adding options.');
  }
}

final pollsRepositoryProvider = Provider<PollsRepository>((ref) {
  try {
    return SupabasePollsRepository(
      ref.watch(supabaseClientProvider),
      ref.watch(chatsRepositoryProvider),
    );
  } on ProviderException {
    return const _UninitializedPollsRepository();
  }
});
