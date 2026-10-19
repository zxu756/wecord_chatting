import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:wecord/features/admin/admin_ops_models.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// A short-lived link to a screenshot of the private feedback bucket. Only
/// a platform admin gets one (the bucket's policy).
typedef FeedbackScreenshotUrl = Future<String> Function(String path);

/// The admin console's calls for flags, notices and feedback (K4, K6, K7).
/// The server checks the role on every one of them; the console only hides
/// what the role cannot use.
class AdminOpsRepository {
  const AdminOpsRepository(this._rpc, this._screenshotUrl);

  final CircleRpc _rpc;
  final FeedbackScreenshotUrl _screenshotUrl;

  // ---- Feature flags and the minimum version (K4).

  Future<List<AdminFlag>> listFlags() async {
    final rows = await _rpc('admin_list_feature_flags', const {});
    return [for (final row in rpcRows(rows)) AdminFlag.fromJson(row)];
  }

  /// Creates or changes a flag. [allowUsernames] must all exist.
  Future<void> saveFlag({
    required String key,
    required String description,
    required bool enabled,
    required int rolloutPercent,
    required List<String> allowUsernames,
    required String minVersion,
  }) async {
    await _rpc('admin_set_feature_flag', {
      'flag_key': key.trim(),
      'flag_description': description.trim(),
      'flag_enabled': enabled,
      'flag_rollout_percent': rolloutPercent,
      'allow_usernames': allowUsernames,
      'flag_min_version': minVersion.trim(),
    });
  }

  Future<void> deleteFlag(String key) async {
    await _rpc('admin_delete_feature_flag', {'flag_key': key});
  }

  /// Platform to minimum version; platforms without one are left out.
  Future<Map<String, String>> minVersions() async {
    final result = await _rpc('admin_get_min_versions', const {});
    return {
      if (result is Map)
        for (final entry in result.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
    };
  }

  /// Sets the minimum for [platform] ('all' for every one); '' clears it.
  Future<void> setMinVersion(String platform, String minimum) async {
    await _rpc('admin_set_min_version', {
      'client_platform': platform,
      'minimum': minimum.trim(),
    });
  }

  // ---- Official notices (K6).

  Future<List<AdminNotice>> listNotices({
    DateTime? before,
    int pageSize = 30,
  }) async {
    final rows = await _rpc('admin_list_announcements', {
      'page_size': pageSize,
      'before_published_at': before?.toUtc().toIso8601String(),
    });
    return [for (final row in rpcRows(rows)) AdminNotice.fromJson(row)];
  }

  Future<void> publishNotice({
    required String titleEn,
    required String titleZh,
    required String bodyEn,
    required String bodyZh,
    required bool push,
  }) async {
    await _rpc('admin_publish_announcement', {
      'title_en': titleEn.trim(),
      'title_zh': titleZh.trim(),
      'body_en': bodyEn.trim(),
      'body_zh': bodyZh.trim(),
      'send_push': push,
    });
  }

  Future<void> retractNotice(String id) async {
    await _rpc('admin_retract_announcement', {'target_announcement_id': id});
  }

  // ---- Feedback (K7).

  Future<List<AdminFeedback>> listFeedback({
    FeedbackQueueStatus status = FeedbackQueueStatus.open,
    DateTime? before,
    int pageSize = 30,
  }) async {
    final rows = await _rpc('admin_list_feedback', {
      'status_filter': status.value,
      'page_size': pageSize,
      'before_created_at': before?.toUtc().toIso8601String(),
    });
    return [for (final row in rpcRows(rows)) AdminFeedback.fromJson(row)];
  }

  Future<AdminFeedbackDetail> feedbackDetail(String id) async {
    final result = await _rpc('admin_get_feedback', {'target_feedback_id': id});
    return AdminFeedbackDetail.fromJson(rpcObject(result));
  }

  Future<void> replyToFeedback({
    required String id,
    required String text,
    required bool closeAfter,
  }) async {
    await _rpc('admin_reply_feedback', {
      'target_feedback_id': id,
      'reply_text': text.trim(),
      'close_after': closeAfter,
    });
  }

  Future<void> setFeedbackClosed(String id, {required bool closed}) async {
    await _rpc('admin_close_feedback', {
      'target_feedback_id': id,
      'closed': closed,
    });
  }

  Future<String> screenshotUrl(String path) => _screenshotUrl(path);
}

final feedbackScreenshotUrlProvider = Provider<FeedbackScreenshotUrl>((ref) {
  return (path) async {
    try {
      return await ref
          .read(supabaseClientProvider)
          .storage
          .from('feedback-screenshots')
          .createSignedUrl(path, 300);
    } on ProviderException {
      throw StateError('Supabase must be initialized first.');
    }
  };
});

final adminOpsRepositoryProvider = Provider<AdminOpsRepository>((ref) {
  return AdminOpsRepository(
    ref.watch(circleRpcProvider),
    ref.watch(feedbackScreenshotUrlProvider),
  );
});
