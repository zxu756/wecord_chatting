import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Urgent messages (A7, migrations 202610240400 to 202610240460) and the
/// group announcements that ask for a confirmation.
abstract interface class UrgentRepository {
  /// Makes the sender's message urgent for [targetIds]; how many people were
  /// told. Throws an [UrgentException].
  Future<int> sendUrgent(String messageId, List<String> targetIds);

  /// "Got it": confirms what was made urgent for the current user.
  Future<void> acknowledge(String messageId);

  /// The urgent messages waiting for the current user, in one conversation or
  /// all of them.
  Future<List<PendingUrgent>> pending({String? conversationId});

  /// Who a message was made urgent for, and who confirmed (its sender only).
  Future<List<UrgentRecipient>> recipients(String messageId);

  Future<UrgentQuota> quota();

  /// Allows or stops urgent messages from one person.
  Future<void> setAllowedFrom(String senderId, {required bool allowed});

  Future<List<MutedUrgentSender>> mutedSenders();

  /// Fires when an urgent message arrives for, or is confirmed by, the
  /// current user (Realtime on their own rows).
  Stream<void> changes();

  Future<AnnouncementAckState> announcementState(String conversationId);

  Future<List<AnnouncementAckMember>> announcementMembers(
    String conversationId,
  );

  Future<void> acknowledgeAnnouncement(String conversationId);

  Future<void> setAnnouncementRequiresAck(
    String conversationId, {
    required bool required,
  });

  /// Asks the members who have not confirmed; how many were asked.
  Future<int> remindUnconfirmed(String conversationId);

  Future<List<PendingAnnouncementAck>> pendingAnnouncements();
}

/// What a server error from these functions means.
UrgentProblem urgentProblemOf(PostgrestException error) {
  final message = error.message;
  if (error.code == '53400' || message.contains('rate_limited')) {
    return UrgentProblem.rateLimited;
  }
  if (message.contains('nobody_to_urgent')) {
    return UrgentProblem.nobodyToUrgent;
  }
  if (message.contains('too_many_targets')) {
    return UrgentProblem.tooManyPeople;
  }
  if (message.contains('empty_announcement')) {
    return UrgentProblem.emptyAnnouncement;
  }
  if (message.contains('nobody_to_remind')) {
    return UrgentProblem.nobodyToRemind;
  }
  return switch (error.code) {
    '22023' || '42501' || 'P0002' => UrgentProblem.unavailable,
    _ => UrgentProblem.other,
  };
}

class SupabaseUrgentRepository implements UrgentRepository {
  const SupabaseUrgentRepository(this._client);

  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw UrgentException(urgentProblemOf(error));
    }
  }

  List<Map<String, dynamic>> _rows(List<dynamic> rows) => [
    for (final row in rows) Map<String, dynamic>.from(row as Map),
  ];

  @override
  Future<int> sendUrgent(String messageId, List<String> targetIds) {
    return _guard(() async {
      final count = await _client.rpc<int>(
        'send_message_urgent',
        params: {'p_message_id': messageId, 'p_target_ids': targetIds},
      );
      return count;
    });
  }

  @override
  Future<void> acknowledge(String messageId) {
    return _guard(() async {
      await _client.rpc<dynamic>(
        'ack_message_urgent',
        params: {'p_message_id': messageId},
      );
    });
  }

  @override
  Future<List<PendingUrgent>> pending({String? conversationId}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_my_pending_urgents',
      params: {'p_conversation_id': conversationId},
    );
    return [for (final row in _rows(rows)) PendingUrgent.fromJson(row)];
  }

  @override
  Future<List<UrgentRecipient>> recipients(String messageId) {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'get_message_urgent_status',
        params: {'p_message_id': messageId},
      );
      return [for (final row in _rows(rows)) UrgentRecipient.fromJson(row)];
    });
  }

  @override
  Future<UrgentQuota> quota() async {
    final rows = await _client.rpc<List<dynamic>>('my_urgent_quota');
    if (rows.isEmpty) {
      return const UrgentQuota.unknown();
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return UrgentQuota(
      used: (row['used'] as num).toInt(),
      allowed: (row['allowed'] as num).toInt(),
    );
  }

  @override
  Future<void> setAllowedFrom(String senderId, {required bool allowed}) {
    return _guard(() async {
      await _client.rpc<dynamic>(
        'set_urgent_from_sender',
        params: {'p_sender_id': senderId, 'p_allowed': allowed},
      );
    });
  }

  @override
  Future<List<MutedUrgentSender>> mutedSenders() async {
    final rows = await _client.rpc<List<dynamic>>('list_urgent_muted_senders');
    return [for (final row in _rows(rows)) MutedUrgentSender.fromJson(row)];
  }

  @override
  Stream<void> changes() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<void>.empty();
    }
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('urgent-$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'message_urgent_targets',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Future<AnnouncementAckState> announcementState(String conversationId) {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'get_announcement_ack_state',
        params: {'p_conversation_id': conversationId},
      );
      if (rows.isEmpty) {
        return AnnouncementAckState.none;
      }
      return AnnouncementAckState.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
      );
    });
  }

  @override
  Future<List<AnnouncementAckMember>> announcementMembers(
    String conversationId,
  ) {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'list_announcement_ack_members',
        params: {'p_conversation_id': conversationId},
      );
      return [
        for (final row in _rows(rows)) AnnouncementAckMember.fromJson(row),
      ];
    });
  }

  @override
  Future<void> acknowledgeAnnouncement(String conversationId) {
    return _guard(() async {
      await _client.rpc<dynamic>(
        'ack_announcement',
        params: {'p_conversation_id': conversationId},
      );
    });
  }

  @override
  Future<void> setAnnouncementRequiresAck(
    String conversationId, {
    required bool required,
  }) {
    return _guard(() async {
      await _client.rpc<dynamic>(
        'set_announcement_requires_ack',
        params: {'p_conversation_id': conversationId, 'p_required': required},
      );
    });
  }

  @override
  Future<int> remindUnconfirmed(String conversationId) {
    return _guard(() async {
      final count = await _client.rpc<int>(
        'remind_announcement_unacked',
        params: {'p_conversation_id': conversationId},
      );
      return count;
    });
  }

  @override
  Future<List<PendingAnnouncementAck>> pendingAnnouncements() async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_my_pending_announcement_acks',
    );
    return [
      for (final row in _rows(rows)) PendingAnnouncementAck.fromJson(row),
    ];
  }
}

