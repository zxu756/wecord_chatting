import 'package:flutter/foundation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

String _string(Object? value) => value is String ? value : '';

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// The platforms a minimum version can be set for ('all' is every one).
const adminPlatforms = [
  'all',
  'web',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
];

String adminPlatformLabel(String platform) => switch (platform) {
  'all' => tr('All platforms'),
  'web' => tr('Web'),
  'ios' => 'iOS',
  'android' => 'Android',
  'macos' => 'macOS',
  'windows' => 'Windows',
  'linux' => 'Linux',
  _ => platform,
};

/// A feature flag as the console lists it (`admin_list_feature_flags`).
@immutable
class AdminFlag {
  const AdminFlag({
    required this.key,
    required this.description,
    required this.enabled,
    required this.rolloutPercent,
    required this.allowUsernames,
    required this.minVersion,
  });

  factory AdminFlag.fromJson(Map<String, dynamic> json) {
    final allow = json['allow_usernames'];
    return AdminFlag(
      key: _string(json['key']),
      description: _string(json['description']),
      enabled: json['enabled'] == true,
      rolloutPercent: json['rollout_percent'] is num
          ? (json['rollout_percent'] as num).toInt()
          : 0,
      allowUsernames: [
        if (allow is List)
          for (final name in allow)
            if (name is String) name,
      ],
      minVersion: _string(json['min_version']),
    );
  }

  final String key;
  final String description;
  final bool enabled;
  final int rolloutPercent;
  final List<String> allowUsernames;
  final String minVersion;
}

/// A notice for everybody, as the console lists it
/// (`admin_list_announcements`).
@immutable
class AdminNotice {
  const AdminNotice({
    required this.id,
    required this.titleEn,
    required this.titleZh,
    required this.bodyEn,
    required this.bodyZh,
    required this.push,
    required this.pushDone,
    required this.publishedAt,
    required this.retractedAt,
    required this.readCount,
    required this.dismissedCount,
  });

  factory AdminNotice.fromJson(Map<String, dynamic> json) {
    int count(String key) => json[key] is num ? (json[key] as num).toInt() : 0;
    return AdminNotice(
      id: _string(json['id']),
      titleEn: _string(json['title_en']),
      titleZh: _string(json['title_zh']),
      bodyEn: _string(json['body_en']),
      bodyZh: _string(json['body_zh']),
      push: json['push'] == true,
      pushDone: json['push_done'] == true,
      publishedAt: _time(json['published_at']) ?? DateTime.now(),
      retractedAt: _time(json['retracted_at']),
      readCount: count('read_count'),
      dismissedCount: count('dismissed_count'),
    );
  }

  final String id;
  final String titleEn;
  final String titleZh;
  final String bodyEn;
  final String bodyZh;
  final bool push;
  final bool pushDone;
  final DateTime publishedAt;
  final DateTime? retractedAt;
  final int readCount;
  final int dismissedCount;

  bool get isRetracted => retractedAt != null;

  /// A title to list it by: English, else Chinese.
  String get title => titleEn.trim().isNotEmpty ? titleEn : titleZh;

  String get body => bodyEn.trim().isNotEmpty ? bodyEn : bodyZh;
}

/// One piece of feedback in the queue (`admin_list_feedback`).
@immutable
class AdminFeedback {
  const AdminFeedback({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.message,
    required this.appVersion,
    required this.platform,
    required this.hasScreenshot,
    required this.closed,
    required this.repliedAt,
    required this.createdAt,
  });

  factory AdminFeedback.fromJson(Map<String, dynamic> json) {
    return AdminFeedback(
      id: _string(json['id']),
      userId: _string(json['user_id']),
      username: _string(json['username']),
      displayName: _string(json['display_name']),
      message: _string(json['message']),
      appVersion: _string(json['app_version']),
      platform: _string(json['platform']),
      hasScreenshot: json['has_screenshot'] == true,
      closed: json['status'] == 'closed',
      repliedAt: _time(json['replied_at']),
      createdAt: _time(json['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String message;
  final String appVersion;
  final String platform;
  final bool hasScreenshot;
  final bool closed;
  final DateTime? repliedAt;
  final DateTime createdAt;

  /// "web 1.4.0" (what the app sent), or ''.
  String get appLabel =>
      [platform, appVersion].where((part) => part.trim().isNotEmpty).join(' ');
}

/// A reply the team sent (a notice for the one person).
@immutable
class AdminFeedbackReply {
  const AdminFeedbackReply({
    required this.id,
    required this.body,
    required this.publishedAt,
    required this.retracted,
  });

  factory AdminFeedbackReply.fromJson(Map<String, dynamic> json) {
    return AdminFeedbackReply(
      id: _string(json['id']),
      body: _string(json['body']),
      publishedAt: _time(json['published_at']) ?? DateTime.now(),
      retracted: json['retracted_at'] != null,
    );
  }

  final String id;
  final String body;
  final DateTime publishedAt;
  final bool retracted;
}

/// Feedback with its screenshot and replies (`admin_get_feedback`).
@immutable
class AdminFeedbackDetail {
  const AdminFeedbackDetail({
    required this.feedback,
    required this.screenshotPath,
    required this.replies,
  });

  factory AdminFeedbackDetail.fromJson(Map<String, dynamic> json) {
    final replies = json['replies'];
    final path = _string(json['screenshot_path']);
    return AdminFeedbackDetail(
      feedback: AdminFeedback.fromJson({
        ...json,
        'has_screenshot': path.isNotEmpty,
      }),
      screenshotPath: path.isEmpty ? null : path,
      replies: [
        if (replies is List)
          for (final reply in replies)
            if (reply is Map)
              AdminFeedbackReply.fromJson(Map<String, dynamic>.from(reply)),
      ],
    );
  }

  final AdminFeedback feedback;
  final String? screenshotPath;
  final List<AdminFeedbackReply> replies;
}

/// Which feedback the queue lists.
enum FeedbackQueueStatus {
  open('open'),
  closed('closed'),
  all('all');

  const FeedbackQueueStatus(this.value);

  final String value;

  String get label => switch (this) {
    open => trIn('Admin', 'Open'),
    closed => trIn('Feedback', 'Closed'),
    all => tr('All'),
  };
}
