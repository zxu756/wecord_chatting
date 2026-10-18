import 'package:wecord/shared/l10n/l10n.dart';

/// How people get into a circle (`circles.join_mode`).
enum CircleJoinMode {
  /// Anyone who reaches a join path joins at once.
  open('open'),

  /// Every path makes a request that a moderator approves or denies.
  apply('apply'),

  /// Not from Discover; invite links and member invites still work.
  inviteOnly('invite_only');

  const CircleJoinMode(this.key);

  final String key;

  static CircleJoinMode fromKey(Object? key) => values.firstWhere(
    (mode) => mode.key == key,
    orElse: () => CircleJoinMode.open,
  );

  String get label => switch (this) {
    CircleJoinMode.open => trIn('join mode', 'Open'),
    CircleJoinMode.apply => tr('Apply to join'),
    CircleJoinMode.inviteOnly => tr('Invite only'),
  };

  String get description => switch (this) {
    CircleJoinMode.open => tr(
      'Anyone with an invite link, or from Explore if the circle is public, '
      'joins at once.',
    ),
    CircleJoinMode.apply => tr(
      'Everyone who tries to join sends a request. Members who can remove '
      'members approve or deny it.',
    ),
    CircleJoinMode.inviteOnly => tr(
      'Nobody joins from Explore. Invite links and invites from members '
      'still work.',
    ),
  };
}

/// The most questions a circle asks.
const joinQuestionLimit = 5;

/// The longest answer to a question.
const joinAnswerMaxLength = 500;

/// One question a circle asks people who want to join.
class JoinQuestion {
  const JoinQuestion({
    required this.id,
    required this.kind,
    required this.prompt,
    this.options = const [],
    this.required = true,
  });

  factory JoinQuestion.fromJson(Map<String, dynamic> json) {
    return JoinQuestion(
      id: json['id'] as String? ?? '',
      kind: json['kind'] == 'choice'
          ? JoinQuestionKind.choice
          : JoinQuestionKind.text,
      prompt: json['prompt'] as String? ?? '',
      options: [
        for (final option in (json['options'] as List? ?? const []))
          option as String,
      ],
      required: json['required'] != false,
    );
  }

  /// Empty for a question that is not saved yet.
  final String id;
  final JoinQuestionKind kind;
  final String prompt;

  /// The choices of a [JoinQuestionKind.choice] question.
  final List<String> options;
  final bool required;

  JoinQuestion copyWith({
    JoinQuestionKind? kind,
    String? prompt,
    List<String>? options,
    bool? required,
  }) {
    return JoinQuestion(
      id: id,
      kind: kind ?? this.kind,
      prompt: prompt ?? this.prompt,
      options: options ?? this.options,
      required: required ?? this.required,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'kind': kind.key,
    'prompt': prompt.trim(),
    if (kind == JoinQuestionKind.choice)
      'options': [
        for (final option in options)
          if (option.trim().isNotEmpty) option.trim(),
      ],
    'required': required,
  };

  /// Whether the question can be saved as it is.
  bool get isValid {
    if (prompt.trim().isEmpty || prompt.trim().length > 200) {
      return false;
    }
    if (kind == JoinQuestionKind.text) {
      return true;
    }
    final cleaned = {
      for (final option in options)
        if (option.trim().isNotEmpty) option.trim(),
    };
    return cleaned.length >= 2 && cleaned.length <= 8;
  }
}

enum JoinQuestionKind {
  text('text'),
  choice('choice');

  const JoinQuestionKind(this.key);

  final String key;
}

/// A circle's join mode and questions, for its settings.
class CircleJoinSettings {
  const CircleJoinSettings({
    this.mode = CircleJoinMode.open,
    this.questions = const [],
  });

  factory CircleJoinSettings.fromJson(Map<String, dynamic> json) {
    return CircleJoinSettings(
      mode: CircleJoinMode.fromKey(json['join_mode']),
      questions: [
        for (final question in (json['questions'] as List? ?? const []))
          JoinQuestion.fromJson(Map<String, dynamic>.from(question as Map)),
      ],
    );
  }

  final CircleJoinMode mode;
  final List<JoinQuestion> questions;
}

enum JoinRequestStatus {
  pending('pending'),
  approved('approved'),
  denied('denied');

  const JoinRequestStatus(this.key);

  final String key;

  static JoinRequestStatus fromKey(Object? key) => values.firstWhere(
    (status) => status.key == key,
    orElse: () => JoinRequestStatus.pending,
  );
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// The person's latest request to a circle.
class JoinRequestInfo {
  const JoinRequestInfo({
    required this.id,
    required this.status,
    required this.createdAt,
    this.decidedAt,
    this.note,
    this.invited = false,
  });

  factory JoinRequestInfo.fromJson(Map<String, dynamic> json) {
    return JoinRequestInfo(
      id: json['id'] as String,
      status: JoinRequestStatus.fromKey(json['status']),
      createdAt: _time(json['created_at']) ?? DateTime.now().toUtc(),
      decidedAt: _time(json['decided_at']),
      note: json['note'] as String?,
      invited: json['invited'] == true,
    );
  }

  final String id;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;

  /// What the moderator said when they denied it.
  final String? note;

