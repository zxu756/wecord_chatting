import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';

/// The calls behind the moderator tools (C5) and raid protection (C6). Every
/// one is a database function that checks the caller's permission and rank
/// itself; the app only asks.
class ModToolsRepository {
  const ModToolsRepository(this._rpc);

  final CircleRpc _rpc;

  // ---- The member list and batch actions

  Future<ModMemberPage> listMembers(
    String circleId,
    ModMemberFilter filter, {
    int limit = 50,
    int offset = 0,
  }) async {
    final result = await _rpc('list_circle_members_for_moderation', {
      'target_circle_id': circleId,
      ...filter.toParams(),
      'result_limit': limit,
      'result_offset': offset,
    });
    final rows = rpcRows(result);
    return ModMemberPage(
      members: [for (final row in rows) ModMember.fromJson(row)],
      total: rows.isEmpty ? 0 : (rows.first['total_count'] as num).toInt(),
    );
  }

  /// Times out, kicks or bans up to 50 members at once. [seconds] is the
  /// timeout's length, or how long a ban lasts (null: until lifted).
  Future<BatchOutcome> batch(
    String circleId,
    List<String> userIds,
    BatchAction action, {
    int? seconds,
    String? reason,
  }) async {
    final trimmed = reason?.trim() ?? '';
    final result = await _rpc('batch_moderate_circle_members', {
      'target_circle_id': circleId,
      'target_user_ids': userIds,
      'batch_action': action.name,
      'duration_seconds': seconds,
      if (trimmed.isNotEmpty) 'batch_reason': trimmed,
    });
    return BatchOutcome.fromJson(rpcObject(result));
  }

  // ---- Notes and warnings

  Future<List<ModNote>> listNotes(String circleId, String userId) async {
    final result = await _rpc('list_circle_mod_notes', {
      'target_circle_id': circleId,
      'target_user_id': userId,
    });
    return [for (final row in rpcRows(result)) ModNote.fromJson(row)];
  }

  Future<void> addNote(
    String circleId,
    String userId,
    ModNoteKind kind,
    String body,
  ) async {
    await _rpc('add_circle_mod_note', {
      'target_circle_id': circleId,
      'target_user_id': userId,
      'note_kind': kind.name,
      'note_body': body.trim(),
    });
  }

  Future<void> deleteNote(String noteId) async {
    await _rpc('delete_circle_mod_note', {'target_note_id': noteId});
  }

  // ---- Ban appeals

  Future<List<BanAppeal>> listAppeals(String circleId) async {
    final result = await _rpc('list_ban_appeals', {
      'target_circle_id': circleId,
    });
    return [for (final row in rpcRows(result)) BanAppeal.fromJson(row)];
  }

  /// How many appeals wait; 0 without the permission.
  Future<int> countAppeals(String circleId) async {
    final result = await _rpc('count_ban_appeals', {
      'target_circle_id': circleId,
    });
    return (result as num?)?.toInt() ?? 0;
  }

  Future<void> decideAppeal(
    String appealId, {
    required bool approve,
    String? note,
  }) async {
    final text = note?.trim() ?? '';
    await _rpc('decide_ban_appeal', {
      'target_appeal_id': appealId,
      'approve': approve,
      if (text.isNotEmpty) 'decision_note': text,
    });
  }

  /// The circles the current user is banned from.
  Future<List<MyCircleBan>> myBans() async {
    final result = await _rpc('my_circle_bans', const {});
    return [for (final row in rpcRows(result)) MyCircleBan.fromJson(row)];
  }

  Future<void> submitAppeal(String circleId, String message) async {
    await _rpc('submit_ban_appeal', {
      'target_circle_id': circleId,
      'appeal_message': message.trim(),
    });
  }

  // ---- Raid protection and safety actions

  Future<CircleSecurity> getSecurity(String circleId) async {
    final result = await _rpc('get_circle_security', {
      'target_circle_id': circleId,
    });
    return CircleSecurity.fromJson(rpcObject(result));
  }

  Future<void> saveRaidSettings(
    String circleId, {
    required bool enabled,
    required int threshold,
    required int lockHours,
  }) async {
    await _rpc('set_circle_raid_settings', {
      'target_circle_id': circleId,
      'protection_enabled': enabled,
      'join_threshold': threshold,
      'lockdown_hours': lockHours,
    });
  }

  Future<void> pauseInvites(String circleId, int hours) async {
    await _rpc('pause_circle_invites', {
      'target_circle_id': circleId,
      'pause_hours': hours,
    });
  }

  Future<void> resumeInvites(String circleId) async {
    await _rpc('resume_circle_invites', {'target_circle_id': circleId});
  }

  Future<void> startLockdown(String circleId, int hours) async {
    await _rpc('start_circle_lockdown', {
      'target_circle_id': circleId,
      'lockdown_hours': hours,
    });
  }

  Future<void> endLockdown(String circleId) async {
    await _rpc('end_circle_lockdown', {'target_circle_id': circleId});
  }

  // ---- Locked threads

  /// Null when [conversationId] is not a thread the user belongs to.
  Future<ThreadLockState?> threadLockState(String conversationId) async {
    final result = await _rpc('get_thread_lock_state', {
      'target_conversation_id': conversationId,
    });
    if (result is! Map) {
      return null;
    }
    return ThreadLockState.fromJson(Map<String, dynamic>.from(result));
  }

  Future<void> setThreadLocked(String threadId, {required bool locked}) async {
    await _rpc('set_thread_locked', {
      'target_thread_id': threadId,
      'locked': locked,
    });
  }
}

final modToolsRepositoryProvider = Provider<ModToolsRepository>((ref) {
  return ModToolsRepository(ref.watch(circleRpcProvider));
});

/// A circle's safety state; fails for members who may not read it.
final circleSecurityProvider = FutureProvider.autoDispose
    .family<CircleSecurity, String>((ref, circleId) {
      return ref.watch(modToolsRepositoryProvider).getSecurity(circleId);
    });

/// The ban appeals waiting in a circle.
final banAppealsProvider = FutureProvider.autoDispose
    .family<List<BanAppeal>, String>((ref, circleId) {
      return ref.watch(modToolsRepositoryProvider).listAppeals(circleId);
    });

/// How many appeals wait; 0 when unreadable (it is part of the Review
/// badge).
final banAppealCountProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  circleId,
) async {
  try {
    return await ref.watch(modToolsRepositoryProvider).countAppeals(circleId);
  } on Object {
    return 0;
  }
});

/// A circle id and a member's id.
typedef ModNotesKey = ({String circleId, String userId});

final modNotesProvider = FutureProvider.autoDispose
    .family<List<ModNote>, ModNotesKey>((ref, key) {
      return ref
          .watch(modToolsRepositoryProvider)
          .listNotes(key.circleId, key.userId);
    });

/// The circles the current user is banned from, for Notifications.
final myCircleBansProvider = FutureProvider.autoDispose<List<MyCircleBan>>((
  ref,
) async {
  try {
    return await ref.watch(modToolsRepositoryProvider).myBans();
  } on Object {
    return const [];
  }
});

/// A thread conversation's lock; null for anything that is not a circle
/// thread (or when it cannot be read: the server still enforces the lock).
final threadLockProvider = FutureProvider.autoDispose
    .family<ThreadLockState?, String>((ref, conversationId) async {
      try {
        return await ref
            .watch(modToolsRepositoryProvider)
            .threadLockState(conversationId);
      } on Object {
        return null;
      }
    });
