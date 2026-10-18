// The message menu's own entries, in the order the menu has always listed
// them: 100 Reply, 200 Copy, 300 Forward, 400 Translate, 500 Transcribe,
// 600 Edit, 700 Create task, 800 Pin, 900 Thread, 1000 Remind me, 1100 Save,
// 1200 Select, 1300 Preview, 1400 Copy text from picture, 1500 Publish,
// 1600 Remove embed, 1700 Delete.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_translation.dart';
import 'package:wecord/features/chats/link_preview_card.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/selection/selection_hooks.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/image_text/image_text_sheet.dart';
import 'package:wecord/features/transcribe/transcribe_controller.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/workspace/workspace_cards.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// The built-in contributions, in menu order.
final List<MessageActionContribution> builtInMessageActions = [
  MessageActionContribution(
    id: 'reply',
    order: 100,
    build: (ctx) => [
      if (ctx.canCompose)
        MessageAction(
          slot: MessageActionSlot.reply,
          icon: Icons.reply_rounded,
          label: tr('Reply'),
          onSelected: () => ctx.onReply(ctx.message),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'copy',
    order: 200,
    build: (ctx) => [
      if (ctx.message.type == MessageType.text)
        MessageAction(
          slot: MessageActionSlot.copy,
          icon: Icons.copy_rounded,
          label: tr('Copy'),
          onSelected: () => unawaited(
            Clipboard.setData(ClipboardData(text: ctx.message.body)),
          ),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'forward',
    order: 300,
    build: (ctx) => [
      // A poll's votes belong to the original, so polls are not
      // forwarded; stickers belong to circles the recipients may not be
      // in.
      if (ctx.message.type != MessageType.poll &&
          ctx.message.type != MessageType.sticker &&
          ctx.message.liveLocationCard == null &&
          !ctx.message.isViewOnce)
        MessageAction(
          slot: MessageActionSlot.forward,
          icon: Icons.shortcut_rounded,
          label: tr('Forward'),
          onSelected: () => ctx.onForward(ctx.message),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'translate',
    order: 400,
    build: (ctx) => [if (_canTranslate(ctx)) _translateAction(ctx)],
  ),
  MessageActionContribution(
    id: 'transcribe',
    order: 500,
    build: (ctx) => [if (_canTranscribe(ctx)) _transcribeAction(ctx)],
  ),
  MessageActionContribution(
    id: 'edit',
    order: 600,
    build: (ctx) => [
      if (ctx.canCompose &&
          ctx.isCurrentUser &&
          ctx.message.type == MessageType.text &&
          ctx.message.locationCard == null &&
          ctx.message.liveLocationCard == null)
        MessageAction(
          icon: Icons.edit_outlined,
          label: tr('Edit'),
          onSelected: () => ctx.onEdit(ctx.message),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'create-task',
    order: 700,
    build: (ctx) => [
      if (ctx.canCompose &&
          !ctx.isRecalled &&
          ctx.message.type != MessageType.system)
        MessageAction(
          key: const ValueKey('message-create-task'),
          icon: Icons.add_task_rounded,
          label: tr('Create task'),
          onSelected: () =>
              unawaited(showCreateTaskFromMessage(ctx.context, ctx.message)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'pin',
    order: 800,
    build: (ctx) => [
      if (ctx.canPin)
        MessageAction(
          icon: ctx.message.isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          label: ctx.message.isPinned ? tr('Unpin') : tr('Pin'),
          onSelected: () => unawaited(ctx.onTogglePin(ctx.message)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'thread',
    order: 900,
    build: (ctx) => [
      if (ctx.onOpenThread != null &&
          (ctx.message.threadSummary != null ||
              (ctx.canStartThread && ctx.message.type != MessageType.system)))
        MessageAction(
          icon: Icons.forum_outlined,
          label: ctx.message.threadSummary == null
              ? tr('Create thread')
              : tr('Open thread'),
          onSelected: () => unawaited(ctx.onOpenThread!(ctx.message)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'remind',
    order: 1000,
    build: (ctx) => [
      if (ctx.onRemind case final remind?
          when !ctx.isPending && !ctx.isRecalled)
        MessageAction(
          key: const ValueKey('message-remind'),
          icon: Icons.alarm_add_outlined,
          label: tr('Remind me'),
          onSelected: () => unawaited(remind(ctx.message)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'save',
    order: 1100,
    build: (ctx) => [
      if (ctx.onToggleSaved case final toggle?
          when !ctx.isPending && !ctx.isRecalled)
        MessageAction(
          key: const ValueKey('message-save'),
          icon: ctx.isSaved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          label: ctx.isSaved ? tr('Remove from Saved') : tr('Save for later'),
          onSelected: () => unawaited(toggle(ctx.message)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'select',
    order: 1200,
    build: (ctx) => [
      if (!ctx.isPending &&
          !ctx.isRecalled &&
          ctx.message.type != MessageType.system)
        selectMessageAction(ctx.context, ctx.message),
    ],
  ),
  MessageActionContribution(
    id: 'preview-image',
    order: 1300,
    build: (ctx) => [
      if (_imageAttachment(ctx) case final image?)
        MessageAction(
          icon: Icons.visibility_outlined,
          label: tr('Preview'),
          onSelected: () => unawaited(ctx.onPreviewImage(image)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'copy-image-text',
    order: 1400,
    build: (ctx) => [
      if (_imageAttachment(ctx) case final image? when !ctx.isPending)
        MessageAction(
          key: const ValueKey('message-copy-image-text'),
          icon: Icons.document_scanner_outlined,
          label: tr('Copy text from picture'),
          onSelected: () => unawaited(
            showImageTextSheet(
              ctx.context,
              circleId: ctx.circleId,
              file: PreviewFile.fromImageAttachment(
                image,
                messageId: ctx.message.id,
                conversationId: ctx.message.conversationId,
              ),
            ),
          ),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'publish',
    order: 1500,
    build: (ctx) => [
      if (ctx.onPublish case final publish?)
        MessageAction(
          key: const ValueKey('message-publish'),
          icon: Icons.campaign_outlined,
          label: tr('Publish'),
          onSelected: () => unawaited(publish(ctx.message)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'remove-embed',
    order: 1600,
    build: (ctx) => [
      if (ctx.canCompose && ctx.isCurrentUser && _hasVisiblePreview(ctx))
        MessageAction(
          icon: Icons.link_off_rounded,
          label: tr('Remove embed'),
          onSelected: () => unawaited(ctx.onRemoveEmbed(ctx.message)),
        ),
    ],
  ),
  MessageActionContribution(
    id: 'delete',
    order: 1700,
    build: (ctx) => [
      if (ctx.isCurrentUser)
        MessageAction(
          icon: Icons.delete_outline_rounded,
          label: tr('Delete'),
          destructive: true,
          onSelected: () => unawaited(ctx.onDelete(ctx.message)),
        )
      else if (ctx.canModerate)
        MessageAction(
          key: const ValueKey('message-moderator-delete'),
          icon: Icons.delete_outline_rounded,
          label: tr('Delete message'),
          destructive: true,
          onSelected: () => unawaited(ctx.onDelete(ctx.message)),
        ),
    ],
  ),
];

/// View-once media is neither previewed nor forwarded.
ImageAttachment? _imageAttachment(MessageActionContext ctx) =>
    ctx.isRecalled || ctx.message.isViewOnce
    ? null
    : ctx.message.imageAttachment;

bool _hasVisiblePreview(MessageActionContext ctx) {
  final url = ctx.previewUrl;
  if (url == null) {
    return false;
  }
  return ctx.container.read(linkPreviewProvider(url)).value != null;
}

/// Whether the menu offers Translate: a text message, and AI available.
bool _canTranslate(MessageActionContext ctx) {
  return !ctx.isRecalled &&
      ctx.message.type == MessageType.text &&
      ctx.message.body.trim().isNotEmpty &&
      !ctx.isPending &&
      ctx.container.read(aiAvailableProvider(ctx.circleId));
}

/// Translate to the app's language, or hide the translation again.
MessageAction _translateAction(MessageActionContext ctx) {
  final message = ctx.message;
  final translations = ctx.container.read(aiTranslationsProvider.notifier);
  final shown = translations.isShown(message.id);
  return MessageAction(
    key: const ValueKey('message-translate'),
    icon: Icons.translate_rounded,
    label: shown ? tr('Show original') : tr('Translate'),
    onSelected: () => shown
        ? translations.hide(message.id)
        : unawaited(
            translations.translate(
              message.id,
              message.body,
              conversationId: message.conversationId,
            ),
          ),
  );
}

/// Whether the menu offers Transcribe: a sent voice message.
bool _canTranscribe(MessageActionContext ctx) =>
    !ctx.isRecalled &&
    !ctx.isPending &&
    !ctx.message.isViewOnce &&
    ctx.message.type == MessageType.voice &&
    ctx.message.voiceAttachment != null;

/// Shows the voice message as text under its waveform, or hides it again.
MessageAction _transcribeAction(MessageActionContext ctx) {
  final message = ctx.message;
  final transcripts = ctx.container.read(transcriptsProvider.notifier);
  final shown = transcripts.isShown(message.id);
  final attachment = message.voiceAttachment!;
  return MessageAction(
    key: const ValueKey('message-transcribe'),
    icon: Icons.subtitles_outlined,
    label: shown ? tr('Hide transcript') : tr('Transcribe'),
    onSelected: () => shown
        ? transcripts.hide(message.id)
        : unawaited(
            transcripts.show(
              TranscribeRequest.forMessage(
                messageId: message.id,
                conversationId: message.conversationId,
                attachment: attachment,
              ),
            ),
          ),
  );
}
