import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// A date in October 2026, for a day of the month.
String _day(int day) => '2026-10-${day.toString().padLeft(2, '0')}';

/// One day of the product numbers as the server sends it.
Map<String, dynamic> opsDayJson(
  int day, {
  int active = 20,
  int newUsers = 0,
  int? d1,
  int? d7,
  int? d30,
  int messages = 400,
  Map<String, int>? byType,
  Map<String, int>? features,
  int voice = 45,
  int ai = 12,
  int pushSent = 90,
  int pushFailed = 3,
  int pushGone = 1,
  int errors = 4,
  int? storage,
  int? storageAdded,
}) => {
  'day': _day(day),
  'active_users': active,
  'new_users': newUsers,
  'd1_retained': d1,
  'd7_retained': d7,
  'd30_retained': d30,
  'messages_total': messages,
  'messages_by_type':
      byType ?? {'text': messages - 60, 'image': 40, 'voice': 20},
  'feature_counts':
      features ?? {'circle_posts': 5, 'moments': 9, 'stories': 3, 'tasks': 2},
  'voice_minutes': voice,
  'ai_requests': ai,
  'ai_users': 4,
  'push_sent': pushSent,
  'push_failed': pushFailed,
  'push_gone': pushGone,
  'error_reports': errors,
  'storage_bytes': storage,
  'storage_added': storageAdded,
};

/// Ten days, the last one today, with a few sign-ups to follow.
Map<String, dynamic> opsMetricsJson({List<Map<String, dynamic>>? days}) => {
  'generated_at': '2026-10-20T10:00:00Z',
  'days':
      days ??
      [
        for (var d = 11; d <= 20; d++)
          opsDayJson(
            d,
            active: 14 + d % 5,
            newUsers: d == 15 ? 8 : (d == 18 ? 4 : 0),
            d1: d == 15 ? 4 : null,
            d7: null,
            d30: null,
            storage: d == 19 ? 1500 * 1024 * 1024 : null,
            storageAdded: d == 19 ? 12 * 1024 * 1024 : null,
          ),
      ],
  'summary': {'wau': 31, 'mau': 58},
  'versions': [
    {
      'app_version': '1.4.2',
      'platform': 'ios',
      'active_users': 20,
      'crash_users': 3,
      'crash_reports': 5,
    },
    {
      'app_version': '1.4.1',
      'platform': 'web',
      'active_users': 40,
      'crash_users': 0,
      'crash_reports': 0,
    },
    {
      'app_version': '1.3.9',
      'platform': 'macos',
      'active_users': 10,
      'crash_users': 2,
      'crash_reports': 2,
    },
  ],
};

Map<String, dynamic> opsCheckJson(
  String key, {
  String status = 'ok',
  Map<String, dynamic> detail = const {},
}) => {
  'key': key,
  'status': status,
  'detail': detail,
  'checked_at': '2026-10-20T09:58:00Z',
  'changed_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> opsChecksJson({
  String? heartbeat = '2026-10-20T09:58:00Z',
  String now = '2026-10-20T10:00:00Z',
  List<Map<String, dynamic>>? checks,
}) => {
  'now': now,
  'heartbeat_at': heartbeat,
  'checks':
      checks ??
      [
        opsCheckJson(
          'cron_dispatch',
          status: 'fail',
          detail: {'minutes_since_success': 13},
        ),
        opsCheckJson('cron_failures', detail: {'failed_runs': 0}),
        opsCheckJson(
          'edge_wakes',
          status: 'unknown',
          detail: {'reason': 'pg_net is not installed'},
        ),
        opsCheckJson('push_failures', detail: {'attempts': 90, 'failed': 3}),
        opsCheckJson(
          'error_spike',
          status: 'warn',
          detail: {'last_hour': 41, 'hourly_average': 2.0},
        ),
        opsCheckJson(
          'ai_quota',
          detail: {'circles_at_limit': 0, 'people_at_limit': 1},
        ),
        opsCheckJson(
          'version_health',
          detail: {
            'app_version': '1.4.2',
            'platform': 'ios',
            'active_users': 20,
            'crash_users': 3,
          },
        ),
        opsCheckJson('new_errors', detail: {'new_groups': 0}),
      ],
};

