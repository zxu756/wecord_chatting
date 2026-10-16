import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/message.dart';

/// A reminder about a message: [remindAt] (a UTC instant) is when it
/// comes back to the reader, in Notifications.
class MessageReminder {
  const MessageReminder({
    required this.id,
    required this.conversationId,
    required this.remindAt,
    this.messageId,
    this.senderId,
    this.senderName = '',
    this.senderAvatarUrl,
    this.body = '',
    this.type = MessageType.text,
    this.messageCreatedAt,
    this.available = true,
  });

  factory MessageReminder.fromJson(Map<String, dynamic> json) {
    final available = json['available'] as bool? ?? false;
    final webhookName = json['webhook_name'] as String?;
    return MessageReminder(
      id: json['reminder_id'] as String,
      messageId: json['message_id'] as String?,
      conversationId: json['conversation_id'] as String,
      remindAt: DateTime.parse(json['remind_at'] as String),
      senderId: json['sender_id'] as String?,
      senderName: webhookName ?? json['sender_display_name'] as String? ?? '',
      senderAvatarUrl: webhookName == null
          ? json['sender_avatar_url'] as String?
          : null,
      body: available ? json['body'] as String? ?? '' : '',
      type: available && json['type'] is String
          ? MessageType.fromJson(json['type'] as String)
          : MessageType.text,
      messageCreatedAt: json['message_created_at'] == null
          ? null
          : DateTime.parse(json['message_created_at'] as String),
      available: available,
    );
  }

  final String id;
  final String? messageId;
  final String conversationId;
  final DateTime remindAt;
  final String? senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String body;
  final MessageType type;
  final DateTime? messageCreatedAt;

  /// The message can still be read by the current user.
  final bool available;

  /// Whether the time has come.
  bool isFired([DateTime? now]) => !remindAt.isAfter(now ?? clock.now());
}

/// A reminder that came due while the app was open: what to notify.
class LocalReminder {
  const LocalReminder({
    required this.id,
    required this.conversationId,
    required this.senderName,
    required this.body,
    required this.type,
    this.messageId,
  });

  factory LocalReminder.fromJson(Map<String, dynamic> json) {
    return LocalReminder(
      id: json['reminder_id'] as String,
      conversationId: json['conversation_id'] as String,
      messageId: json['message_id'] as String?,
      senderName: json['sender_name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      type: MessageType.fromJson(json['type'] as String? ?? 'text'),
    );
  }

  final String id;
  final String conversationId;
  final String? messageId;
  final String senderName;
  final String body;
  final MessageType type;
}

abstract interface class RemindersRepository {
  /// The current user's open reminders, soonest first: fired ones waiting
  /// in Notifications and upcoming ones.
  Future<List<MessageReminder>> list();

  /// Reminds the user about a message at [remindAt]; a message has one open
  /// reminder, so this moves an existing one.
  Future<void> set(String messageId, DateTime remindAt);

  /// Dismisses a fired reminder, or cancels an upcoming one.
  Future<void> dismiss(String id);

  /// Reminders that came due since the last call, marked as shown (for the
  /// local notification).
  Future<List<LocalReminder>> claimDue();
}

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  try {
    return SupabaseRemindersRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedRemindersRepository();
  }
});

/// The open reminders. Fetched again when the next one comes due, so its
/// card appears in Notifications on time.
final remindersProvider = FutureProvider.autoDispose<List<MessageReminder>>((
  ref,
) async {
  final reminders = await ref.watch(remindersRepositoryProvider).list();
  final now = clock.now();
  final next = reminders
      .where((reminder) => !reminder.isFired(now))
      .map((reminder) => reminder.remindAt)
      .fold<DateTime?>(
        null,
        (soonest, at) => soonest == null || at.isBefore(soonest) ? at : soonest,
      );
  if (next != null) {
    // Never longer than an hour, so a sleeping device catches up.
    final wait = next.difference(now) + const Duration(seconds: 2);
    final timer = Timer(
      wait > const Duration(hours: 1) ? const Duration(hours: 1) : wait,
      ref.invalidateSelf,
    );
    ref.onDispose(timer.cancel);
  }
  return reminders;
});

/// Reminders whose time has come and that the user has not dismissed,
/// newest due first.
final firedRemindersProvider = Provider.autoDispose<List<MessageReminder>>((
  ref,
) {
  final now = clock.now();
  final fired = [
    for (final reminder
        in ref.watch(remindersProvider).value ?? const <MessageReminder>[])
      if (reminder.isFired(now)) reminder,
  ]..sort((a, b) => b.remindAt.compareTo(a.remindAt));
  return fired;
});

class SupabaseRemindersRepository implements RemindersRepository {
  const SupabaseRemindersRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MessageReminder>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_my_reminders');
    return [
      for (final row in rows)
        MessageReminder.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> set(String messageId, DateTime remindAt) async {
    await _client.rpc<dynamic>(
      'set_message_reminder',
      params: {
        'p_message_id': messageId,
        'p_remind_at': remindAt.toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> dismiss(String id) async {
    await _client.rpc<dynamic>(
      'dismiss_message_reminder',
      params: {'p_id': id},
    );
  }

  @override
  Future<List<LocalReminder>> claimDue() async {
    final rows = await _client.rpc<List<dynamic>>('claim_local_reminders');
    return [
      for (final row in rows)
        LocalReminder.fromJson(row as Map<String, dynamic>),
    ];
  }
}

/// The tap payload of a reminder's local notification: opens the
/// conversation at the message.
String reminderNotificationPayload(String conversationId, String? messageId) {
  return messageId == null
      ? conversationId
      : 'message:$conversationId:$messageId';
}

/// The conversation and message of a reminder notification's [payload], or
/// null for other notifications.
({String conversationId, String messageId})? parseReminderNotificationPayload(
  String payload,
) {
  final parts = payload.split(':');
  if (parts.length != 3 ||
      parts[0] != 'message' ||
      parts[1].isEmpty ||
      parts[2].isEmpty) {
    return null;
  }
  return (conversationId: parts[1], messageId: parts[2]);
}

class UninitializedRemindersRepository implements RemindersRepository {
  const UninitializedRemindersRepository();

  @override
  Future<List<MessageReminder>> list() async => const [];

  @override
  Future<void> set(String messageId, DateTime remindAt) =>
      throw StateError('Supabase must be initialized to set reminders.');

  @override
  Future<void> dismiss(String id) async {}

  @override
  Future<List<LocalReminder>> claimDue() async => const [];
}
