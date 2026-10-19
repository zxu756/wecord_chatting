// The daily digest (roadmap F3, migrations 202610230500 to 202610230540): the
// card in Notifications and the settings behind it.

/// One chat's part of a digest.
class DigestChatSummary {
  const DigestChatSummary({
    required this.conversationId,
    required this.title,
    required this.summary,
    this.circleName,
    this.messageCount = 0,
  });

  factory DigestChatSummary.fromJson(Map<String, dynamic> json) {
    return DigestChatSummary(
      conversationId: json['conversation_id'] as String,
      title: (json['title'] as String?)?.trim() ?? '',
      circleName: (json['circle_name'] as String?)?.trim(),
      summary: (json['summary'] as String?)?.trim() ?? '',
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String conversationId;

  /// The group's name, or the channel's.
  final String title;

  /// The circle a channel belongs to.
  final String? circleName;

  /// Bullet points, one per line, each starting with "- ".
  final String summary;

  /// How many messages the digest covered in this chat.
  final int messageCount;

  /// The summary as its lines, without the "- " bullets or blank lines.
  List<String> get bullets => [
    for (final line in summary.split('\n'))
      if (line.trim().isNotEmpty) line.replaceFirst(RegExp(r'^\s*-\s*'), ''),
  ];
}

/// One day's digest, as Notifications lists it.
class AiDigest {
  const AiDigest({
    required this.id,
    required this.localDate,
    required this.createdAt,
    required this.items,
    this.readAt,
  });

  factory AiDigest.fromJson(Map<String, dynamic> json) {
    return AiDigest(
      id: json['id'] as String,
      localDate: DateTime.parse(json['local_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
      items: [
        for (final item in (json['items'] as List<dynamic>? ?? const []))
          DigestChatSummary.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  final String id;

  /// The day on the person's own clock.
  final DateTime localDate;
  final DateTime createdAt;
  final DateTime? readAt;
  final List<DigestChatSummary> items;

  bool get isUnread => readAt == null;

  int get messageCount => items.fold(0, (sum, item) => sum + item.messageCount);
}

/// A chat the person follows.
class DigestSubscription {
  const DigestSubscription({
    required this.conversationId,
    required this.title,
    this.circleName,
  });

  factory DigestSubscription.fromJson(Map<String, dynamic> json) {
    return DigestSubscription(
      conversationId: json['conversation_id'] as String,
      title: (json['title'] as String?)?.trim() ?? '',
      circleName: (json['circle_name'] as String?)?.trim(),
    );
  }

  final String conversationId;
  final String title;
  final String? circleName;
}

/// Settings -> AI -> Daily digest.
class DigestSettings {
  const DigestSettings({
    this.enabled = true,
    this.hour = 8,
    this.minute = 0,
    this.language = 'en',
    this.timeZone = 'UTC',
    this.maxSubscriptions = 10,
    this.subscriptions = const [],
  });

  factory DigestSettings.fromJson(Map<String, dynamic> json) {
    final time = (json['deliver_at'] as String? ?? '08:00').split(':');
    return DigestSettings(
      enabled: json['enabled'] as bool? ?? true,
      hour: int.tryParse(time.first) ?? 8,
      minute: time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0,
      language: json['language'] as String? ?? 'en',
      timeZone: json['time_zone'] as String? ?? 'UTC',
      maxSubscriptions: (json['max_subscriptions'] as num?)?.toInt() ?? 10,
      subscriptions: [
        for (final item
            in (json['subscriptions'] as List<dynamic>? ?? const []))
          DigestSubscription.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  final bool enabled;
  final int hour;
  final int minute;

  /// What the summaries are written in: 'en' or 'zh'.
  final String language;

  /// The zone the digest runs in: the one this person's devices reported.
  final String timeZone;
  final int maxSubscriptions;
  final List<DigestSubscription> subscriptions;

  bool follows(String conversationId) => subscriptions.any(
    (subscription) => subscription.conversationId == conversationId,
  );

  bool get isFull => subscriptions.length >= maxSubscriptions;
}

/// Following one more chat than the server allows (SQLSTATE 54000).
class DigestLimitReached implements Exception {
  const DigestLimitReached();

  @override
  String toString() => 'DigestLimitReached';
}
