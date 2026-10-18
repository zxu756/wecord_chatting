import 'package:wecord/shared/l10n/l10n.dart';

/// The name people mention to ask the assistant.
const assistantMention = '@WeCord AI';

/// What the assistant may read besides the message that mentions it and the
/// message that one replies to. The requester chooses; it is written after
/// the mention as `/20` or `/100`, and the database reads it back from the
/// text (migration 202610230410), so the syntax is the same everywhere:
///
///     @WeCord AI summarize the plan        this message (and its reply target)
///     @WeCord AI /20 what did we decide?   plus the last 20 messages
///     @WeCord AI /100 list the to-dos      plus the last 100 messages
enum AssistantRange {
  thisMessage(0),
  last20(20),
  last100(100);

  const AssistantRange(this.count);

  /// Messages before the question that the assistant reads.
  final int count;

  /// The text after the mention that asks for this range.
  String get suffix => count == 0 ? '' : ' /$count';

  String get label => switch (this) {
    AssistantRange.thisMessage => tr('This message'),
    AssistantRange.last20 => tr('Last 20 messages'),
    AssistantRange.last100 => tr('Last 100 messages'),
  };
}

final RegExp _mention = RegExp(
  r'(^|[^A-Za-z0-9_])@wecord[ _]?ai(?![A-Za-z0-9_])(\s+/(20|100)(?![A-Za-z0-9_]))?',
  caseSensitive: false,
);

/// Whether [body] mentions the assistant.
bool mentionsAssistant(String body) => _mention.hasMatch(body);

/// The range [body] asks for, or null when it does not mention the assistant.
AssistantRange? assistantRangeOf(String body) {
  final match = _mention.firstMatch(body);
  if (match == null) {
    return null;
  }
  return switch (match.group(3)) {
    '20' => AssistantRange.last20,
    '100' => AssistantRange.last100,
    _ => AssistantRange.thisMessage,
  };
}

/// The message to send for [question] with the chosen [range].
String assistantMessageText(AssistantRange range, String question) =>
    '$assistantMention${range.suffix} ${question.trim()}'.trim();

/// A chat message that sits under the last few minutes of an own request:
/// the assistant has had time to answer, or to fail.
const assistantStatusWindow = Duration(minutes: 15);
