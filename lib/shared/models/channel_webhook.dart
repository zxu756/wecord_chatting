/// A channel webhook as `list_channel_webhooks` returns it (never its
/// token).
class ChannelWebhook {
  const ChannelWebhook({
    required this.id,
    required this.channelId,
    required this.name,
    required this.createdAt,
    this.avatarUrl,
    this.createdById,
    this.creatorName,
    this.lastUsedAt,
  });

  factory ChannelWebhook.fromJson(Map<String, dynamic> json) {
    final lastUsedAt = json['last_used_at'];
    return ChannelWebhook(
      id: json['id'] as String,
      channelId: json['channel_id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      createdById: json['created_by'] as String?,
      creatorName: json['creator_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      lastUsedAt: lastUsedAt is String
          ? DateTime.parse(lastUsedAt).toUtc()
          : null,
    );
  }

  static const maxNameLength = 80;

  final String id;
  final String channelId;
  final String name;
  final String? avatarUrl;
  final String? createdById;

  /// The creator's name in the circle when the list was loaded.
  final String? creatorName;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// A webhook with its secret token, returned only when it is created or its
/// token is regenerated.
class ChannelWebhookSecret {
  const ChannelWebhookSecret({required this.webhook, required this.token});

  factory ChannelWebhookSecret.fromJson(Map<String, dynamic> json) {
    return ChannelWebhookSecret(
      webhook: ChannelWebhook.fromJson(json),
      token: json['token'] as String,
    );
  }

  final ChannelWebhook webhook;
  final String token;

  /// The URL external services post to.
  String urlFor(Uri supabaseUrl) => channelWebhookUrl(supabaseUrl, this);
}

/// `<SUPABASE_URL>/functions/v1/webhook/<id>/<token>`.
String channelWebhookUrl(Uri supabaseUrl, ChannelWebhookSecret secret) {
  final base = supabaseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
  return '$base/functions/v1/webhook/${secret.webhook.id}/${secret.token}';
}
