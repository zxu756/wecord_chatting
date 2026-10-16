import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

/// What an album holds, in words: "3 photos", "2 photos, 1 video",
/// "4 files". Empty for no items.
String albumLabel({int images = 0, int videos = 0, int files = 0}) {
  final parts = <String>[
    if (images > 0)
      images == 1 ? tr('1 photo') : tr('{count} photos', {'count': images}),
    if (videos > 0)
      videos == 1 ? tr('1 video') : tr('{count} videos', {'count': videos}),
    if (files > 0)
      files == 1 ? tr('1 file') : tr('{count} files', {'count': files}),
  ];
  if (parts.isEmpty) {
    return '';
  }
  return parts
      .skip(1)
      .fold(
        parts.first,
        (text, part) =>
            tr('{first}, {second}', {'first': text, 'second': part}),
      );
}

/// [albumLabel] of a conversation's latest album.
String conversationAlbumLabel(ConversationAlbum album) =>
    albumLabel(images: album.images, videos: album.videos, files: album.files);