  /// A member invited the person (rather than the person asking).
  final bool invited;
}

/// Where the current user stands in joining a circle
/// (`get_circle_join_state`).
class CircleJoinState {
  const CircleJoinState({
    required this.circleId,
    this.mode = CircleJoinMode.open,
    this.closed = false,
    this.isMember = false,
    this.skipReview = false,
    this.questions = const [],
    this.request,
    this.retryAt,
  });

  factory CircleJoinState.fromJson(Map<String, dynamic> json) {
    final request = json['request'];
    return CircleJoinState(
      circleId: json['circle_id'] as String? ?? '',
      mode: CircleJoinMode.fromKey(json['join_mode']),
      closed: json['closed'] == true,
      isMember: json['is_member'] == true,
      skipReview: json['skip_review'] == true,
      questions: [
        for (final question in (json['questions'] as List? ?? const []))
          JoinQuestion.fromJson(Map<String, dynamic>.from(question as Map)),
      ],
      request: request is Map
          ? JoinRequestInfo.fromJson(Map<String, dynamic>.from(request))
          : null,
      retryAt: _time(json['retry_at']),
    );
  }

  final String circleId;
  final CircleJoinMode mode;

  /// The circle takes no new members (taken down).
  final bool closed;
  final bool isMember;

  /// The invite in hand skips review.
  final bool skipReview;

  /// What to answer: only while a request must be made.
  final List<JoinQuestion> questions;
  final JoinRequestInfo? request;

  /// When a denied person may apply again, while that is in the future.
  final DateTime? retryAt;

  /// Joining makes a request, not a membership.
  bool get needsReview =>
      mode == CircleJoinMode.apply && !isMember && !skipReview;

  bool get isPending =>
      !isMember && request?.status == JoinRequestStatus.pending;

  bool get isDenied => !isMember && request?.status == JoinRequestStatus.denied;

  /// A denied person who has to wait before asking again.
  bool canRetryAt(DateTime now) => retryAt == null || !retryAt!.isAfter(now);
}

/// One answer on a request: the question as it read, and what was said.
class JoinAnswerEntry {
  const JoinAnswerEntry({required this.prompt, required this.answer});

  factory JoinAnswerEntry.fromJson(Map<String, dynamic> json) {
    return JoinAnswerEntry(
      prompt: json['prompt'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
    );
  }

  final String prompt;
  final String answer;
}

/// A request waiting for a moderator (`list_join_requests`).
class PendingJoinRequest {
  const PendingJoinRequest({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.username,
    required this.createdAt,
    this.avatarUrl,
    this.accountCreatedAt,
    this.answers = const [],
    this.invitedByName,
  });

  factory PendingJoinRequest.fromJson(Map<String, dynamic> json) {
    return PendingJoinRequest(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      accountCreatedAt: _time(json['account_created_at']),
      createdAt: _time(json['created_at']) ?? DateTime.now().toUtc(),
      answers: [
        for (final answer in (json['answers'] as List? ?? const []))
          JoinAnswerEntry.fromJson(Map<String, dynamic>.from(answer as Map)),
      ],
      invitedByName: json['invited_by_name'] as String?,
    );
  }

  final String id;
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final DateTime? accountCreatedAt;
  final DateTime createdAt;
  final List<JoinAnswerEntry> answers;

  /// Set when a member invited the person.
  final String? invitedByName;

  String get name => displayName.trim().isEmpty ? username : displayName;
}

/// One of the current user's own requests, for Notifications
/// (`list_my_join_requests`).
class MyJoinRequest {
  const MyJoinRequest({
    required this.id,
    required this.circleId,
    required this.circleName,
    required this.status,
    required this.createdAt,
    this.circleAvatarUrl,
    this.decidedAt,
    this.note,
    this.invited = false,
    this.isMember = false,
  });

  factory MyJoinRequest.fromJson(Map<String, dynamic> json) {
    return MyJoinRequest(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      circleName: json['circle_name'] as String? ?? '',
      circleAvatarUrl: json['circle_avatar_url'] as String?,
      status: JoinRequestStatus.fromKey(json['status']),
      createdAt: _time(json['created_at']) ?? DateTime.now().toUtc(),
      decidedAt: _time(json['decided_at']),
      note: json['note'] as String?,
      invited: json['invited'] == true,
      isMember: json['is_member'] == true,
    );
  }

  final String id;
  final String circleId;
  final String circleName;
  final String? circleAvatarUrl;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? note;
  final bool invited;
  final bool isMember;

  /// When it happened: the decision, or the request while it waits.
  DateTime get at => decidedAt ?? createdAt;
}

/// The answers to a circle's questions, as the join functions take them.
List<Map<String, String>> joinAnswersJson(Map<String, String> answers) => [
  for (final entry in answers.entries)
    if (entry.value.trim().isNotEmpty)
      {'question_id': entry.key, 'answer': entry.value.trim()},
];

/// Whether [answers] (by question id) answer every required question.
bool joinAnswersComplete(
  List<JoinQuestion> questions,
  Map<String, String> answers,
) {
  for (final question in questions) {
    final answer = (answers[question.id] ?? '').trim();
    if (question.required && answer.isEmpty) {
      return false;
    }
    if (answer.length > joinAnswerMaxLength) {
      return false;
    }
  }
  return true;
}
