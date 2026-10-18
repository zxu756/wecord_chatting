import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/insights/insights_models.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

/// Who may open Insights: members with manage_circle or view_audit_log
/// (the owner and administrators have every permission). The server decides
/// again on every call.
extension CircleInsightsPermissions on CircleDetail {
  bool get canViewInsights =>
      can(CirclePermission.manageCircle) || can(CirclePermission.viewAuditLog);
}

/// The ranges the page offers, in days.
const insightRanges = <int>[7, 30, 90];

/// The calls behind the Insights page and the invite list.
class CircleInsightsRepository {
  const CircleInsightsRepository(this._rpc);

  final CircleRpc _rpc;

  /// The numbers for the last [rangeDays] days up to yesterday. The weekday
  /// by hour map is shifted by [tzOffset] so busy hours read in local time.
  Future<CircleInsights> load(
    String circleId, {
    int rangeDays = 30,
    Duration tzOffset = Duration.zero,
  }) async {
    final result = await _rpc('get_circle_insights', {
      'target_circle_id': circleId,
      'range_days': rangeDays,
      'tz_offset_minutes': tzOffset.inMinutes,
    });
    return CircleInsights.fromJson(rpcObject(result));
  }

  /// How many people each invite link brought and how many are still in the
  /// circle, by invite code. Links the caller cannot list are missing.
  Future<Map<String, InviteStats>> inviteStats(String circleId) async {
    final result = await _rpc('get_circle_invite_stats', {
      'target_circle_id': circleId,
    });
    return {
      for (final row in rpcRows(result))
        row['code'] as String: InviteStats(
          brought: (row['brought'] as num?)?.toInt() ?? 0,
          remaining: (row['remaining'] as num?)?.toInt() ?? 0,
        ),
    };
  }
}

final circleInsightsRepositoryProvider = Provider<CircleInsightsRepository>((
  ref,
) {
  return CircleInsightsRepository(ref.watch(circleRpcProvider));
});

/// The insights of a circle for a range in days.
final circleInsightsProvider = FutureProvider.autoDispose
    .family<CircleInsights, ({String circleId, int rangeDays})>((ref, key) {
      return ref
          .watch(circleInsightsRepositoryProvider)
          .load(
            key.circleId,
            rangeDays: key.rangeDays,
            tzOffset: DateTime.now().timeZoneOffset,
          );
    });
