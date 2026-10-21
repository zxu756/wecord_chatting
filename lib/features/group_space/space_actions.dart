// The group space (B6) in the chat page.
//
// How it plugs into the chat page (see "Chat page extension points" in
// docs/design/wecord-design-language.md):
//
//  * [groupSpaceHeaderAction] adds "Group space" to the More menu of a group
//    chat. It also watches what the space allows, which keeps that loaded;
//    the two message entries below only read it.
//  * [addToAlbumAction] adds "Add to album" to the menu of a picture or a
//    video, [saveToGroupFilesAction] adds "Save to group files" to the menu of
//    a picture, video or file. Neither is offered for what cannot be kept:
//    view-once media, deleted messages, messages that expire, ones waiting for
//    review and ones forwarded from another chat; nor in a chat whose
//    disappearing messages are on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_providers.dart';
import 'package:wecord/features/group_space/group_space_screen.dart';
import 'package:wecord/features/group_space/space_pickers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

/// What the space of [conversationId] allows, if some page already loaded it;
/// null otherwise, and it never starts a load.
GroupSpaceInfo? knownGroupSpaceInfo(
  ProviderContainer container,
  String conversationId,
) {
  final provider = groupSpaceInfoProvider(conversationId);
  if (!container.exists(provider)) {
    return null;
  }
  return container.read(provider).value;
}

/// "Group space" in the More menu of a group chat.
final groupSpaceHeaderAction = HeaderActionContribution(
  id: 'group-space',
  order: 950,
  build: (ctx) {
    if (ctx.conversationType != ConversationType.group) {
      return null;
    }
    final info = ctx.ref.watch(groupSpaceInfoProvider(ctx.conversationId));
    if (info.value case final value? when !value.supported) {
      return null;
    }
    return ChatThreadAction(
      id: 'group-space',
      tooltip: tr('Group space'),
      icon: Icons.folder_special_outlined,
      menuOnly: true,
      onPressed: () {
        unawaited(
          ctx.context.push(GroupSpaceScreen.pathFor(ctx.conversationId)),
        );
      },
    );
  },
);

/// The messages a menu entry would keep: [message], or every picture of the
/// album it opens. Empty when the message cannot go in the space.
List<ChatMessage> _keepable(ChatMessage message, {required bool albumOnly}) {
  bool ok(ChatMessage m) {
    if (m.recalledAt != null ||
        m.isViewOnce ||
        m.expiresAt != null ||
        m.reviewState != null ||
        m.forwardPreview != null) {
      return false;
    }
    final attachment = m.attachment;
    final path = attachment?['path'];
    if (path is! String || !path.startsWith('${m.conversationId}/')) {
      return false;
    }
    switch (m.type) {
      case MessageType.image:
        return true;
      case MessageType.file:
        final file = m.fileAttachment;
        return file != null && (!albumOnly || file.isVideo);
      case MessageType.text ||
          MessageType.voice ||
          MessageType.system ||
          MessageType.poll ||
          MessageType.sticker:
        return false;
    }
  }

  final group = message.album;
  final candidates = group == null || group.isEmpty ? [message] : group;
  return [
    for (final candidate in candidates)
      if (ok(candidate)) candidate,
  ];
}

Iterable<MessageAction> _entries(
  MessageActionContext ctx, {
  required bool albumOnly,
}) {
  if (ctx.isPending || ctx.isRecalled || ctx.circleId != null) {
    return const [];
  }
  final message = ctx.message;
  final info = knownGroupSpaceInfo(ctx.container, message.conversationId);
  if (info == null || !info.supported || !info.canAdd) {
    return const [];
  }
  final keep = _keepable(message, albumOnly: albumOnly);
  if (keep.isEmpty) {
    return const [];
  }
  final ids = [for (final m in keep) m.id];
  final context = ctx.context;
  final conversationId = message.conversationId;
  if (albumOnly) {
    return [
      MessageAction(
        key: const ValueKey('message-add-to-album'),
        icon: Icons.photo_album_outlined,
        label: tr('Add to album'),
        onSelected: () => unawaited(
          addMessagesToAlbumFlow(
            context,
            conversationId: conversationId,
            messageIds: ids,
          ),
        ),
      ),
    ];
  }
  return [
    MessageAction(
      key: const ValueKey('message-save-to-group-files'),
      icon: Icons.folder_copy_outlined,
      label: tr('Save to group files'),
      onSelected: () => unawaited(
        saveMessagesToFilesFlow(
          context,
          conversationId: conversationId,
          messageIds: ids,
        ),
      ),
    ),
  ];
}

/// "Add to album" in the menu of a picture or video (after Add to stickers).
final addToAlbumAction = MessageActionContribution(
  id: 'add-to-album',
  order: 352,
  build: (ctx) {
    final message = ctx.message;
    final isMedia =
        message.type == MessageType.image ||
        (message.type == MessageType.file &&
            (message.fileAttachment?.isVideo ?? false));
    return isMedia ? _entries(ctx, albumOnly: true) : const [];
  },
);

/// "Save to group files" in the menu of a picture, video or file.
final saveToGroupFilesAction = MessageActionContribution(
  id: 'save-to-group-files',
  order: 354,
  build: (ctx) => _entries(ctx, albumOnly: false),
);
