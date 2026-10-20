import 'package:flutter/foundation.dart';
import 'package:wecord/features/admin/admin_stats_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

String _string(Object? value) => value is String ? value : '';

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

num _num(Object? value) => value is num ? value : 0;

/// How a check came out.
enum OpsCheckStatus {
  ok('ok'),
  warn('warn'),
  fail('fail'),

  /// It could not look (a part it needs is not there).
  unknown('unknown');

  const OpsCheckStatus(this.value);

  final String value;

  static OpsCheckStatus parse(Object? value) {
    for (final status in values) {
      if (status.value == value) {
        return status;
      }
    }
    return OpsCheckStatus.unknown;
  }

  String get label => switch (this) {
    ok => trIn('Check', 'OK'),
    warn => tr('Warning'),
    fail => tr('Failing'),
    unknown => tr('Unknown'),
  };
}

/// The latest result of one check (`admin_list_ops_checks`).
@immutable
class OpsCheck {
  const OpsCheck({
    required this.key,
    required this.status,
    required this.detail,
    required this.checkedAt,
    required this.changedAt,
  });

  factory OpsCheck.fromJson(Map<String, dynamic> json) {
    return OpsCheck(
      key: _string(json['key']),
      status: OpsCheckStatus.parse(json['status']),
      detail: _map(json['detail']),
      checkedAt: _time(json['checked_at']),
      changedAt: _time(json['changed_at']),
    );
  }

  final String key;
  final OpsCheckStatus status;
  final Map<String, dynamic> detail;
  final DateTime? checkedAt;
  final DateTime? changedAt;

  /// What the check looks at, in words.
  String get label => switch (key) {
    'cron_dispatch' => tr('Scheduled tasks'),
    'cron_failures' => tr('Failed cron jobs'),
    'edge_wakes' => tr('Edge Function calls'),
    'push_failures' => tr('Push delivery'),
    'error_spike' => tr('Error reports'),
    'ai_quota' => tr('AI limits'),
    'version_health' => tr('App versions'),
    'new_errors' => tr('New kinds of error'),
    _ => key,
  };

  /// One line of what it found.
  String get summary {
    if (status == OpsCheckStatus.unknown) {
      return tr('Cannot be checked right now.');
    }
    return switch (key) {
      'cron_dispatch' =>
        detail['minutes_since_success'] is num
            ? tr('Last good run {minutes} min ago', {
                'minutes': _num(detail['minutes_since_success']).toInt(),
              })
            : tr('No good run on record'),
      'cron_failures' => tr('{count} failed runs in 30 min', {
        'count': _num(detail['failed_runs']).toInt(),
      }),
      'edge_wakes' => tr('{failed} of {calls} calls failed in 15 min', {
        'failed': _num(detail['failed']).toInt(),
        'calls': _num(detail['calls']).toInt(),
      }),
      'push_failures' => tr('{failed} of {attempts} pushes failed in an hour', {
        'failed': _num(detail['failed']).toInt(),
        'attempts': _num(detail['attempts']).toInt(),
      }),
      'error_spike' => tr('{count} reports in the last hour', {
        'count': _num(detail['last_hour']).toInt(),
      }),
      'ai_quota' => tr('{circles} circles and {people} people at their limit', {
        'circles': _num(detail['circles_at_limit']).toInt(),
        'people': _num(detail['people_at_limit']).toInt(),
      }),
      'version_health' =>
        _string(detail['app_version']).isEmpty
            ? tr('No version has enough people yet')
            : tr('{version}: {crashed} of {active} people crashed', {
                'version': _string(detail['app_version']),
                'crashed': _num(detail['crash_users']).toInt(),
                'active': _num(detail['active_users']).toInt(),
              }),
      'new_errors' => tr('{count} new groups', {
        'count': _num(detail['new_groups']).toInt(),
      }),
      _ => '',
    };
  }
}

/// All the checks and when they last ran.
@immutable
class OpsChecks {
  const OpsChecks({required this.checks, this.now, this.heartbeatAt});

  factory OpsChecks.fromJson(Map<String, dynamic> json) {
    return OpsChecks(
      now: _time(json['now']),
      heartbeatAt: _time(json['heartbeat_at']),
      checks: [
        if (json['checks'] is List)
          for (final check in json['checks'] as List)
            if (check is Map)
              OpsCheck.fromJson(Map<String, dynamic>.from(check)),
      ],
    );
  }

  final List<OpsCheck> checks;

  /// The server's clock when it answered, so the age of the heartbeat does
  /// not depend on this device's clock.
  final DateTime? now;

