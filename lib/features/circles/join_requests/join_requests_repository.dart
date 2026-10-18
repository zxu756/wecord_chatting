import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

/// Who may review join requests: members who can remove members, the
/// permission that also lets an invite skip review.
extension JoinRequestPermissions on CircleDetail {
  bool get canReviewJoinRequests => can(CirclePermission.kickMembers);

  /// Whether the Review page has something for this member: held messages
  /// or join requests.
  bool get canOpenReview =>
      can(CirclePermission.manageMessages) || canReviewJoinRequests;

  /// Whether this member can make an invite that skips review: both
  /// create_invites and kick_members.
  bool get canSkipJoinReview =>
      canCreateInvites && can(CirclePermission.kickMembers);
}

/// The calls behind joining a circle that reviews who joins.
class JoinRequestsRepository {
  const JoinRequestsRepository(this._rpc);

  final CircleRpc _rpc;

  /// Where the current user stands in joining [circleId]; null when the
  /// circle is not theirs to see. [inviteCode] makes a private circle
  /// visible and says whether the invite skips review.
  Future<CircleJoinState?> getState(
    String circleId, {
    String? inviteCode,
  }) async {
    final result = await _rpc('get_circle_join_state', {
      'target_circle_id': circleId,
      'invite_code': ?inviteCode,
    });
    if (result is! Map) {
      return null;
    }
    return CircleJoinState.fromJson(Map<String, dynamic>.from(result));
  }

  /// Follows an invite. In a circle that reviews who joins this sends a
  /// request with [answers] (by question id) instead of joining; the answer
  /// to "where do I stand" is [getState]. Returns the circle id either way.
  Future<String> acceptInvite(
    String code, {
    Map<String, String> answers = const {},
  }) async {
    final circleId = await _rpc('accept_circle_invite', {
      'invite_code': code,
      'answers': joinAnswersJson(answers),
    });
    return circleId! as String;
  }

  /// Takes the request back.
  Future<void> cancel(String circleId) async {
    await _rpc('cancel_join_request', {'target_circle_id': circleId});
  }

  /// How many requests wait for the current user to review (0 without the
  /// permission).
  Future<int> count(String circleId) async {
    final result = await _rpc('count_join_requests', {
      'target_circle_id': circleId,
    });
    return (result as num?)?.toInt() ?? 0;
  }

  Future<List<PendingJoinRequest>> list(String circleId) async {
    final result = await _rpc('list_join_requests', {
      'target_circle_id': circleId,
    });
    return [
      for (final row in rpcRows(result)) PendingJoinRequest.fromJson(row),
    ];
  }

  /// Lets the person in ([approve]) or turns them down, with a note the
  /// person reads.
  Future<void> decide(
    String requestId, {
    required bool approve,
    String? note,
  }) async {
    final text = note?.trim() ?? '';
    await _rpc('decide_join_request', {
      'request_id': requestId,
      'approve': approve,
      if (text.isNotEmpty) 'decision_note': text,
    });
  }

  /// The current user's waiting requests and answers they have not
  /// dismissed.
  Future<List<MyJoinRequest>> listMine() async {
    final result = await _rpc('list_my_join_requests', const {});
    return [for (final row in rpcRows(result)) MyJoinRequest.fromJson(row)];
  }

  Future<void> dismiss(String requestId) async {
    await _rpc('dismiss_join_request_result', {'request_id': requestId});
  }

  Future<CircleJoinSettings> getSettings(String circleId) async {
    final result = await _rpc('get_circle_join_settings', {
      'target_circle_id': circleId,
    });
    return CircleJoinSettings.fromJson(rpcObject(result));
  }

  Future<void> saveSettings(
    String circleId,
    CircleJoinSettings settings,
  ) async {
    await _rpc('set_circle_join_settings', {
      'target_circle_id': circleId,
      'new_mode': settings.mode.key,
      'question_list': [
        for (final question in settings.questions) question.toJson(),
      ],
    });
  }

  /// The codes of the invites that skip review, newest first.
  Future<Set<String>> invitesSkippingReview(String circleId) async {
    final result = await _rpc('list_circle_invites_skipping_review', {
      'target_circle_id': circleId,
    });
    return {
      if (result is List)
        for (final code in result)
          if (code is String) code,
    };
  }

  /// Makes an invite; [skipReview] needs create_invites and kick_members.
  Future<String> createInvite({
    required String circleId,
    required bool skipReview,
    Duration? expiresIn,
    int? maxUses,
  }) async {
    final code = await _rpc('create_circle_invite_v2', {
      'target_circle_id': circleId,
      'expires_in_hours': expiresIn?.inHours,
      'max_uses': maxUses,
      'skip_review': skipReview,
    });
    return code! as String;
  }
}

final joinRequestsRepositoryProvider = Provider<JoinRequestsRepository>((ref) {
  return JoinRequestsRepository(ref.watch(circleRpcProvider));
});

/// A circle id and, from an invite page, the invite's code.
typedef JoinStateKey = ({String circleId, String? inviteCode});

/// Where the current user stands in joining a circle. Null when it cannot
/// be told; callers then join the way they always did and the server
/// decides.
final circleJoinStateProvider = FutureProvider.autoDispose
    .family<CircleJoinState?, JoinStateKey>((ref, key) async {
      try {
        return await ref
            .watch(joinRequestsRepositoryProvider)
            .getState(key.circleId, inviteCode: key.inviteCode);
      } on Object {
        return null;
      }
    });

/// The requests waiting for review in a circle.
final pendingJoinRequestsProvider = FutureProvider.autoDispose
    .family<List<PendingJoinRequest>, String>((ref, circleId) {
      return ref.watch(joinRequestsRepositoryProvider).list(circleId);
    });

/// How many requests wait, 0 without the permission or when it cannot be
/// read (for the badge on the circle's moderation tools).
final joinRequestCountProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, circleId) async {
    try {
      return await ref.watch(joinRequestsRepositoryProvider).count(circleId);
    } on Object {
      return 0;
    }
  },
);

/// The current user's own requests and unread answers, for Notifications.
final myJoinRequestsProvider = FutureProvider.autoDispose<List<MyJoinRequest>>((
  ref,
) async {
  try {
    return await ref.watch(joinRequestsRepositoryProvider).listMine();
  } on Object {
    return const [];
  }
});

/// Answers not dismissed yet, for the Notifications badge.
final joinRequestAnswersUnseenProvider = Provider.autoDispose<int>((ref) {
  final requests =
      ref.watch(myJoinRequestsProvider).value ?? const <MyJoinRequest>[];
  return requests
      .where((request) => request.status != JoinRequestStatus.pending)
      .length;
});

/// A circle's join mode and questions, for its settings.
final circleJoinSettingsProvider = FutureProvider.autoDispose
    .family<CircleJoinSettings, String>((ref, circleId) {
      return ref.watch(joinRequestsRepositoryProvider).getSettings(circleId);
    });
