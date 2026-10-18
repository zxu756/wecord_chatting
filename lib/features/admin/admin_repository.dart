import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The admin console's calls: the admin RPCs, and the `admin` Edge Function
/// for what needs the service role (banning). Every one of them is checked
/// by the server; the app only hides what a normal person cannot use.
class AdminRepository {
  const AdminRepository(this._rpc, this._function);

  final CircleRpc _rpc;
  final CircleFunction _function;

  /// The caller's admin role, or null for everybody else.
  Future<AdminRole?> myRole() async =>
      AdminRole.parse(await _rpc('admin_my_role', const {}));

  /// A page of the report queue, newest first. Pass the last report's
  /// `createdAt` as [before] for the next page.
  Future<List<AdminReport>> listReports({
    ReportKind? kind,
    ReportQueueStatus status = ReportQueueStatus.open,
    DateTime? before,
    int pageSize = 30,
  }) async {
    // Reports of messages in direct chats and groups have a queue of their
    // own (migration 202610220120).
    final rows = kind == ReportKind.message
        ? await _rpc('admin_list_message_reports', {
            'status_filter': status.value,
            'page_size': pageSize,
            'before_created_at': before?.toUtc().toIso8601String(),
          })
        : await _rpc('admin_list_reports', {
            'kind_filter': kind?.value,
            'status_filter': status.value,
            'page_size': pageSize,
            'before_created_at': before?.toUtc().toIso8601String(),
          });
    return [for (final row in rpcRows(rows)) AdminReport.fromJson(row)];
  }

  Future<AdminReportDetail> reportDetail(
    String reportId, {
    bool message = false,
  }) async {
    return AdminReportDetail.fromJson(
      rpcObject(
        await _rpc(message ? 'admin_get_message_report' : 'admin_get_report', {
          'target_report_id': reportId,
        }),
      ),
    );
  }

  /// Closes a report of a message: [action] is 'dismiss', 'delete_message'
  /// or 'suspend' (after the person was suspended).
  Future<void> resolveMessageReport({
    required String reportId,
    required String action,
    String note = '',
  }) async {
    await _rpc('admin_resolve_message_report', {
      'target_report_id': reportId,
      'action': action,
      'note': note.trim(),
    });
  }

  /// Closes a report: [dismissed] for "no violation", else "reviewed".
  Future<void> resolveReport({
    required String reportId,
    required bool dismissed,
    required ReportResolution resolution,
    String note = '',
  }) async {
    await _rpc('admin_resolve_report', {
      'target_report_id': reportId,
      'new_status': dismissed ? 'dismissed' : 'reviewed',
      'resolution': resolution.value,
      'note': note.trim(),
    });
  }

  /// Suspends a person: recorded in the database, then banned in Auth with
  /// their sessions ended, by the `admin` function. [until] null is for good.
  Future<void> suspendUser({
    required String userId,
    required String reason,
    DateTime? until,
    String? reportId,
  }) async {
    await _function('admin', {
      'action': 'suspend_user',
      'user_id': userId,
      'reason': reason.trim(),
      'until': until?.toUtc().toIso8601String(),
      'report_id': reportId,
    });
  }

  Future<void> unsuspendUser({
    required String userId,
    String reason = '',
  }) async {
    await _function('admin', {
      'action': 'unsuspend_user',
      'user_id': userId,
      'reason': reason.trim(),
    });
  }

  Future<void> disableCircle({
    required String circleId,
    required CircleTakedownMode mode,
    required String reason,
    String? reportId,
  }) async {
    await _rpc('admin_disable_circle', {
      'target_circle_id': circleId,
      'mode': mode.value,
      'reason': reason.trim(),
      'report_id': reportId,
    });
  }

  Future<void> enableCircle({
    required String circleId,
    String reason = '',
  }) async {
    await _rpc('admin_enable_circle', {
      'target_circle_id': circleId,
      'reason': reason.trim(),
    });
  }

  Future<void> deletePost({
    required String postId,
    required String reason,
    String? reportId,
  }) async {
    await _rpc('admin_delete_circle_post', {
      'target_post_id': postId,
      'reason': reason.trim(),
      'report_id': reportId,
    });
  }

  /// A page of the audit log, newest first.
  Future<List<AdminAuditEntry>> listAuditLog({
    DateTime? before,
    int pageSize = 50,
  }) async {
    final rows = await _rpc('admin_list_audit_log', {
      'page_size': pageSize,
      'before_created_at': before?.toUtc().toIso8601String(),
    });
    return [for (final row in rpcRows(rows)) AdminAuditEntry.fromJson(row)];
  }

  /// A short link to the picture of a reported post (from the report's
  /// snapshot), or null when there is none.
  Future<String?> attachmentUrl(String reportId) async {
    final result = await _function('admin', {
      'action': 'attachment_url',
      'report_id': reportId,
    });
    return result is Map && result['url'] is String
        ? result['url'] as String
        : null;
  }

  /// The caller's circles that an admin took down.
  Future<List<CircleTakedown>> myCircleTakedowns() async {
    final rows = await _rpc('my_circle_takedowns', const {});
    return [
      for (final row in rpcRows(rows))
        if (row['circle_id'] is String &&
            CircleTakedownMode.parse(row['mode']) != null)
          CircleTakedown(
            circleId: row['circle_id'] as String,
            mode: CircleTakedownMode.parse(row['mode'])!,
          ),
    ];
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(
    ref.watch(circleRpcProvider),
    ref.watch(circleFunctionProvider),
  );
});

/// The signed-in person's admin role, or null. Reloads when the account
/// changes; a failed lookup counts as "not an admin" (the server decides
/// anyway).
final adminRoleProvider = FutureProvider<AdminRole?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return null;
  }
  try {
    return await ref.watch(adminRepositoryProvider).myRole();
  } catch (_) {
    return null;
  }
});

/// The circles of the signed-in person that an admin took down, by id.
final circleTakedownsProvider =
    FutureProvider.autoDispose<Map<String, CircleTakedownMode>>((ref) async {
      final takedowns = await ref
          .watch(adminRepositoryProvider)
          .myCircleTakedowns();
      return {for (final item in takedowns) item.circleId: item.mode};
    });

/// What to tell an admin about a failed action: the server's own reason
/// when it gave one, else a plain sentence for the `admin` function's codes.
String adminErrorText(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final code = details is Map ? details['error'] : null;
    final message = details is Map ? details['message'] : null;
    switch (code) {
      case 'ban_failed':
        return tr(
          'The suspension was saved, but the account could not be banned. '
          'Try again.',
        );
      case 'sessions_failed':
        return tr(
          'The account is banned, but its sessions could not be ended. '
          'Try again.',
        );
      case 'unban_failed':
        return tr(
          'The suspension was lifted, but the ban could not be removed. '
          'Try again.',
        );
      case 'forbidden':
        // A server sentence ("Admins cannot be suspended") has spaces; a
        // field name does not.
        return message is String && message.contains(' ')
            ? tr(message)
            : tr('You are not allowed to do that.');
      case 'bad_request':
        return message is String && message.contains(' ')
            ? tr(message)
            : tr('Check the details and try again.');
      case 'not_found':
      case 'no_attachment':
        return tr('Not found.');
    }
  }
  return errorText(error);
}
