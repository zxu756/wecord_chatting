/// A poll message's question and options (`messages.attachment` of a
/// `poll` message).
class PollAttachment {
  const PollAttachment({
    required this.question,
    required this.options,
    this.multi = false,
    this.endsAt,
  });

  /// Parses a poll attachment; null for anything else.
  static PollAttachment? maybeFromJson(Object? json) {
    if (json is! Map || json['kind'] != 'poll') {
      return null;
    }
    final rawOptions = json['options'];
    final options = <PollOption>[
      if (rawOptions is List)
        for (final option in rawOptions)
          if (option is Map &&
              option['id'] is String &&
              option['text'] is String)
            PollOption(
              id: option['id'] as String,
              text: option['text'] as String,
            ),
    ];
    final endsAt = json['ends_at'];
    return PollAttachment(
      question: json['question'] as String? ?? '',
      options: options,
      multi: json['multi'] == true,
      endsAt: endsAt is String ? DateTime.parse(endsAt).toUtc() : null,
    );
  }

  static const maxQuestionLength = 300;
  static const maxOptionLength = 100;
  static const minOptions = 2;
  static const maxOptions = 10;

  final String question;
  final List<PollOption> options;

  /// Voters may pick several options.
  final bool multi;

  /// When voting ends; null for polls without an end.
  final DateTime? endsAt;

  bool hasEndedAt(DateTime now) {
    final endsAt = this.endsAt;
    return endsAt != null && !endsAt.isAfter(now);
  }
}

class PollOption {
  const PollOption({required this.id, required this.text});

  final String id;
  final String text;
}

/// The `poll_results` computed field of a poll message.
class PollResults {
  const PollResults({
    this.counts = const <String, int>{},
    this.totalVoters = 0,
    this.myVotes = const <String>{},
    this.closed = false,
  });

  static PollResults? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final rawCounts = json['counts'];
    final rawMine = json['my_votes'];
    return PollResults(
      counts: {
        if (rawCounts is Map)
          for (final MapEntry(:key, :value) in rawCounts.entries)
            if (key is String && value is num) key: value.toInt(),
      },
      totalVoters: (json['total_voters'] as num?)?.toInt() ?? 0,
      myVotes: {
        if (rawMine is List)
          for (final id in rawMine)
            if (id is String) id,
      },
      closed: json['closed'] == true,
    );
  }

  /// Votes per option id.
  final Map<String, int> counts;

  /// People who voted, each counted once however many options they chose.
  final int totalVoters;

  /// The options the current user chose.
  final Set<String> myVotes;

  /// Ended, ended early or deleted: no more votes.
  final bool closed;

  int countFor(String optionId) => counts[optionId] ?? 0;

  /// [optionId]'s share of the voters, 0 to 1.
  double shareOf(String optionId) {
    if (totalVoters <= 0) {
      return 0;
    }
    return (countFor(optionId) / totalVoters).clamp(0, 1).toDouble();
  }
}

/// How a poll reads in one-line previews and notifications.
String pollPreviewText(String question) {
  final trimmed = question.trim();
  return trimmed.isEmpty ? '📊 Poll' : '📊 Poll: $trimmed';
}

/// The poll durations offered when creating a poll, in hours (null for no
/// end).
const pollDurationHours = <int?>[null, 1, 4, 8, 24, 72, 168];

/// `No end`, `1 hour`, `3 days`, ...
String pollDurationLabel(int? hours) {
  if (hours == null) {
    return 'No end';
  }
  if (hours % 24 == 0) {
    final days = hours ~/ 24;
    return days == 1 ? '1 day' : '$days days';
  }
  return hours == 1 ? '1 hour' : '$hours hours';
}

/// "Ends in 5m", "Ends in 3h", "Ends in 2d", or "Ending" in its last
/// minute.
String pollEndsInLabel(DateTime endsAt, {DateTime? now}) {
  final left = endsAt.difference((now ?? DateTime.now()).toUtc());
  if (left.inMinutes < 1) {
    return 'Ending';
  }
  if (left.inHours < 1) {
    return 'Ends in ${left.inMinutes}m';
  }
  if (left.inDays < 1) {
    return 'Ends in ${left.inHours}h';
  }
  return 'Ends in ${left.inDays}d';
}
