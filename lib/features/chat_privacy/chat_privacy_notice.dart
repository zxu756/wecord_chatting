import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A line the chat shows about advanced chat privacy (G6) or a screenshot of a
/// view-once photo or video (G7). The server writes both as system messages
/// with an attachment (migrations 202610280910 and 202610280930); the line is
/// worded here, in the reader's language.
sealed class ChatNotice {
  const ChatNotice({required this.actorName});

  /// Whoever did it.
  final String actorName;

  /// The line's words.
  String get text;

  IconData get icon;

  /// Null unless [attachment] belongs to one of these lines.
  static ChatNotice? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null) {
      return null;
    }
    final name = (attachment['actor_name'] as String?)?.trim();
    final actor = name == null || name.isEmpty ? tr('Someone') : name;
    switch (attachment['kind']) {
      case 'chat_privacy':
        return PrivacyNotice(
          actorName: actor,
          enabled: attachment['enabled'] == true,
        );
      case 'screenshot':
        return ScreenshotNotice(
          actorName: actor,
          recording: attachment['event'] == 'recording',
          video: attachment['media'] == 'video',
          viewOnceMessageId: attachment['message_id'] as String?,
        );
    }
    return null;
  }
}

/// "Ada turned on advanced chat privacy."
class PrivacyNotice extends ChatNotice {
  const PrivacyNotice({required super.actorName, required this.enabled});

  final bool enabled;

  @override
  String get text => enabled
      ? tr('{name} turned on advanced chat privacy', {'name': actorName})
      : tr('{name} turned off advanced chat privacy', {'name': actorName});

  @override
  IconData get icon =>
      enabled ? Icons.lock_outline_rounded : Icons.lock_open_rounded;
}

/// "Bob took a screenshot of a view-once photo." Only an iPhone can say so; it
/// is the other phone's report, not proof (see the alerts' help text).
class ScreenshotNotice extends ChatNotice {
  const ScreenshotNotice({
    required super.actorName,
    required this.recording,
    required this.video,
    this.viewOnceMessageId,
  });

  /// The screen was being recorded, rather than a screenshot taken.
  final bool recording;
  final bool video;
  final String? viewOnceMessageId;

  @override
  String get text => switch ((recording, video)) {
    (false, false) => tr('{name} took a screenshot of a view-once photo', {
      'name': actorName,
    }),
    (false, true) => tr('{name} took a screenshot of a view-once video', {
      'name': actorName,
    }),
    (true, false) => tr(
      '{name} was recording the screen while a view-once photo was open',
      {'name': actorName},
    ),
    (true, true) => tr(
      '{name} was recording the screen while a view-once video was open',
      {'name': actorName},
    ),
  };

  @override
  IconData get icon => recording
      ? Icons.fiber_manual_record_outlined
      : Icons.screenshot_outlined;
}

/// The grey pill the chat shows for a [ChatNotice].
class ChatNoticeLine extends StatelessWidget {
  const ChatNoticeLine({required this.notice, super.key});

  final ChatNotice notice;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Center(
        child: Container(
          key: const ValueKey('chat-notice-line'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(notice.icon, size: 14, color: c.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  notice.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: c.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The newest message of [messages] that announces a change of a chat's
/// advanced chat privacy; null when there is none. A new id means the setting
/// may have changed, and the chat reads it again.
String? latestPrivacyNoticeId(List<ChatMessage>? messages) {
  if (messages == null) {
    return null;
  }
  ChatMessage? latest;
  for (final message in messages) {
    if (message.type == MessageType.system &&
        message.attachment?['kind'] == 'chat_privacy' &&
        (latest == null || message.createdAt.isAfter(latest.createdAt))) {
      latest = message;
    }
  }
  return latest?.id;
}
