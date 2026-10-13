import 'dart:typed_data';

/// A circle's custom emoji or sticker, as `list_circle_emojis` and
/// `list_my_usable_emojis` return it.
class CircleEmoji {
  const CircleEmoji({
    required this.id,
    required this.circleId,
    required this.name,
    required this.kind,
    required this.storagePath,
    required this.mimeType,
    required this.createdAt,
    this.circleName,
    this.createdBy,
    this.creatorName,
  });

  factory CircleEmoji.fromJson(Map<String, dynamic> json) {
    return CircleEmoji(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      circleName: json['circle_name'] as String?,
      name: json['name'] as String,
      kind: CircleEmojiKind.fromJson(json['kind'] as String),
      storagePath: json['storage_path'] as String,
      mimeType: json['mime_type'] as String,
      createdBy: json['created_by'] as String?,
      creatorName: json['creator_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    );
  }

  final String id;
  final String circleId;

  /// The circle's name, to group pickers by circle.
  final String? circleName;
  final String name;
  final CircleEmojiKind kind;

  /// Where the image is in the `circle-emojis` bucket.
  final String storagePath;
  final String mimeType;
  final String? createdBy;
  final String? creatorName;
  final DateTime createdAt;

  bool get isSticker => kind == CircleEmojiKind.sticker;

  /// How an emoji is written in a message body.
  String get token => '<:$name:$id>';

  /// How an emoji is stored as a reaction.
  String get reactionValue => '$customReactionPrefix$id';

  CircleEmoji copyWith({String? name}) {
    return CircleEmoji(
      id: id,
      circleId: circleId,
      circleName: circleName,
      name: name ?? this.name,
      kind: kind,
      storagePath: storagePath,
      mimeType: mimeType,
      createdBy: createdBy,
      creatorName: creatorName,
      createdAt: createdAt,
    );
  }
}

enum CircleEmojiKind {
  emoji,
  sticker;

  factory CircleEmojiKind.fromJson(String value) {
    return switch (value) {
      'emoji' => CircleEmojiKind.emoji,
      'sticker' => CircleEmojiKind.sticker,
      _ => throw ArgumentError.value(value, 'value', 'Unknown emoji kind'),
    };
  }

  String toJson() => name;

  /// How many a circle may have.
  int get limit => switch (this) {
    CircleEmojiKind.emoji => maxCircleEmojis,
    CircleEmojiKind.sticker => maxCircleStickers,
  };
}

const maxCircleEmojis = 50;
const maxCircleStickers = 20;

/// The largest image a circle emoji or sticker may be, in bytes.
const maxCircleEmojiBytes = 256 * 1024;

const circleEmojiBucket = 'circle-emojis';

/// Names are 2 to 32 lowercase letters, digits or underscores.
final circleEmojiNamePattern = RegExp(r'^[a-z0-9_]{2,32}$');

const customReactionPrefix = 'custom:';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// The emoji id of a `custom:<uuid>` reaction, or null for other reactions.
String? customReactionEmojiId(String reaction) {
  if (!reaction.startsWith(customReactionPrefix)) {
    return null;
  }
  final id = reaction.substring(customReactionPrefix.length);
  return _uuidPattern.hasMatch(id) ? id : null;
}

/// A name suggested from an image's file name: lowercased, with anything
/// but letters, digits and underscores turned into underscores.
String suggestedCircleEmojiName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = (dot > 0 ? fileName.substring(0, dot) : fileName).toLowerCase();
  var name = base
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (name.length > 32) {
    name = name.substring(0, 32);
  }
  return name.length < 2 ? '' : name;
}

/// The type of a PNG, GIF or WebP image from its first bytes, or null for
/// anything else.
String? circleEmojiImageMimeType(Uint8List bytes) {
  bool startsWith(List<int> prefix, [int offset = 0]) {
    if (bytes.length < offset + prefix.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[offset + index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith('GIF87a'.codeUnits) || startsWith('GIF89a'.codeUnits)) {
    return 'image/gif';
  }
  if (startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, 8)) {
    return 'image/webp';
  }
  return null;
}

/// The file extension the `circle-emojis` bucket expects for [mimeType].
String circleEmojiExtension(String mimeType) {
  return switch (mimeType) {
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => 'png',
  };
}

/// A sticker message's attachment: `{kind: 'sticker', emoji_id, name,
/// circle_id}`.
class StickerAttachment {
  const StickerAttachment({
    required this.emojiId,
    required this.name,
    required this.circleId,
  });

  static StickerAttachment? maybeFromJson(Object? json) {
    if (json is! Map || json['kind'] != 'sticker') {
      return null;
    }
    final emojiId = json['emoji_id'];
    final name = json['name'];
    final circleId = json['circle_id'];
    if (emojiId is! String || name is! String || circleId is! String) {
      return null;
    }
    return StickerAttachment(emojiId: emojiId, name: name, circleId: circleId);
  }

  final String emojiId;
  final String name;
  final String circleId;
}

/// "[Sticker] name", for previews and notifications.
String stickerPreviewText(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '[Sticker]' : '[Sticker] $trimmed';
}
