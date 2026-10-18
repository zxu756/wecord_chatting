import 'package:wecord/shared/models/message.dart';

/// One earlier version of an edited message: what it said before an edit.
/// Version 1 is the text as it was first sent.
class MessageEditVersion {
  const MessageEditVersion({
    required this.version,
    required this.body,
    required this.editedAt,
    this.mentions = const <MessageMention>[],
  });

  factory MessageEditVersion.fromJson(Map<String, dynamic> json) {
    final mentions = json['mentions'];
    return MessageEditVersion(
      version: (json['version'] as num?)?.toInt() ?? 1,
      body: json['body'] as String? ?? '',
      editedAt:
          DateTime.tryParse(json['edited_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      mentions: [
        if (mentions is List)
          for (final mention in mentions)
            if (mention is Map<String, dynamic>)
              MessageMention.fromJson(mention),
      ],
    );
  }

  final int version;
  final String body;

  /// When this version was written: the message's send time for version 1,
  /// otherwise the time of the edit that made it.
  final DateTime editedAt;
  final List<MessageMention> mentions;

  /// The text as it was first sent.
  bool get isOriginal => version == 1;
}
