import 'package:wecord/features/chats/time_tokens/time_phrase_parser.dart';

/// Whether an extracted item becomes a task or a chat event.
enum ExtractedKind {
  task,
  event;

  static ExtractedKind fromJson(Object? value) =>
      value == 'event' ? ExtractedKind.event : ExtractedKind.task;
}

/// One to-do or event the `ai` function found in a chat (extract_actions), or
/// that WeCord AI listed in an answer. The person confirms and edits these
/// before anything is created.
class ExtractedAction {
  const ExtractedAction({
    required this.title,
    this.assignees = const [],
    this.due,
    this.dueHasTime = false,
    this.dueText,
    this.kind = ExtractedKind.task,
    this.sourceMessageId,
  });

  /// Reads an item as the `ai` function writes it (and as it is kept in
  /// messages.ai_reply): `{title, assignee, due, due_has_time, due_text,
  /// kind, source_message_id}`. Null when it has no title.
  static ExtractedAction? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final title = json['title'];
    if (title is! String || title.trim().isEmpty) {
      return null;
    }
    final assignee = json['assignee'];
    final due = json['due'];
    return ExtractedAction(
      title: title.trim(),
      assignees: [if (assignee is String && assignee.isNotEmpty) assignee],
      due: due is String ? DateTime.tryParse(due)?.toLocal() : null,
      dueHasTime: json['due_has_time'] == true,
      dueText: json['due_text'] is String && json['due_text'] != ''
          ? json['due_text'] as String
          : null,
      kind: ExtractedKind.fromJson(json['kind']),
      sourceMessageId: json['source_message_id'] as String?,
    );
  }

  final String title;

  /// Members of the conversation to do it; the server only ever suggests
  /// one, and the person may add more.
  final List<String> assignees;

  /// In the local time zone.
  final DateTime? due;

  /// The due moment has a time of day (otherwise only the date counts).
  final bool dueHasTime;

  /// The words in the chat the date came from ("tomorrow 8pm").
  final String? dueText;
  final ExtractedKind kind;
  final String? sourceMessageId;

  /// An event needs a time of day.
  bool get canBeEvent => due != null && dueHasTime;

  ExtractedAction copyWith({
    String? title,
    List<String>? assignees,
    Object? due = _unset,
    bool? dueHasTime,
    ExtractedKind? kind,
  }) {
    return ExtractedAction(
      title: title ?? this.title,
      assignees: assignees ?? this.assignees,
      due: identical(due, _unset) ? this.due : due as DateTime?,
      dueHasTime: dueHasTime ?? this.dueHasTime,
      dueText: dueText,
      kind: kind ?? this.kind,
      sourceMessageId: sourceMessageId,
    );
  }

  /// The item with its date read by the app's own time phrase parser (the
  /// one behind time tokens) when [dueText] holds a phrase it understands:
  /// the same words give the same moment here as in the composer. Without a
  /// phrase, or one in the past, the server's date stays. An event without a
  /// time of day is a task.
  ExtractedAction refined(DateTime now) {
    var result = this;
    final text = dueText;
    if (text != null) {
      final phrases = findTimePhrases(text, now: now);
      if (phrases.isNotEmpty) {
        final time = phrases.first.time;
        final midnight = time.hour == 0 && time.minute == 0;
        result = copyWith(due: time, dueHasTime: !midnight);
      }
    }
    if (result.kind == ExtractedKind.event && !result.canBeEvent) {
      result = result.copyWith(kind: ExtractedKind.task);
    }
    return result;
  }
}

const Object _unset = Object();
