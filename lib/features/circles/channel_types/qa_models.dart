import 'package:wecord/shared/l10n/l10n.dart';

/// What a Q&A post page knows about the question (`get_qa_post_state`): whether
/// it is solved, which message is the accepted answer and whether the current
/// person may change that.
class QaPostState {
  const QaPostState({
    required this.threadId,
    required this.channelId,
    required this.circleId,
    this.solved = false,
    this.solvedAt,
    this.answerMessageId,
    this.openingMessageId,
    this.canMark = false,
  });

  factory QaPostState.fromJson(Map<String, dynamic> json) {
    return QaPostState(
      threadId: json['thread_id'] as String,
      channelId: json['channel_id'] as String? ?? '',
      circleId: json['circle_id'] as String? ?? '',
      solved: json['solved'] == true,
      solvedAt: switch (json['solved_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      answerMessageId: json['answer_message_id'] as String?,
      openingMessageId: json['opening_message_id'] as String?,
      canMark: json['can_mark'] == true,
    );
  }

  final String threadId;
  final String channelId;
  final String circleId;

  /// The question was marked solved, with or without an accepted answer.
  final bool solved;
  final DateTime? solvedAt;

  /// The accepted answer, when one was picked and it still counts.
  final String? answerMessageId;

  /// The question itself (the first message), which cannot be its own answer.
  final String? openingMessageId;

  /// The current person may mark the question solved, pick the answer or
  /// reopen it: the asker, or a moderator of the channel.
  final bool canMark;

  /// [messageId] is the accepted answer.
  bool isAnswer(String messageId) => answerMessageId == messageId;
}

/// Which questions a Q&A channel lists.
enum QaStatusFilter {
  all('all', 'All'),
  unsolved('unsolved', 'Unsolved'),
  solved('solved', 'Solved');

  const QaStatusFilter(this.value, this._label);

  /// The `filter_status` value of `list_qa_posts`.
  final String value;
  final String _label;

  String get label => tr(_label);
}