Map<String, dynamic> opsAlertJson(
  String id, {
  String checkKey = 'cron_dispatch',
  String kind = 'state',
  String severity = 'fail',
  String titleEn = 'Scheduled tasks have stopped',
  String titleZh = '定时任务停了',
  String bodyEn =
      'The every-minute dispatcher (wecord-later-dispatch) has not '
      'finished a run for 13 minutes.',
  String bodyZh = '每分钟的调度任务已有 13 分钟没有成功运行。',
  String openedAt = '2026-10-20T09:45:00Z',
  String? acknowledgedAt,
  String? acknowledgedBy,
  String? resolvedAt,
  String? resolvedBy,
  String? resolution,
  int reopenCount = 0,
}) => {
  'id': id,
  'check_key': checkKey,
  'kind': kind,
  'severity': severity,
  'title_en': titleEn,
  'title_zh': titleZh,
  'body_en': bodyEn,
  'body_zh': bodyZh,
  'detail': <String, dynamic>{},
  'opened_at': openedAt,
  'updated_at': openedAt,
  'acknowledged_at': acknowledgedAt,
  'acknowledged_by': acknowledgedBy,
  'resolved_at': resolvedAt,
  'resolved_by': resolvedBy,
  'resolution': resolution,
  'reopen_count': reopenCount,
};

Map<String, dynamic> opsErrorGroupJson(
  String key, {
  String label =
      'flutter_error | Bad state: No element N | _ChatState.build @ '
      'package:wecord/features/chats/chat.dart',
  String kind = 'flutter_error',
  int occurrences = 38,
  int reports = 12,
  int people = 5,
  bool isNew = false,
  String lastSeenAt = '2026-10-20T09:30:00Z',
}) => {
  'group_key': key,
  'label': label,
  'kind': kind,
  'occurrences': occurrences,
  'reports': reports,
  'people': people,
  'first_seen_at': '2026-10-19T09:00:00Z',
  'last_seen_at': lastSeenAt,
  'first_version': '1.4.1',
  'latest_version': '1.4.2',
  'is_new': isNew,
};

/// Answers the admin calls of the Stats and Alerts tabs and records them.
class FakeMetricsBackend {
  FakeMetricsBackend({this.role = 'owner'});

  String? role;
  Map<String, dynamic> metrics = opsMetricsJson();
  Map<String, dynamic> checks = opsChecksJson();
  List<Map<String, dynamic>> openAlerts = [];
  List<Map<String, dynamic>> closedAlerts = [];
  List<Map<String, dynamic>> errorGroups = [];

  /// Makes the next call named here fail with this error.
  final failures = <String, Object>{};

  final rpcCalls = <(String, Map<String, dynamic>)>[];