  /// When the checks last ran; null if they never have.
  final DateTime? heartbeatAt;

  /// Minutes since the checks ran, or null if they never have.
  int? get minutesSinceHeartbeat {
    final beat = heartbeatAt;
    final reference = now;
    if (beat == null || reference == null) {
      return null;
    }
    return reference.difference(beat).inMinutes;
  }

  /// The checks run every 5 minutes; this much silence means they stopped
  /// (they run from cron, so a stopped cron looks exactly like this).
  bool get stale {
    final minutes = minutesSinceHeartbeat;
    return minutes == null || minutes >= 15;
  }
}

/// An alert (`admin_list_ops_alerts`).
@immutable
class OpsAlert {
  const OpsAlert({
    required this.id,
    required this.checkKey,
    required this.isEvent,
    required this.isFailure,
    required this.titleEn,
    required this.titleZh,
    required this.bodyEn,
    required this.bodyZh,
    required this.openedAt,
    this.updatedAt,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.resolvedAt,
    this.resolvedBy,
    this.resolution,
    this.reopenCount = 0,
  });

  factory OpsAlert.fromJson(Map<String, dynamic> json) {
    return OpsAlert(
      id: _string(json['id']),
      checkKey: _string(json['check_key']),
      isEvent: json['kind'] == 'event',
      isFailure: json['severity'] == 'fail',
      titleEn: _string(json['title_en']),
      titleZh: _string(json['title_zh']),
      bodyEn: _string(json['body_en']),
      bodyZh: _string(json['body_zh']),
      openedAt:
          _time(json['opened_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _time(json['updated_at']),
      acknowledgedAt: _time(json['acknowledged_at']),
      acknowledgedBy: json['acknowledged_by'] is String
          ? json['acknowledged_by'] as String
          : null,
      resolvedAt: _time(json['resolved_at']),
      resolvedBy: json['resolved_by'] is String
          ? json['resolved_by'] as String
          : null,
      resolution: json['resolution'] is String
          ? json['resolution'] as String
          : null,
      reopenCount: json['reopen_count'] is num
          ? (json['reopen_count'] as num).toInt()
          : 0,
    );
  }

  final String id;
  final String checkKey;

  /// An event (a new kind of error) rather than a state that can recover.
  final bool isEvent;
  final bool isFailure;
  final String titleEn;
  final String titleZh;
  final String bodyEn;
  final String bodyZh;
  final DateTime openedAt;
  final DateTime? updatedAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  /// 'auto' (it recovered or the day passed) or 'manual' (an admin).
  final String? resolution;
  final int reopenCount;

  bool get isOpen => resolvedAt == null;

  String title({required bool chinese}) =>
      _pick(chinese ? titleZh : titleEn, chinese ? titleEn : titleZh);

  String body({required bool chinese}) =>
      _pick(chinese ? bodyZh : bodyEn, chinese ? bodyEn : bodyZh);

  static String _pick(String wanted, String other) =>
      wanted.trim().isNotEmpty ? wanted.trim() : other.trim();
}

/// One group of error reports (`admin_ops_error_groups`).
@immutable
class OpsErrorGroup {
  const OpsErrorGroup({
    required this.groupKey,
    required this.label,
    required this.kind,
    required this.occurrences,
    required this.reports,
    required this.people,
    required this.firstVersion,
    required this.latestVersion,
    required this.isNew,
    this.lastSeenAt,
  });

  factory OpsErrorGroup.fromJson(Map<String, dynamic> json) {
    return OpsErrorGroup(
      groupKey: _string(json['group_key']),
      label: _string(json['label']),
      kind: _string(json['kind']),
      occurrences: _num(json['occurrences']).toInt(),
      reports: _num(json['reports']).toInt(),
      people: _num(json['people']).toInt(),
      firstVersion: _string(json['first_version']),
      latestVersion: _string(json['latest_version']),
      isNew: json['is_new'] == true,
      lastSeenAt: _time(json['last_seen_at']),
    );
  }

  final String groupKey;

  /// "kind | type | function @ library", already free of any data.
  final String label;
  final String kind;
  final int occurrences;
  final int reports;
  final int people;
  final String firstVersion;
  final String latestVersion;
  final bool isNew;
  final DateTime? lastSeenAt;

  /// The label without its kind (the kind is shown on its own).
  String get what {
    final parts = label.split(' | ');
    return parts.length > 1 ? parts.sublist(1).join(' · ') : label;
  }

  String get occurrencesText => opsNumber(occurrences);
}
