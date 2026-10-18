import 'package:wecord/shared/l10n/l10n.dart';

/// The private bucket of a person's sticker library (202610220500).
const userStickerBucket = 'user-stickers';

/// The bucket sent copies live in: the normal chat pictures.
const stickerChatBucket = 'chat-images';

/// How many stickers one person keeps.
const maxUserStickers = 300;

/// The largest an animated sticker (and, for the bucket, any sticker) can be.
const maxUserStickerBytes = 1024 * 1024;

/// The long side of a still sticker, in pixels.
const userStickerMaxEdge = 512;

/// One sticker in a person's own library (the `user_stickers` table).
class UserSticker {
  const UserSticker({
    required this.id,
    required this.ownerId,
    required this.path,
    required this.width,
    required this.height,
    required this.animated,
    required this.sortKey,
    required this.createdAt,
  });

  factory UserSticker.fromJson(Map<String, dynamic> json) {
    return UserSticker(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      path: json['path'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      animated: json['animated'] == true,
      sortKey: (json['sort_key'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    );
  }

  final String id;
  final String ownerId;

  /// Where the image is in the `user-stickers` bucket:
  /// `<owner id>/<uuid>.<png|gif|webp>`.
  final String path;
  final int width;
  final int height;

  /// A GIF or WebP that moves.
  final bool animated;
  final int sortKey;
  final DateTime createdAt;

  /// `png`, `gif` or `webp`.
  String get extension => userStickerExtension(path);

  String get mimeType => 'image/$extension';

  @override
  bool operator ==(Object other) => other is UserSticker && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The extension of a sticker file name, `png` when there is none.
String userStickerExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) {
    return 'png';
  }
  final extension = path.substring(dot + 1).toLowerCase();
  return const {'gif', 'webp'}.contains(extension) ? extension : 'png';
}

/// A file in a bucket, whichever it is: the library (`user-stickers`) or a
/// sent copy (`chat-images`). Used as a provider key.
class StickerFile {
  const StickerFile(this.bucket, this.path);

  final String bucket;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is StickerFile && other.bucket == bucket && other.path == path;

  @override
  int get hashCode => Object.hash(bucket, path);
}

/// Why a sticker could not be saved, with a message to show.
class UserStickerException implements Exception {
  const UserStickerException(this.message);

  /// The library is full.
  factory UserStickerException.full() => UserStickerException(
    tr('You can keep up to {count} stickers. Delete some to add more.', {
      'count': maxUserStickers,
    }),
  );

  /// An animated picture over 1 MB.
  factory UserStickerException.animatedTooLarge() =>
      UserStickerException(tr('Animated stickers can be at most 1 MB.'));

  /// Something that is not a picture the app can read.
  factory UserStickerException.unreadable() => UserStickerException(
    tr('That is not a picture WeCord can use as a sticker.'),
  );

  final String message;

  @override
  String toString() => message;
}