  Future<Object?> rpc(String name, Map<String, dynamic> params) async {
    rpcCalls.add((name, params));
    final failure = failures.remove(name);
    if (failure != null) {
      throw failure;
    }
    switch (name) {
      case 'admin_my_role':
        return role;
      case 'admin_list_reports':
      case 'admin_list_audit_log':
        return <Map<String, dynamic>>[];
      case 'admin_ops_metrics':
        return metrics;
      case 'admin_list_ops_checks':
        return checks;
      case 'admin_list_ops_alerts':
        return params['status_filter'] == 'resolved'
            ? closedAlerts
            : openAlerts;
      case 'admin_ops_error_groups':
        return errorGroups;
      case 'admin_ack_ops_alert':
        final id = params['target_alert_id'];
        openAlerts = [
          for (final alert in openAlerts)
            if (alert['id'] == id)
              {
                ...alert,
                'acknowledged_at': '2026-10-20T10:00:00Z',
                'acknowledged_by': 'root',
              }
            else
              alert,
        ];
        return null;
      case 'admin_resolve_ops_alert':
        final id = params['target_alert_id'];
        final closed = [
          for (final alert in openAlerts)
            if (alert['id'] == id)
              {
                ...alert,
                'resolved_at': '2026-10-20T10:00:00Z',
                'resolved_by': 'root',
                'resolution': 'manual',
              },
        ];
        openAlerts = [
          for (final alert in openAlerts)
            if (alert['id'] != id) alert,
        ];
        closedAlerts = [...closed, ...closedAlerts];
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
  ];

  List<Override> get overrides => [
    authStateProvider.overrideWith(
      (ref) => Stream.value(const AuthUser(id: 'user-1')),
    ),
    ...callOverrides,
  ];
}

/// A backend with trouble: two alerts, one acknowledged, a closed one, and
/// the error groups of the day.
///
/// [clock] is the "now" the times are counted back from; the tests that open
/// the console by its route cannot give it a fixed clock, so they pass the
/// real one and the cards read the same whatever the day.
FakeMetricsBackend opsMetricsShowcase({
  String role = 'owner',
  DateTime? clock,
}) {
  final base = (clock ?? DateTime.utc(2026, 10, 20, 10)).toUtc();
  String ago(Duration duration) => base.subtract(duration).toIso8601String();
  return FakeMetricsBackend(role: role)
    ..checks = opsChecksJson(
      now: base.toIso8601String(),
      heartbeat: ago(const Duration(minutes: 2)),
    )
    ..openAlerts = [
      opsAlertJson('a1', openedAt: ago(const Duration(minutes: 15))),
      opsAlertJson(
        'a2',
        checkKey: 'error_spike',
        severity: 'warn',
        titleEn: 'Error reports are spiking',
        titleZh: '错误报告激增',
        bodyEn: '41 error reports in the last hour, against about 2.0 an hour.',
        bodyZh: '最近一小时收到 41 条错误报告，前一天平均每小时约 2.0 条。',
        openedAt: ago(const Duration(minutes: 30)),
        acknowledgedAt: ago(const Duration(minutes: 20)),
        acknowledgedBy: 'mia',
        reopenCount: 1,
      ),
      opsAlertJson(
        'a3',
        checkKey: 'new_error_aaaaaaaa11111111',
        kind: 'event',
        severity: 'warn',
        titleEn: 'New kind of error: flutter_error',
        titleZh: '出现新的错误类型：flutter_error',
        bodyEn:
            'flutter_error | Bad state | _ChatState.build @ '
            'package:wecord/features/chats/chat.dart. First seen in version '
            '1.4.2, 3 reports so far.',
        bodyZh:
            'flutter_error | Bad state | _ChatState.build @ '
            'package:wecord/features/chats/chat.dart。首次出现在版本 1.4.2，目前已有 3 条报告。',
        openedAt: ago(const Duration(hours: 2)),
      ),
    ]
    ..closedAlerts = [
      opsAlertJson(
        'c1',
        checkKey: 'push_failures',
        titleEn: 'Many pushes are failing',
        titleZh: '大量推送失败',
        bodyEn: '30 of 40 pushes failed (75%) in the last hour or so.',
        bodyZh: '最近约一小时内 40 条推送中有 30 条失败（75%）。',
        openedAt: ago(const Duration(hours: 14)),
        resolvedAt: ago(const Duration(hours: 13)),
        resolution: 'auto',
      ),
      opsAlertJson(
        'c2',
        checkKey: 'ai_quota',
        severity: 'warn',
        titleEn: 'AI use is near its limit',
        titleZh: 'AI 用量接近上限',
        bodyEn: 'Today 0 circle(s) used up the AI guard’s daily limit.',
        bodyZh: '今天有 0 个圈子用完了 AI 守护的每日额度。',
        openedAt: ago(const Duration(days: 2, hours: 14)),
        resolvedAt: ago(const Duration(days: 2, hours: 12)),
        resolvedBy: 'root',
        resolution: 'manual',
      ),
    ]
    ..errorGroups = [
      opsErrorGroupJson(
        'aaaaaaaa11111111',
        isNew: true,
        lastSeenAt: ago(const Duration(minutes: 30)),
      ),
      opsErrorGroupJson(
        'bbbbbbbb11111111',
        label: 'rpc_error | status=N | rpc_error status=N',
        kind: 'rpc_error',
        occurrences: 1204,
        reports: 80,
        people: 22,
        lastSeenAt: ago(const Duration(minutes: 3)),
      ),
      opsErrorGroupJson(
        'cccccccc11111111',
        label:
            'platform_error | Null check operator used on a null value | '
            'Null check operator used on a null value',
        kind: 'platform_error',
        occurrences: 6,
        reports: 6,
        people: 1,
        lastSeenAt: ago(const Duration(hours: 5)),
      ),
    ];
}
