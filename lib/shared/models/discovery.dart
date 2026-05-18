enum DiscoveryResultType {
  contact,
  group,
  circle,
  circleChannel,
  message;

  factory DiscoveryResultType.fromJson(
    String value, {
    required bool hasConversationId,
  }) {
    return switch (value) {
      'contact' => DiscoveryResultType.contact,
      'group' => DiscoveryResultType.group,
      'circle' => DiscoveryResultType.circle,
      'circle_channel' => DiscoveryResultType.circleChannel,
      'message' => DiscoveryResultType.message,
      _ when hasConversationId => DiscoveryResultType.message,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Unknown discovery result type',
      ),
    };
  }

  String toJson() {
    return switch (this) {
      DiscoveryResultType.contact => 'contact',
      DiscoveryResultType.group => 'group',
      DiscoveryResultType.circle => 'circle',
      DiscoveryResultType.circleChannel => 'circle_channel',
      DiscoveryResultType.message => 'message',
    };
  }
}

class DiscoveryResult {
  const DiscoveryResult({
    required this.type,
    required this.id,
    required this.title,
    required this.rank,
    this.subtitle,
    this.conversationId,
    this.circleId,
    this.channelId,
  });

  factory DiscoveryResult.fromJson(Map<String, dynamic> json) {
    final conversationId = json['conversation_id'] as String?;
    return DiscoveryResult(
      type: DiscoveryResultType.fromJson(
        json['result_type'] as String,
        hasConversationId: conversationId != null,
      ),
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      conversationId: conversationId,
      circleId: json['circle_id'] as String?,
      channelId: json['channel_id'] as String?,
      rank: (json['rank'] as num?)?.toDouble() ?? 0,
    );
  }

  final DiscoveryResultType type;
  final String id;
  final String title;
  final String? subtitle;
  final String? conversationId;
  final String? circleId;
  final String? channelId;
  final double rank;
}
