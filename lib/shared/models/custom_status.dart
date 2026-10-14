import 'package:wecord/shared/l10n/l10n.dart';

/// A user's custom status: an emoji and/or short text shown under their
/// name, until [expiresAt] when set.
class CustomStatus {
  const CustomStatus({this.emoji, this.text, this.expiresAt});

  /// Parses a `custom_status` value; null, non-objects and empty statuses
  /// give null.
  static CustomStatus? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final emoji = _nonEmpty(json['emoji']);
    final text = _nonEmpty(json['text']);
    if (emoji == null && text == null) {
      return null;
    }
    final expiresAt = json['expires_at'];
    return CustomStatus(
      emoji: emoji,
      text: text,
      expiresAt: expiresAt is String ? DateTime.parse(expiresAt).toUtc() : null,
    );
  }

  static const maxTextLength = 64;

  final String? emoji;
  final String? text;
  final DateTime? expiresAt;

  /// The server never returns expired statuses, but a loaded one can expire
  /// while it is on screen.
  bool isActiveAt(DateTime now) {
    final expiresAt = this.expiresAt;
    return expiresAt == null || expiresAt.isAfter(now);
  }

  /// Emoji and text joined for display, e.g. "🎯 Focusing".
  String get label {
    return [emoji, text].whereType<String>().join(' ');
  }

  Map<String, dynamic> toJson() {
    return {
      'emoji': emoji,
      'text': text,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    };
  }
}

/// [status] when it is still active at [now] (default: the current time),
/// otherwise null.
CustomStatus? activeCustomStatus(CustomStatus? status, {DateTime? now}) {
  if (status == null) {
    return null;
  }
  return status.isActiveAt((now ?? DateTime.now()).toUtc()) ? status : null;
}

/// How long a newly set status lasts.
enum CustomStatusDuration {
  thirtyMinutes('30 minutes'),
  fourHours('4 hours'),
  today('Today'),
  never("Don't clear");

  const CustomStatusDuration(this._label);

  final String _label;

  String get label => tr(_label);

  /// When a status set at [now] expires, or null to keep it. "Today" ends
  /// at the next local midnight.
  DateTime? expiresAt(DateTime now) {
    final local = now.toLocal();
    return switch (this) {
      CustomStatusDuration.thirtyMinutes =>
        local.add(const Duration(minutes: 30)).toUtc(),
      CustomStatusDuration.fourHours =>
        local.add(const Duration(hours: 4)).toUtc(),
      CustomStatusDuration.today => DateTime(
        local.year,
        local.month,
        local.day + 1,
      ).toUtc(),
      CustomStatusDuration.never => null,
    };
  }
}

String? _nonEmpty(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
