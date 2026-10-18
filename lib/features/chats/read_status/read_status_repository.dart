import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/read_status/read_status_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The group read list and "remind unread" (get_message_read_status and
/// remind_unread, migrations 202610220310 and 202610220320).
abstract interface class ReadStatusRepository {
  /// Who has read the message. Throws a [ReadStatusException] when it has
  /// no list for the caller.
  Future<List<MemberReadStatus>> statuses(String messageId);

  /// Whether the sender already used the message's one reminder.
  Future<bool> wasReminded(String messageId);

  /// Reminds the members who have not read it; how many were reminded.
  Future<int> remind(String messageId);
}

class SupabaseReadStatusRepository implements ReadStatusRepository {
  const SupabaseReadStatusRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MemberReadStatus>> statuses(String messageId) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'get_message_read_status',
        params: {'target_message_id': messageId},
      );
      return [
        for (final row in rows)
          MemberReadStatus.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } on PostgrestException catch (error) {
      throw ReadStatusException(readStatusProblemOf(error));
    }
  }

  @override
  Future<bool> wasReminded(String messageId) async {
    final row = await _client
        .from('message_read_reminders')
        .select('message_id')
        .eq('message_id', messageId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<int> remind(String messageId) async {
    final int reminded;
    try {
      reminded = await _client.rpc<int>(
        'remind_unread',
        params: {'target_message_id': messageId},
      );
    } on PostgrestException catch (error) {
      throw ReadStatusException(readStatusProblemOf(error));
    }
    // The push is a courtesy: the "Reminder" card is already waiting.
    try {
      await _client.functions.invoke(
        'push',
        body: {'read_reminder_message_id': messageId},
      );
    } on Object {
      // Push is not set up, or this device is offline again.
    }
    return reminded;
  }
}

/// What a server error from the read list functions means.
ReadStatusProblem readStatusProblemOf(PostgrestException error) {
  final message = error.message;
  if (message.contains('read_receipts_off')) {
    return ReadStatusProblem.receiptsOff;
  }
  if (message.contains('already_reminded')) {
    return ReadStatusProblem.alreadyReminded;
  }
  if (message.contains('nobody_to_remind')) {
    return ReadStatusProblem.nobodyToRemind;
  }
  if (error.code == '53400' || message.contains('rate_limited')) {
    return ReadStatusProblem.rateLimited;
  }
  return switch (error.code) {
    '22023' || '42501' || 'P0002' => ReadStatusProblem.unavailable,
    _ => ReadStatusProblem.other,
  };
}

class _UninitializedReadStatusRepository implements ReadStatusRepository {
  const _UninitializedReadStatusRepository();

  @override
  Future<List<MemberReadStatus>> statuses(String messageId) async =>
      throw const ReadStatusException(ReadStatusProblem.unavailable);

  @override
  Future<bool> wasReminded(String messageId) async => false;

  @override
  Future<int> remind(String messageId) async =>
      throw const ReadStatusException(ReadStatusProblem.unavailable);
}

final readStatusRepositoryProvider = Provider<ReadStatusRepository>((ref) {
  try {
    return SupabaseReadStatusRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedReadStatusRepository();
  }
});

/// Who has read a message, for the sheet. Read when it opens; nothing keeps
/// it up to date after that.
final messageReadStatusProvider = FutureProvider.autoDispose
    .family<ReadList, String>((ref, messageId) async {
      final rows = await ref
          .watch(readStatusRepositoryProvider)
          .statuses(messageId);
      return ReadList(rows);
    });

/// Whether the message's reminder is used up.
final readReminderSentProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, messageId) {
      return ref.watch(readStatusRepositoryProvider).wasReminded(messageId);
    });
