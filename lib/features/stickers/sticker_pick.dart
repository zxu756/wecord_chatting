import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
import 'package:wecord/shared/models/circle_emoji.dart';

/// What the sticker picker hands back: a sticker of a circle or one from the
/// person's own library.
sealed class StickerPick {
  const StickerPick();
}

class CircleStickerPick extends StickerPick {
  const CircleStickerPick(this.emoji);

  final CircleEmoji emoji;
}

class PersonalStickerPick extends StickerPick {
  const PersonalStickerPick(this.sticker);

  final UserSticker sticker;
}

/// Sends [pick] to [conversationId], in a direct chat, a group or a circle
/// channel. Throws what a send throws ([SlowmodeException],
/// [SendRefusedException], or anything else for a failure).
Future<void> sendStickerPick(
  WidgetRef ref, {
  required String conversationId,
  required StickerPick pick,
}) {
  return switch (pick) {
    CircleStickerPick(:final emoji) =>
      ref
          .read(chatsRepositoryProvider)
          .sendSticker(conversationId: conversationId, stickerId: emoji.id),
    PersonalStickerPick(:final sticker) =>
      ref
          .read(userStickersRepositoryProvider)
          .send(conversationId: conversationId, sticker: sticker),
  };
}
