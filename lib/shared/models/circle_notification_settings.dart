/// Which channel messages in a circle may notify the current user.
enum CircleNotificationLevel {
  all,
  mentions,
  none;

  factory CircleNotificationLevel.fromJson(String? value) {
    return switch (value) {
      'mentions' => CircleNotificationLevel.mentions,
      'none' => CircleNotificationLevel.none,
      _ => CircleNotificationLevel.all,
    };
  }

  String toJson() => name;
}

/// "Until I turn it back on" is stored as a mute this far ahead, the same
/// convention as muting a single conversation.
const circleMuteIndefinitely = Duration(days: 36500);

class CircleNotificationSettings {
  const CircleNotificationSettings({
    required this.circleId,
    this.level = CircleNotificationLevel.all,
    this.mutedUntil,
  });

  factory CircleNotificationSettings.fromJson(Map<String, dynamic> json) {
    final mutedUntil = json['muted_until'] as String?;
    return CircleNotificationSettings(
      circleId: json['circle_id'] as String,
      level: CircleNotificationLevel.fromJson(json['level'] as String?),
      mutedUntil: mutedUntil == null
          ? null
          : DateTime.parse(mutedUntil).toUtc(),
    );
  }

  final String circleId;
  final CircleNotificationLevel level;
  final DateTime? mutedUntil;

  bool isMutedAt(DateTime now) => isCircleMutedAt(mutedUntil, now);

  /// Muted with no end the user would reasonably reach (see
  /// [circleMuteIndefinitely]).
  bool isMutedIndefinitelyAt(DateTime now) {
    final mutedUntil = this.mutedUntil;
    return mutedUntil != null &&
        mutedUntil.isAfter(now.add(const Duration(days: 3650)));
  }
}

bool isCircleMutedAt(DateTime? mutedUntil, DateTime now) {
  return mutedUntil != null && mutedUntil.isAfter(now);
}
