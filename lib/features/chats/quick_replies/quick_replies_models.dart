// Quick replies (A8): phrases kept to send with a slash, and the away
// auto-reply.

/// A person keeps at most this many (the database enforces it too).
const maxQuickReplies = 50;

/// The longest shortcut, in characters.
const maxQuickReplyShortcutLength = 32;

/// The longest phrase, in characters.
const maxQuickReplyBodyLength = 2000;

/// The longest away message, in characters.
const maxAwayMessageLength = 500;

/// One phrase: typing `/shortcut` offers [body].
class QuickReply {
  const QuickReply({
    required this.id,
    required this.shortcut,
    required this.body,
  });

  factory QuickReply.fromJson(Map<String, dynamic> json) {
    return QuickReply(
      id: json['id'] as String,
      shortcut: json['shortcut'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }

  final String id;

  /// Lower case, without the slash, no spaces.
  final String shortcut;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is QuickReply &&
      other.id == id &&
      other.shortcut == shortcut &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, shortcut, body);
}

/// What is wrong with a phrase being saved.
enum QuickReplyProblem {
  /// The shortcut is empty, too long, or holds a space or a slash.
  shortcut,

  /// The phrase is empty or too long.
  body,

  /// Another phrase already has the shortcut.
  taken,

  /// The person already keeps [maxQuickReplies].
  limit,
}

class QuickReplyException implements Exception {
  const QuickReplyException(this.problem);

  final QuickReplyProblem problem;

  @override
  String toString() => 'QuickReplyException($problem)';
}

/// [raw] as it is stored: trimmed, lower case, without a leading slash.
String normalizeQuickReplyShortcut(String raw) {
  return raw.trim().replaceFirst(RegExp(r'^/+'), '').toLowerCase();
}

/// The first thing wrong with the shortcut and phrase, or null.
QuickReplyProblem? checkQuickReply(String shortcut, String body) {
  final key = normalizeQuickReplyShortcut(shortcut);
  final length = key.runes.length;
  if (length == 0 ||
      length > maxQuickReplyShortcutLength ||
      RegExp(r'[\s/]').hasMatch(key)) {
    return QuickReplyProblem.shortcut;
  }
  final bodyLength = body.trim().runes.length;
  if (bodyLength == 0 || bodyLength > maxQuickReplyBodyLength) {
    return QuickReplyProblem.body;
  }
  return null;
}

/// A `/` followed by what is being typed, with nothing else in the box: no
/// space, no second slash. Wider than the command names, which are letters:
/// a shortcut can hold digits, dashes and any script.
final _quickQueryPattern = RegExp(r'^/([^\s/]*)$');

/// The lower-cased text after a leading `/` when the box holds only that,
/// or null.
String? slashQueryAt(String text) {
  return _quickQueryPattern.firstMatch(text)?.group(1)?.toLowerCase();
}

/// The phrases whose shortcut starts with [query], in the order kept.
List<QuickReply> quickReplyCandidates(
  String query,
  List<QuickReply> replies,
) {
  final normalized = query.toLowerCase();
  return [
    for (final reply in replies)
      if (reply.shortcut.startsWith(normalized)) reply,
  ];
}

/// The phrase [text] names in full (`/addr`), or null: what sending the
/// box does when it holds just a shortcut.
QuickReply? quickReplyNamedBy(String text, List<QuickReply> replies) {
  final query = slashQueryAt(text.trim());
  if (query == null || query.isEmpty) {
    return null;
  }
  for (final reply in replies) {
    if (reply.shortcut == query) {
      return reply;
    }
  }
  return null;
}

/// The away auto-reply of the signed-in person.
class AwayReply {
  const AwayReply({
    this.enabled = false,
    this.message = '',
    this.until,
    this.duringQuietHours = false,
  });

  factory AwayReply.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AwayReply();
    }
    final until = json['away_until'];
    return AwayReply(
      enabled: json['away_enabled'] == true,
      message: json['away_message'] as String? ?? '',
      until: until is String ? DateTime.tryParse(until)?.toLocal() : null,
      duringQuietHours: json['away_in_quiet_hours'] == true,
    );
  }

  final bool enabled;
  final String message;

  /// When it turns itself off; null: until switched off by hand.
  final DateTime? until;

  /// Also answers while quiet hours (A4) are on, even with the switch off.
  final bool duringQuietHours;

  /// Whether the switch is on at [now] (it ends by itself at [until]).
  bool isOn(DateTime now) {
    if (!enabled || message.trim().isEmpty) {
      return false;
    }
    final end = until;
    return end == null || end.isAfter(now);
  }

  AwayReply copyWith({
    bool? enabled,
    String? message,
    DateTime? until,
    bool clearUntil = false,
    bool? duringQuietHours,
  }) {
    return AwayReply(
      enabled: enabled ?? this.enabled,
      message: message ?? this.message,
      until: clearUntil ? null : until ?? this.until,
      duringQuietHours: duringQuietHours ?? this.duringQuietHours,
    );
  }
}
