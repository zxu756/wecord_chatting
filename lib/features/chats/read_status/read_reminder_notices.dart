// The "Reminder" card in Notifications for a message the sender asked you to
// read ("Remind unread", migration 202610220320). It goes away when you read
// the message or dismiss it.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/later/later_cards.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One reminder to read a message.
class ReadReminderNotice {
  const ReadReminderNotice({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.senderName,
    required this.body,
    required this.type,
    required this.createdAt,
    this.senderAvatarUrl,
  });

  factory ReadReminderNotice.fromJson(Map<String, dynamic> json) {
    return ReadReminderNotice(
      id: json['notice_id'] as String,
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      senderName: json['sender_display_name'] as String? ?? '',
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      body: json['body'] as String? ?? '',
      type: MessageType.fromJson(json['type'] as String? ?? 'text'),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String messageId;
  final String conversationId;
  final String senderName;
  final String? senderAvatarUrl;
  final String body;
  final MessageType type;
  final DateTime createdAt;
}

abstract interface class ReadReminderNoticesRepository {
  Future<List<ReadReminderNotice>> list();

  Future<void> markRead(List<String> ids);
}

class SupabaseReadReminderNoticesRepository
    implements ReadReminderNoticesRepository {
  const SupabaseReadReminderNoticesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ReadReminderNotice>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_read_reminder_notices');
    return [
      for (final row in rows)
        ReadReminderNotice.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<void> markRead(List<String> ids) async {
    await _client.rpc<void>(
      'mark_read_reminder_notices_read',
      params: {'p_ids': ids},
    );
  }
}

class _UninitializedReadReminderNoticesRepository
    implements ReadReminderNoticesRepository {
  const _UninitializedReadReminderNoticesRepository();

  @override
  Future<List<ReadReminderNotice>> list() async => const [];

  @override
  Future<void> markRead(List<String> ids) async {}
}

final readReminderNoticesRepositoryProvider =
    Provider<ReadReminderNoticesRepository>((ref) {
      try {
        return SupabaseReadReminderNoticesRepository(
          ref.watch(supabaseClientProvider),
        );
      } on ProviderException {
        return const _UninitializedReadReminderNoticesRepository();
      }
    });

/// The reminders to read waiting for the current user, newest first. Empty
/// when they cannot be loaded: the inbox still shows the rest.
final readReminderNoticesProvider =
    FutureProvider.autoDispose<List<ReadReminderNotice>>((ref) async {
      try {
        return await ref.watch(readReminderNoticesRepositoryProvider).list();
      } catch (_) {
        return const [];
      }
    });

/// An inbox card: who asked, the message, and a way to jump to it.
class ReadReminderCard extends StatelessWidget {
  const ReadReminderCard({
    required this.notice,
    required this.place,
    required this.onOpen,
    required this.onDismiss,
    super.key,
  });

  final ReadReminderNotice notice;

  /// The group's name.
  final String? place;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final time = describeWhen(
      MaterialLocalizations.of(context),
      notice.createdAt.toLocal(),
      clock.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final name = notice.senderName.isEmpty ? tr('Message') : notice.senderName;
    return LaterCard(
      key: ValueKey('read-reminder-${notice.id}'),
      highlighted: true,
      onPressed: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: name,
            avatarUrl: notice.senderAvatarUrl,
            badge: LaterAvatarBadge(
              color: c.warning,
              icon: Icons.notifications_active_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: ' '),
                            TextSpan(text: tr('asked you to read this')),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (place != null && place!.isNotEmpty)
                  Text(
                    place!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                const SizedBox(height: 8),
                LaterMessagePreview(
                  available: true,
                  text: laterPreview(
                    conversationId: notice.conversationId,
                    body: notice.body,
                    type: notice.type,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    WeCordButton(
                      key: ValueKey('read-reminder-open-${notice.id}'),
                      label: tr('Jump'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.secondary,
                      onPressed: onOpen,
                    ),
                    WeCordButton(
                      key: ValueKey('read-reminder-dismiss-${notice.id}'),
                      label: tr('Dismiss'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
