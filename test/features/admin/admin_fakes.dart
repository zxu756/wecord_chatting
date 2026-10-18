import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// A report as admin_list_reports returns it.
Map<String, dynamic> adminReportJson(
  String id, {
  String kind = 'user',
  String status = 'open',
  String reason = 'spam',
  String details = '',
  String title = 'Eve Adams (@eve)',
  String reporter = 'dee',
  int repeat = 1,
  String createdAt = '2026-10-20T09:00:00Z',
  String? resolution,
  String? handledBy,
}) => {
  'id': id,
  'kind': kind,
  'status': status,
  'reason': reason,
  'details': details,
  'created_at': createdAt,
  'handled_at': status == 'open' ? null : '2026-10-20T10:00:00Z',
  'handled_by_username': handledBy,
  'resolution': resolution,
  'title': title,
  'subject_id': 'subject-$id',
  'responsible_user_id': 'user-eve',
  'reporter': {
    'id': 'user-$reporter',
    'username': reporter,
    'display_name': reporter.toUpperCase(),
  },
  'repeat_count': repeat,
};

/// A report as admin_get_report returns it.
Map<String, dynamic> adminDetailJson(
  String id, {
  String kind = 'post',
  String status = 'open',
  Map<String, dynamic>? snapshot,
  Map<String, dynamic>? subject,
  Map<String, dynamic>? responsible,
  List<Map<String, dynamic>> history = const [],
  List<Map<String, dynamic>> actions = const [],
  int repeat = 1,
  String details = 'Selling pills in a circle post',
}) {
  final snapshots = {
    'post': {
      'kind': 'post',
      'title': 'buy my pills',
      'body': 'buy my pills, DM me',
      'author_username': 'eve',
      'author_display_name': 'Eve Adams',
      'circle_name': 'Pixel Painters',
      'created_at': '2026-10-19T08:00:00Z',
      'attachment': null,
    },
    'circle': {
      'kind': 'circle',
      'title': 'Free Gift Cards',
      'name': 'Free Gift Cards',
      'owner_username': 'eve',
      'member_count': 12,
      'is_public': true,
      'created_at': '2026-10-01T08:00:00Z',
      'description': 'Click the link for free gift cards',
    },
    'user': {
      'kind': 'user',
      'title': 'Eve Adams (@eve)',
      'username': 'eve',
      'display_name': 'Eve Adams',
      'bio': 'DM me for crypto tips',
      'created_at': '2026-09-01T08:00:00Z',
    },
  };
  final subjects = {
    'post': {
      'type': 'post',
      'id': 'subject-$id',
      'deleted': false,
      'circle_id': 'circle-1',
      'circle_name': 'Pixel Painters',
      'circle_disabled_mode': null,
    },
    'circle': {
      'type': 'circle',
      'id': 'subject-$id',
      'name': 'Free Gift Cards',
      'disabled_mode': null,
    },
    'user': {'type': 'user'},
  };
  return {
    'report': {
      ...adminReportJson(
        id,
        kind: kind,
        status: status,
        title: (snapshots[kind]!['title'] as String),
        repeat: repeat,
        details: details,
        reason: 'spam',
      ),
      'snapshot': snapshot ?? snapshots[kind],
    },
    'subject': subject ?? subjects[kind],
    'responsible_user': responsible ?? adminPersonJson(),
    'history': history,
    'actions': actions,
    'reporter_stats': {'total': 4, 'dismissed': 1},
  };
}

Map<String, dynamic> adminPersonJson({
  String id = 'user-eve',
  String username = 'eve',
  String displayName = 'Eve Adams',
  bool suspended = false,
  bool admin = false,
}) => {
  'id': id,
  'username': username,
  'display_name': displayName,
  'created_at': '2026-09-01T08:00:00Z',
  'is_suspended': suspended,
  'suspended_until': null,
  'suspension_reason': suspended ? 'harassment' : null,
  'is_admin': admin,
  'reports_against': 3,
  'open_reports_against': 2,
};

Map<String, dynamic> adminAuditJson(
  String id,
  String action, {
  String actor = 'mia',
  String title = '@eve',
  String reason = 'harassment',
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'action': action,
  'actor_id': 'user-$actor',
  'actor_username': actor,
  'actor_role': 'moderator',
  'target_type': 'user',
  'target_id': 'user-eve',
  'report_id': null,
  'details': {'title': title, 'reason': reason, ...extra},
  'created_at': '2026-10-20T10:00:00Z',
};

/// Answers the admin calls and records them. Anything it has no answer for
/// fails, like an offline server.
class FakeAdminBackend {
  FakeAdminBackend({this.role = 'moderator'});

  /// The caller's admin role, null for a normal user.
  String? role;
  var reports = <Map<String, dynamic>>[];
  var audit = <Map<String, dynamic>>[];
  final details = <String, Map<String, dynamic>>{};
  var takedowns = <Map<String, dynamic>>[];
  Object? functionError;

  /// Makes the report queue fail (an offline server) until cleared.
  var failReports = false;
  var failTakedowns = false;

  final rpcCalls = <(String, Map<String, dynamic>)>[];
  final functionCalls = <(String, Map<String, dynamic>)>[];

  Future<Object?> rpc(String name, Map<String, dynamic> params) async {
    rpcCalls.add((name, params));
    switch (name) {
      case 'admin_my_role':
        return role;
      case 'admin_list_reports':
        if (failReports) {
          throw StateError('Check your connection');
        }
        final kind = params['kind_filter'] as String?;
        final status = params['status_filter'] as String?;
        final before = params['before_created_at'] as String?;
        return [
          for (final report in reports)
            if ((kind == null || report['kind'] == kind) &&
                (status == 'handled'
                    ? report['status'] != 'open'
                    : report['status'] == 'open') &&
                (before == null ||
                    (report['created_at'] as String).compareTo(before) < 0))
              report,
        ].take(params['page_size'] as int).toList();
      case 'admin_get_report':
        final detail = details[params['target_report_id']];
        if (detail == null) {
          throw StateError('Report not found');
        }
        return detail;
      case 'admin_list_audit_log':
        return audit;
      case 'my_circle_takedowns':
        if (failTakedowns) {
          throw StateError('Check your connection');
        }
        return takedowns;
      case 'admin_resolve_report':
      case 'admin_disable_circle':
      case 'admin_enable_circle':
      case 'admin_delete_circle_post':
        return null;
    }
    throw StateError('Supabase must be initialized first.');
  }

  Future<Object?> function(String name, Map<String, dynamic> body) async {
    functionCalls.add((name, body));
    final error = functionError;
    if (error != null) {
      throw error;
    }
    return switch (body['action']) {
      'attachment_url' => {'url': 'https://example.test/picture.png'},
      _ => {'suspended': true},
    };
  }

  /// Only the calls, for tests that bring their own signed-in person.
  List<Override> get callOverrides => [
    circleRpcProvider.overrideWithValue(rpc),
    circleFunctionProvider.overrideWithValue(function),
  ];

  List<Override> get overrides => [
    authStateProvider.overrideWith(
      (ref) => Stream.value(const AuthUser(id: 'user-1')),
    ),
    ...callOverrides,
  ];

  Iterable<Map<String, dynamic>> calls(String name) => [
    for (final (called, params) in rpcCalls)
      if (called == name) params,
  ];
}
