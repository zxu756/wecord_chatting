import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/admin/admin_ops_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

Map<String, dynamic> flagJson(
  String key, {
  String description = '',
  bool enabled = true,
  int percent = 50,
  List<String> allow = const [],
  String minVersion = '',
}) => {
  'key': key,
  'description': description,
  'enabled': enabled,
  'rollout_percent': percent,
  'allow_usernames': allow,
  'min_version': minVersion,
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> noticeJson(
  String id, {
  String titleEn = 'Maintenance tonight',
  String titleZh = '今晚维护',
  String bodyEn = 'We pause at 22:00.',
  String bodyZh = '22:00 暂停服务。',
  bool push = false,
  bool pushDone = false,
  String? retractedAt,
  int read = 12,
  int dismissed = 3,
  String publishedAt = '2026-10-20T09:00:00Z',
}) => {
  'id': id,
  'title_en': titleEn,
  'title_zh': titleZh,
  'body_en': bodyEn,
  'body_zh': bodyZh,
  'push': push,
  'push_done': pushDone,
  'published_at': publishedAt,
  'retracted_at': retractedAt,
  'read_count': read,
  'dismissed_count': dismissed,
};

Map<String, dynamic> feedbackJson(
  String id, {
  String username = 'ada',
  String message = 'The send button is hidden',
  String platform = 'web',
  String version = '1.4.0',
  bool screenshot = false,
  String status = 'open',
  String? repliedAt,
  String createdAt = '2026-10-20T09:00:00Z',
}) => {
  'id': id,
  'user_id': 'user-$username',
  'username': username,
  'display_name': username.toUpperCase(),
  'message': message,
  'app_version': version,
  'platform': platform,
  'has_screenshot': screenshot,
  'status': status,
  'replied_at': repliedAt,
  'created_at': createdAt,
};

/// Answers the admin calls of flags, notices and feedback and records them.
class FakeOpsBackend {
  FakeOpsBackend({this.role = 'owner'});

  String? role;
  var flags = <Map<String, dynamic>>[];
  var minVersions = <String, String>{};
  var notices = <Map<String, dynamic>>[];
  var feedback = <Map<String, dynamic>>[];
  final details = <String, Map<String, dynamic>>{};

  /// Makes the next call named here fail with this error.
  final failures = <String, Object>{};

  final rpcCalls = <(String, Map<String, dynamic>)>[];
  final signedPaths = <String>[];

  Future<Object?> rpc(String name, Map<String, dynamic> params) async {
    rpcCalls.add((name, params));
    final failure = failures.remove(name);
    if (failure != null) {
      throw failure;
    }
    switch (name) {
      case 'admin_my_role':
        return role;
      case 'admin_list_feature_flags':
        return flags;
      case 'admin_get_min_versions':
        return minVersions;
      case 'admin_set_feature_flag':
      case 'admin_delete_feature_flag':
        return null;
      case 'admin_set_min_version':
        final platform = params['client_platform'] as String;
        final minimum = params['minimum'] as String;
        if (minimum.isEmpty) {
          minVersions.remove(platform);
        } else {
          minVersions[platform] = minimum;
        }
        return null;
      case 'admin_list_announcements':
        return notices;
      case 'admin_publish_announcement':
      case 'admin_retract_announcement':
        return null;
      case 'admin_list_feedback':
        final status = params['status_filter'] as String?;
        return [
          for (final item in feedback)
            if (status == 'all' || item['status'] == status) item,
        ];
      case 'admin_get_feedback':
        final detail = details[params['target_feedback_id']];
        if (detail == null) {
          throw PostgrestException(message: 'Feedback not found');
        }
        return detail;
      case 'admin_reply_feedback':
      case 'admin_close_feedback':
        return null;
    }
    throw StateError('Supabase must be initialized first.');
  }

  Iterable<Map<String, dynamic>> calls(String name) => [
    for (final (called, params) in rpcCalls)
      if (called == name) params,
  ];

  /// Only the calls, for tests that bring their own signed-in person.
  List<Override> get callOverrides => [
    circleRpcProvider.overrideWithValue(rpc),
    feedbackScreenshotUrlProvider.overrideWithValue((path) async {
      signedPaths.add(path);
      return 'https://example.test/screenshot.jpg?path=$path';
    }),
  ];

  List<Override> get overrides => [
    authStateProvider.overrideWith(
      (ref) => Stream.value(const AuthUser(id: 'user-1')),
    ),
    ...callOverrides,
  ];
}

Map<String, dynamic> feedbackDetailJson(
  String id, {
  String username = 'ada',
  String message = 'The send button is hidden',
  String? screenshotPath,
  String status = 'open',
  List<Map<String, dynamic>> replies = const [],
}) => {
  'id': id,
  'user_id': 'user-$username',
  'username': username,
  'display_name': username.toUpperCase(),
  'message': message,
  'app_version': '1.4.0',
  'platform': 'web',
  'screenshot_path': screenshotPath,
  'status': status,
  'replied_at': null,
  'created_at': '2026-10-20T09:00:00Z',
  'replies': replies,
};
