import 'package:flutter/foundation.dart';

int _int(Object? value) => value is num ? value.toInt() : 0;

int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

String _string(Object? value) => value is String ? value : '';

Map<String, int> _counts(Object? value) => {
  if (value is Map)
    for (final entry in value.entries)
      if (entry.key is String && entry.value is num)
        entry.key as String: (entry.value as num).toInt(),
};

/// One UTC day of the product numbers (`ops_daily_metrics`): counts only.
@immutable
class OpsDay {
  const OpsDay({
    required this.day,
    this.activeUsers = 0,
    this.newUsers = 0,
    this.d1Retained,
    this.d7Retained,
    this.d30Retained,
    this.messagesTotal = 0,
    this.messagesByType = const {},
    this.featureCounts = const {},
    this.voiceMinutes = 0,
    this.aiRequests = 0,
    this.aiUsers = 0,
    this.pushSent = 0,
    this.pushFailed = 0,
    this.pushGone = 0,
    this.errorReports = 0,
    this.storageBytes,
    this.storageAdded,
  });

  factory OpsDay.fromJson(Map<String, dynamic> json) {
    return OpsDay(
      day:
          DateTime.tryParse(_string(json['day'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      activeUsers: _int(json['active_users']),
      newUsers: _int(json['new_users']),
      d1Retained: _intOrNull(json['d1_retained']),
      d7Retained: _intOrNull(json['d7_retained']),
      d30Retained: _intOrNull(json['d30_retained']),
      messagesTotal: _int(json['messages_total']),
      messagesByType: _counts(json['messages_by_type']),
      featureCounts: _counts(json['feature_counts']),
      voiceMinutes: _int(json['voice_minutes']),
      aiRequests: _int(json['ai_requests']),
      aiUsers: _int(json['ai_users']),
      pushSent: _int(json['push_sent']),
      pushFailed: _int(json['push_failed']),
      pushGone: _int(json['push_gone']),
      errorReports: _int(json['error_reports']),
      storageBytes: _intOrNull(json['storage_bytes']),
      storageAdded: _intOrNull(json['storage_added']),
    );
  }

  final DateTime day;
  final int activeUsers;
  final int newUsers;

  /// How many of this day's new people were active 1, 7 and 30 days later;
  /// null until that later day is over.
  final int? d1Retained;
  final int? d7Retained;
  final int? d30Retained;
  final int messagesTotal;
  final Map<String, int> messagesByType;
  final Map<String, int> featureCounts;
  final int voiceMinutes;
  final int aiRequests;
  final int aiUsers;
  final int pushSent;
  final int pushFailed;
  final int pushGone;
  final int errorReports;
  final int? storageBytes;
  final int? storageAdded;
}

/// How one app version on one platform is doing over the last 7 days.
@immutable
class OpsVersion {
  const OpsVersion({
    required this.appVersion,
    required this.platform,
    required this.activeUsers,
    required this.crashUsers,
    required this.crashReports,
  });

  factory OpsVersion.fromJson(Map<String, dynamic> json) {
    return OpsVersion(
      appVersion: _string(json['app_version']),
      platform: _string(json['platform']),
      activeUsers: _int(json['active_users']),
      crashUsers: _int(json['crash_users']),
      crashReports: _int(json['crash_reports']),
    );
  }

  final String appVersion;
  final String platform;
  final int activeUsers;
  final int crashUsers;
  final int crashReports;

  /// The share of people on this version who did not hit a crash, 0 to 1.
  double get crashFree => activeUsers <= 0
      ? 1
      : (1 - crashUsers / activeUsers).clamp(0.0, 1.0).toDouble();
}

/// What `admin_ops_metrics` answers.
@immutable
class OpsMetrics {
  const OpsMetrics({
    required this.days,
    required this.versions,
    this.wau = 0,
    this.mau = 0,
  });

  factory OpsMetrics.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    return OpsMetrics(
      days: [
        if (json['days'] is List)
          for (final day in json['days'] as List)
            if (day is Map) OpsDay.fromJson(Map<String, dynamic>.from(day)),
      ],
      versions: [
        if (json['versions'] is List)
          for (final version in json['versions'] as List)
            if (version is Map)
              OpsVersion.fromJson(Map<String, dynamic>.from(version)),
      ],
      wau: summary is Map ? _int(summary['wau']) : 0,
      mau: summary is Map ? _int(summary['mau']) : 0,
    );
  }

  /// Oldest first.
  final List<OpsDay> days;
  final List<OpsVersion> versions;

  /// People active in the last 7 and 30 days (distinct people).
  final int wau;
  final int mau;

  OpsDay? get latest => days.isEmpty ? null : days.last;

  int _sum(int Function(OpsDay day) pick) =>
      days.fold<int>(0, (total, day) => total + pick(day));

  int get totalMessages => _sum((day) => day.messagesTotal);
  int get totalNewUsers => _sum((day) => day.newUsers);
  int get totalVoiceMinutes => _sum((day) => day.voiceMinutes);
  int get totalAiRequests => _sum((day) => day.aiRequests);
  int get totalPushSent => _sum((day) => day.pushSent);
  int get totalPushFailed => _sum((day) => day.pushFailed);
  int get totalPushGone => _sum((day) => day.pushGone);
  int get totalErrorReports => _sum((day) => day.errorReports);
  int get totalStorageAdded => _sum((day) => day.storageAdded ?? 0);

  /// The newest storage total there is.
  int? get storageBytes {
    for (final day in days.reversed) {
      if (day.storageBytes != null) {
        return day.storageBytes;
      }
    }
    return null;
  }

  /// Messages by type over the whole range, biggest first.
  List<MapEntry<String, int>> get messagesByType {
    final totals = <String, int>{};
    for (final day in days) {
      day.messagesByType.forEach((type, count) {
        totals[type] = (totals[type] ?? 0) + count;
      });
    }
    return totals.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// How often each feature was used over the whole range, biggest first.
  List<MapEntry<String, int>> get featureCounts {
    final totals = <String, int>{};
    for (final day in days) {
      day.featureCounts.forEach((feature, count) {
        totals[feature] = (totals[feature] ?? 0) + count;
      });
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// The days with new people, newest first, for the retention table.
  List<OpsDay> get cohorts => [
    for (final day in days.reversed)
      if (day.newUsers > 0) day,
  ];
}

/// "1,234" for a count.
String opsNumber(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(digits[i]);
  }
  return out.toString();
}

/// "42%" for [part] of [whole], or a dash when there is nothing to compare.
String opsPercent(int? part, int whole) {
  if (part == null || whole <= 0) {
    return '–';
  }
  return '${(100 * part / whole).round()}%';
}

/// "12.3 MB" for a size in bytes.
String opsBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.abs().toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final text = unit == 0 || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '${bytes < 0 ? '-' : ''}$text ${units[unit]}';
}
