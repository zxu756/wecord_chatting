// Round video messages in the chat page (A13).
//
// How it plugs into the chat page (see "Chat page extension points" in
// docs/design/wecord-design-language.md):
//
//  * [videoNoteComposerEntry] adds "Video message" to the composer's "+" menu
//    (composer_menu_registrations.dart), after "Photos and videos". It opens
//    the recording page and sends what was recorded through the outbox like
//    any video (so it uploads with progress, is tried again after a failure
//    and survives closing the app).
//  * A sent note shows as a circle: VideoNoteBubble, chosen in
//    thread/message_content.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/offline/outbox.dart' show OutboxEntry;
import 'package:wecord/features/chats/offline/outbox_provider.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/video_note/video_note_camera.dart';
import 'package:wecord/features/chats/video_note/video_note_models.dart';
import 'package:wecord/features/chats/video_note/video_note_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Video message" in the "+" menu, after Photos and videos (100). Offered
/// where the device or browser can record one.
final videoNoteComposerEntry = ComposerMenuContribution(
  id: 'video-message',
  order: 150,
  build: (ctx) {
    if (!ctx.container.read(videoNoteSupportedProvider)) {
      return null;
    }
    return GlassMenuEntry(
      key: const ValueKey('composer-video-message-entry'),
      icon: Icons.videocam_outlined,
      label: tr('Video message'),
      onSelected: () => unawaited(
        recordAndSendVideoNote(
          ctx.context,
          ctx.container,
          conversationId: ctx.conversationId,
          // Like photos, view-once is for direct chats and groups.
          canViewOnce: ctx.isDirect || ctx.isGroup,
        ),
      ),
    );
  },
);

/// Opens the recording page and queues what was recorded for sending.
/// Resolves to whether something was queued.
Future<bool> recordAndSendVideoNote(
  BuildContext context,
  ProviderContainer container, {
  required String conversationId,
  bool canViewOnce = true,
}) async {
  final result = await showVideoNoteRecorder(context, canViewOnce: canViewOnce);
  if (result == null) {
    return false;
  }
  final outbox = container.read(outboxProvider.notifier);
  final clip = result.clip;
  final entries = outbox.isAvailable
      ? await outbox.enqueueMedia(
          conversationId: conversationId,
          items: [
            MediaToQueue(
              kind: OutboxMediaKind.video,
              fileName: clip.fileName,
              mimeType: clip.mimeType,
              data: clip.file.openRead,
              width: clip.width,
              height: clip.height,
              // The server takes at most a minute; the recorder's clock runs
              // a moment past it when the limit stopped it.
              videoNoteMs: clip.durationMs.clamp(
                minVideoNoteMs,
                maxVideoNoteSeconds * 1000,
              ),
            ),
          ],
          viewOnce: result.viewOnce,
        )
      : const <OutboxEntry>[];
  if (entries.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(tr('Could not send the video message. Try again.')),
        ),
      );
    }
    return false;
  }
  unawaited(outbox.startSending());
  return true;
}
