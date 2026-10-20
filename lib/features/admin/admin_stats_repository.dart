import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_alerts_models.dart';
import 'package:wecord/features/admin/admin_stats_models.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// The ranges the Stats tab offers, in days.
const opsRanges = <int>[7, 30, 90];

/// The calls behind the console's Stats and Alerts tabs (K2, K3, K5). The
/// server checks the role on every one of them: any admin reads, owners and
/// moderators acknowledge and close alerts.
class AdminStatsRepository {
  const AdminStatsRepository(this._rpc);

  final CircleRpc _rpc;

  /// The product numbers for the last [rangeDays] days.
  Future<OpsMetrics> metrics({int rangeDays = 30}) async {
    final result = await _rpc('admin_ops_metrics', {'range_days': rangeDays});
    return OpsMetrics.fromJson(rpcObject(result));
  }

  Future<OpsChecks> checks() async {
    final result = await _rpc('admin_list_ops_checks', const {});
    return OpsChecks.fromJson(rpcObject(result));
  }

  /// A page of alerts, newest first. Pass the last alert's `openedAt` as
  /// [before] for the next page.
  Future<List<OpsAlert>> alerts({
    bool resolved = false,
    DateTime? before,
    int pageSize = 30,
  }) async {
    final rows = await _rpc('admin_list_ops_alerts', {
      'status_filter': resolved ? 'resolved' : 'open',
      'page_size': pageSize,
      'before_opened_at': before?.toUtc().toIso8601String(),
    });
    return [for (final row in rpcRows(rows)) OpsAlert.fromJson(row)];
  }

  Future<void> acknowledge(String alertId) async {
    await _rpc('admin_ack_ops_alert', {'target_alert_id': alertId});
  }

  Future<void> resolve(String alertId) async {
    await _rpc('admin_resolve_ops_alert', {'target_alert_id': alertId});
  }

  /// The biggest groups of error reports of the last [hours] hours.
  Future<List<OpsErrorGroup>> errorGroups({
    int hours = 24,
    int maxRows = 10,
  }) async {
    final rows = await _rpc('admin_ops_error_groups', {
      'hours': hours,
      'max_rows': maxRows,
    });
    return [for (final row in rpcRows(rows)) OpsErrorGroup.fromJson(row)];
  }
}

final adminStatsRepositoryProvider = Provider<AdminStatsRepository>((ref) {
  return AdminStatsRepository(ref.watch(circleRpcProvider));
});
