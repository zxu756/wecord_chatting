import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/member_honors/honor_models.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

/// Who may give titles: members who manage nicknames, to themselves or to a
/// member ranked below them (the owner outranks everyone). The server decides
/// again on every call.
extension MemberTitlePermissions on CircleDetail {
  bool canSetTitle(CircleMember member) {
    if (!can(CirclePermission.manageNicknames)) {
      return false;
    }
    return member.isCurrentUser || rankOf(member) < currentUserRank;
  }
}

/// The calls behind titles and honors.
class MemberHonorsRepository {
  const MemberHonorsRepository(this._rpc);

  final CircleRpc _rpc;

  /// Titles and shown honors of the members who have any. Empty when the
  /// call fails (a title is a nicety, not worth an error next to a name).
  Future<Map<String, MemberFlair>> listFlair(String circleId) async {
    try {
      final rows = await _rpc('list_circle_member_flair', {
        'target_circle_id': circleId,
      });
      return {
        for (final row in rpcRows(rows))
          if (row['user_id'] is String)
            row['user_id'] as String: MemberFlair.fromJson(row),
      };
    } catch (_) {
      return const {};
    }
  }

  /// The Honors page; null while the circle is suspended.
  Future<CircleHonors?> load(String circleId) async {
    final result = await _rpc('get_circle_honors', {
      'target_circle_id': circleId,
    });
    if (result is! Map) {
      return null;
    }
    return CircleHonors.fromJson(Map<String, dynamic>.from(result));
  }

  /// Gives [userId] a title; blank takes it off. Returns the stored title.
  Future<String?> setTitle({
    required String circleId,
    required String userId,
    required String title,
  }) async {
    final trimmed = title.trim();
    final result = await _rpc('set_circle_member_title', {
      'target_circle_id': circleId,
      'target_user_id': userId,
      'member_title': trimmed.isEmpty ? null : trimmed,
    });
    return result is String && result.isNotEmpty ? result : null;
  }

  Future<bool> setCircleHonors(String circleId, {required bool on}) async {
    final result = await _rpc('set_circle_honors_enabled', {
      'target_circle_id': circleId,
      'honors_on': on,
    });
    return result == true;
  }

  Future<bool> setParticipation(String circleId, {required bool on}) async {
    final result = await _rpc('set_my_honors_participation', {
      'target_circle_id': circleId,
      'take_part': on,
    });
    return result == true;
  }
}

final memberHonorsRepositoryProvider = Provider<MemberHonorsRepository>((ref) {
  return MemberHonorsRepository(ref.watch(circleRpcProvider));
});

/// The titles and shown honors of a circle's members, by user id. Loaded once
/// for every name on screen; failures show nothing.
final circleMemberFlairProvider = FutureProvider.autoDispose
    .family<Map<String, MemberFlair>, String>((ref, circleId) {
      return ref.watch(memberHonorsRepositoryProvider).listFlair(circleId);
    });

/// The Honors page of a circle.
final circleHonorsProvider = FutureProvider.autoDispose
    .family<CircleHonors?, String>((ref, circleId) {
      return ref.watch(memberHonorsRepositoryProvider).load(circleId);
    });