/// Stands in before Supabase is set up (tests): nothing is waiting.
class UninitializedUrgentRepository implements UrgentRepository {
  const UninitializedUrgentRepository();

  @override
  Future<int> sendUrgent(String messageId, List<String> targetIds) =>
      throw const UrgentException(UrgentProblem.unavailable);

  @override
  Future<void> acknowledge(String messageId) async {}

  @override
  Future<List<PendingUrgent>> pending({String? conversationId}) async =>
      const [];

  @override
  Future<List<UrgentRecipient>> recipients(String messageId) async => const [];

  @override
  Future<UrgentQuota> quota() async => const UrgentQuota.unknown();

  @override
  Future<void> setAllowedFrom(String senderId, {required bool allowed}) async {}

  @override
  Future<List<MutedUrgentSender>> mutedSenders() async => const [];

  @override
  Stream<void> changes() => const Stream<void>.empty();

  @override
  Future<AnnouncementAckState> announcementState(String conversationId) async =>
      AnnouncementAckState.none;

  @override
  Future<List<AnnouncementAckMember>> announcementMembers(
    String conversationId,
  ) async => const [];

  @override
  Future<void> acknowledgeAnnouncement(String conversationId) async {}

  @override
  Future<void> setAnnouncementRequiresAck(
    String conversationId, {
    required bool required,
  }) async {}

  @override
  Future<int> remindUnconfirmed(String conversationId) async => 0;

  @override
  Future<List<PendingAnnouncementAck>> pendingAnnouncements() async => const [];
}

final urgentRepositoryProvider = Provider<UrgentRepository>((ref) {
  try {
    return SupabaseUrgentRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedUrgentRepository();
  }
});

/// The urgent messages waiting for the current user, in one conversation or
/// (null) all of them. Reloaded when one arrives or is confirmed; empty when
/// they cannot be loaded.
final pendingUrgentsProvider = FutureProvider.autoDispose
    .family<List<PendingUrgent>, String?>((ref, conversationId) async {
      final repository = ref.watch(urgentRepositoryProvider);
      final subscription = repository.changes().listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      try {
        return await repository.pending(conversationId: conversationId);
      } catch (_) {
        return const [];
      }
    });

/// A group announcement's confirmation state, for the strip under the header.
final announcementAckStateProvider = FutureProvider.autoDispose
    .family<AnnouncementAckState, String>((ref, conversationId) async {
      try {
        return await ref
            .watch(urgentRepositoryProvider)
            .announcementState(conversationId);
      } catch (_) {
        return AnnouncementAckState.none;
      }
    });

/// Who confirmed and who did not (owner and admins).
final announcementAckMembersProvider = FutureProvider.autoDispose
    .family<List<AnnouncementAckMember>, String>((ref, conversationId) {
      return ref
          .watch(urgentRepositoryProvider)
          .announcementMembers(conversationId);
    });

/// The announcements waiting for the current user's confirmation.
final pendingAnnouncementAcksProvider =
    FutureProvider.autoDispose<List<PendingAnnouncementAck>>((ref) async {
      try {
        return await ref.watch(urgentRepositoryProvider).pendingAnnouncements();
      } catch (_) {
        return const [];
      }
    });

/// The people whose urgent messages the current user turned off.
final mutedUrgentSendersProvider =
    FutureProvider.autoDispose<List<MutedUrgentSender>>((ref) {
      return ref.watch(urgentRepositoryProvider).mutedSenders();
    });

/// Who a message was made urgent for (its sender asks).
final urgentRecipientsProvider = FutureProvider.autoDispose
    .family<List<UrgentRecipient>, String>((ref, messageId) {
      return ref.watch(urgentRepositoryProvider).recipients(messageId);
    });

final urgentQuotaProvider = FutureProvider.autoDispose<UrgentQuota>((ref) {
  return ref.watch(urgentRepositoryProvider).quota();
});

/// How many confirmations the current user owes: urgent messages and
/// announcements, for the Notifications badge.
final pendingConfirmationCountProvider = Provider.autoDispose<int>((ref) {
  final urgent = ref.watch(pendingUrgentsProvider(null)).value?.length ?? 0;
  final announcements =
      ref.watch(pendingAnnouncementAcksProvider).value?.length ?? 0;
  return urgent + announcements;
});
