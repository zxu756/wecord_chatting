import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// How many messages one merged forward holds.
const maxMergedForwardMessages = 100;

/// What a preview line of the card is about.
enum ChatHistoryLineKind {
  text,
  image,
  video,
  file,
  voice,
  history,
  contact;

  static ChatHistoryLineKind fromJson(Object? value) {
    for (final kind in values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return ChatHistoryLineKind.text;
  }
}

/// One of the first lines of a chat history, "Ada: Meet at 7?".
class ChatHistoryLine {
  const ChatHistoryLine({
    required this.name,
    required this.kind,
    required this.text,
  });

  factory ChatHistoryLine.fromJson(Map<String, dynamic> json) {
    return ChatHistoryLine(
      name: json['name'] as String? ?? '',
      kind: ChatHistoryLineKind.fromJson(json['kind']),
      text: json['text'] as String? ?? '',
    );
  }

  final String name;
  final ChatHistoryLineKind kind;

  /// The text of a text message, the file name of a file.
  final String text;

  /// What follows the name: the text, or "[Photo]" and the like.
  String get summary => chatHistoryKindSummary(kind, text);
}

/// "[Photo]", "[File] plan.pdf" or the text itself, for [kind].
String chatHistoryKindSummary(ChatHistoryLineKind kind, String text) {
  return switch (kind) {
    ChatHistoryLineKind.text => text,
    ChatHistoryLineKind.image => tr('[Photo]'),
    ChatHistoryLineKind.video => tr('[Video]'),
    ChatHistoryLineKind.file =>
      text.isEmpty ? tr('[File]') : tr('[File] {name}', {'name': text}),
    ChatHistoryLineKind.voice => tr('[Voice message]'),
    ChatHistoryLineKind.history => tr('[Chat history]'),
    ChatHistoryLineKind.contact => tr('[Contact card]'),
  };
}

/// The card of a merged forward in a chat (the attachment of the message):
/// its title, how many messages it holds and the first lines. The messages
/// themselves are a [ChatHistoryBundle], read when the card is opened.
class ChatHistoryCard {
  const ChatHistoryCard({
    required this.title,
    required this.count,
    required this.preview,
  });

  static const kind = 'chat_history';

  /// The card of [attachment], or null when it is not a chat history.
  static ChatHistoryCard? maybeFromAttachment(
    Map<String, dynamic>? attachment,
  ) {
    if (attachment == null || attachment['kind'] != kind) {
      return null;
    }
    final preview = attachment['preview'];
    return ChatHistoryCard(
      title: (attachment['title'] as String?)?.trim().isNotEmpty == true
          ? (attachment['title'] as String).trim()
          : tr('Chat'),
      count: (attachment['count'] as num?)?.toInt() ?? 0,
      preview: [
        if (preview is List)
          for (final line in preview)
            if (line is Map<String, dynamic>) ChatHistoryLine.fromJson(line),
      ],
    );
  }

  /// The name of the conversation it came from.
  final String title;
  final int count;
  final List<ChatHistoryLine> preview;

  /// "Chat history: Ada".
  String get heading => tr('Chat history: {name}', {'name': title});
}

extension ChatHistoryMessage on ChatMessage {
  /// The chat history this message is, or null.
  ChatHistoryCard? get chatHistoryCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return ChatHistoryCard.maybeFromAttachment(attachment);
  }
}

/// A chat history inside another one (one level deep).
class BundleNested {
  const BundleNested({
    required this.title,
    required this.count,
    required this.items,
  });

  final String title;
  final int count;
  final List<BundleItem> items;
}

/// One message of a chat history, as it was when it was forwarded.
class BundleItem {
  const BundleItem({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    required this.type,
    required this.body,
    this.senderAvatar,
    this.attachment,
    this.nested,
  });

  factory BundleItem.fromJson(Map<String, dynamic> json) {
    final nested = json['nested'];
    return BundleItem(
      messageId: json['message_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? '',
      senderAvatar: json['sender_avatar'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      type: _typeOf(json['type']),
      body: json['body'] as String? ?? '',
      attachment: json['attachment'] is Map
          ? Map<String, dynamic>.from(json['attachment'] as Map)
          : null,
      nested: nested is Map<String, dynamic> ? _nestedFrom(nested) : null,
    );
  }

  static MessageType _typeOf(Object? value) {
    try {
      return MessageType.fromJson(value as String);
    } on Object {
      return MessageType.text;
    }
  }

  static BundleNested _nestedFrom(Map<String, dynamic> json) {
    final items = json['items'];
    return BundleNested(
      title: json['title'] as String? ?? tr('Chat'),
      count: (json['count'] as num?)?.toInt() ?? 0,
      items: [
        if (items is List)
          for (final item in items)
            if (item is Map<String, dynamic>) BundleItem.fromJson(item),
      ],
    );
  }

  final String messageId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final DateTime createdAt;
  final MessageType type;
  final String body;
  final Map<String, dynamic>? attachment;

  /// For a chat history that was forwarded inside this one, what it held.
  final BundleNested? nested;

  ImageAttachment? get image {
    final value = attachment;
    if (type != MessageType.image || value == null) {
      return null;
    }
    try {
      return ImageAttachment.fromJson(value);
    } on Object {
      return null;
    }
  }

  FileAttachment? get file {
    if (type != MessageType.file) {
      return null;
    }
    return FileAttachment.maybeFromJson(attachment);
  }

  VoiceAttachment? get voice {
    final value = attachment;
    if (type != MessageType.voice || value == null) {
      return null;
    }
    try {
      return VoiceAttachment.fromJson(value);
    } on Object {
      return null;
    }
  }

  /// A chat history forwarded inside this one: its title and count, and
  /// [nested] when its messages came along.
  ChatHistoryCard? get history {
    if (type != MessageType.text) {
      return null;
    }
    return ChatHistoryCard.maybeFromAttachment(attachment);
  }

  /// The one-line form of the message, for lists and screen readers.
  String get summary {
    final kind = switch (type) {
      MessageType.image => ChatHistoryLineKind.image,
      MessageType.voice => ChatHistoryLineKind.voice,
      MessageType.file =>
        file?.isVideo == true
            ? ChatHistoryLineKind.video
            : ChatHistoryLineKind.file,
      _ =>
        history != null
            ? ChatHistoryLineKind.history
            : attachment?['kind'] == 'contact_card'
            ? ChatHistoryLineKind.contact
            : ChatHistoryLineKind.text,
    };
    return chatHistoryKindSummary(
      kind,
      kind == ChatHistoryLineKind.file ? file?.name ?? '' : body,
    );
  }
}

/// The messages of a chat history.
class ChatHistoryBundle {
  const ChatHistoryBundle({required this.title, required this.items});

  factory ChatHistoryBundle.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return ChatHistoryBundle(
      title: json['title'] as String? ?? tr('Chat'),
      items: [
        if (items is List)
          for (final item in items)
            if (item is Map<String, dynamic>) BundleItem.fromJson(item),
      ],
    );
  }

  final String title;
  final List<BundleItem> items;
}
