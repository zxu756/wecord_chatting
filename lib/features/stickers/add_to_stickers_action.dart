// How personal stickers plug into the chat page (see "Chat page extension
// points" in docs/design/wecord-design-language.md): [addToStickersAction]
// adds "Add to stickers" to the message menu of pictures, GIFs and stickers
// (registered in message_actions_registrations.dart). Sending a sticker from
// the library is the "Mine" tab of the sticker picker
// (lib/features/chats/custom_emoji.dart).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wecord/features/chats/gif_search.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/stickers/add_sticker_sheet.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/message.dart';

/// Fetches a picture from a web address (a GIF's); tests swap in a fake.
final stickerUrlFetcherProvider = Provider<Future<Uint8List> Function(Uri)>((
  ref,
) {
  return (uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    return response.bodyBytes;
  };
});

/// Where the picture of [message] comes from when it is added to the
/// stickers, or null when it cannot be (not a picture, GIF or sticker; a
/// view-once photo; deleted).
///
///  * a picture: its file in the chat bucket;
///  * a sticker of a circle the person is in, or a personal sticker: its image;
///  * a message that is nothing but a GIF's address: the GIF.
Future<Uint8List> Function()? stickerSourceFor(
  ChatMessage message,
  ProviderContainer container,
) {
  if (message.recalledAt != null || message.isViewOnce) {
    return null;
  }
  switch (message.type) {
    case MessageType.image:
      final image = message.imageAttachment;
      if (image == null) {
        return null;
      }
      return () => container
          .read(userStickersRepositoryProvider)
          .download(StickerFile(image.bucket, image.path));
    case MessageType.sticker:
      final sticker = message.stickerAttachment;
      if (sticker == null) {
        return null;
      }
      final personal = sticker.personal;
      if (personal != null) {
        return () => container
            .read(userStickersRepositoryProvider)
            .download(StickerFile(personal.bucket, personal.path));
      }
      final circleSticker = container.read(
        usableEmojisByIdProvider,
      )[sticker.emojiId];
      if (circleSticker == null) {
        return null;
      }
      return () => container
          .read(userStickersRepositoryProvider)
          .download(StickerFile(circleEmojiBucket, circleSticker.storagePath));
    case MessageType.text:
      final gif = gifUrlIn(message.body);
      if (gif == null) {
        return null;
      }
      return () => container.read(stickerUrlFetcherProvider)(Uri.parse(gif));
    case MessageType.file ||
        MessageType.voice ||
        MessageType.system ||
        MessageType.poll:
      return null;
  }
}

/// "Add to stickers" in the message menu (after Forward, 300, and before
/// Translate, 400). For pictures, GIFs and stickers; not for what is still
/// being sent or was deleted.
final addToStickersAction = MessageActionContribution(
  id: 'add-to-stickers',
  order: 350,
  build: (ctx) {
    if (ctx.isPending) {
      return const [];
    }
    final source = stickerSourceFor(ctx.message, ctx.container);
    if (source == null) {
      return const [];
    }
    return [
      MessageAction(
        key: const ValueKey('message-add-to-stickers'),
        icon: Icons.add_reaction_outlined,
        label: tr('Add to stickers'),
        onSelected: () => unawaited(_add(ctx, source)),
      ),
    ];
  },
);

Future<void> _add(
  MessageActionContext ctx,
  Future<Uint8List> Function() source,
) async {
  final context = ctx.context;
  if (!context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final added = await showAddStickerSheet(context, source: source);
  if (added) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('Added to your stickers.'))));
  }
}
