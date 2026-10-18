import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/report_reason.dart';

/// What a platform admin may do (app_admins.role).
enum AdminRole {
  owner('owner'),
  moderator('moderator'),
  support('support');

  const AdminRole(this.value);

  final String value;

  /// Owners and moderators may suspend people, take circles down and delete
  /// posts; support staff only read and close reports.
  bool get canSanction => this != AdminRole.support;

  static AdminRole? parse(Object? value) {
    for (final role in values) {
      if (role.value == value) {
        return role;
      }
    }
    return null;
  }

  String get label => switch (this) {
    owner => trIn('Admin', 'Owner'),
    moderator => tr('Moderator'),
    support => tr('Support'),
  };
}

/// What a report is about.
enum ReportKind {
  user('user'),
  circle('circle'),
  post('post'),
  message('message');

  const ReportKind(this.value);

  final String value;

  static ReportKind parse(Object? value) {
    for (final kind in values) {
      if (kind.value == value) {
        return kind;
      }
    }
    return ReportKind.user;
  }

  String get label => switch (this) {
    user => tr('People'),
    circle => tr('Circles'),
    post => tr('Posts'),
    message => trIn('Admin', 'Messages'),
  };

  String get singular => switch (this) {
    user => tr('Person'),
    circle => tr('Circle'),
    post => trIn('Admin', 'Post'),
    message => tr('Message'),
  };
}

/// Which reports the queue lists.
enum ReportQueueStatus {
  open('open'),
  handled('handled');

  const ReportQueueStatus(this.value);

  final String value;

  String get label => switch (this) {
    open => trIn('Admin', 'Open'),
    handled => tr('Handled'),
  };
}

/// How an admin closed a report (reports.resolution).
enum ReportResolution {
  noViolation('no_violation'),
  duplicate('duplicate'),
  contentRemoved('content_removed'),
  userSuspended('user_suspended'),
  circleDelisted('circle_delisted'),
  circleSuspended('circle_suspended'),
  other('other');

  const ReportResolution(this.value);

  final String value;

  static ReportResolution? parse(Object? value) {
    for (final resolution in values) {
      if (resolution.value == value) {
        return resolution;
      }
    }
    return null;
  }

  String get label => switch (this) {
    noViolation => tr('No violation'),
    duplicate => trIn('Admin', 'Duplicate'),
    contentRemoved => tr('Content removed'),
    userSuspended => tr('Person suspended'),
    circleDelisted => tr('Circle delisted'),
    circleSuspended => tr('Circle suspended'),
    other => tr('Handled'),
  };
}

/// The two ways of taking a circle down.
enum CircleTakedownMode {
  /// Hidden from Discover and closed to new members; members keep using it.
  delist('delist'),

  /// Nobody can enter or read.
  suspend('suspend');

  const CircleTakedownMode(this.value);

  final String value;

  static CircleTakedownMode? parse(Object? value) {
    for (final mode in values) {
      if (mode.value == value) {
        return mode;
      }
    }
    return null;
  }

  String get label => switch (this) {
    delist => tr('Delisted'),
    suspend => tr('Suspended'),
  };
}

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

String _reasonLabel(String value) {
  for (final reason in ReportReason.values) {
    if (reason.value == value) {
      return reason.label;
    }
  }
  return value;
}

/// One row of the report queue.
class AdminReport {
  const AdminReport({
    required this.id,
    required this.kind,
    required this.status,
    required this.reason,
    required this.details,
    required this.createdAt,
    required this.title,
    required this.subjectId,
    required this.reporterName,
    required this.repeatCount,
    this.handledAt,
    this.handledBy,
    this.resolution,
  });

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    final reporter = json['reporter'];
    final reporterMap = reporter is Map ? reporter : const {};
    final display = _string(reporterMap['display_name']);
    final username = _string(reporterMap['username']);
    return AdminReport(
      id: _string(json['id']),
      kind: ReportKind.parse(json['kind']),
      status: _string(json['status'], 'open'),
      reason: _string(json['reason'], 'other'),
      details: _string(json['details']),
      createdAt: _time(json['created_at']) ?? DateTime.now(),
      title: _string(json['title']),
      subjectId: json['subject_id'] is String
          ? json['subject_id'] as String
          : null,
      reporterName: display.isNotEmpty
          ? display
          : (username.isNotEmpty ? '@$username' : tr('Someone')),
      repeatCount: json['repeat_count'] is int
          ? json['repeat_count'] as int
          : 1,
      handledAt: _time(json['handled_at']),
      handledBy: json['handled_by_username'] is String
          ? json['handled_by_username'] as String
          : null,
      resolution: ReportResolution.parse(json['resolution']),
    );
  }

  final String id;
  final ReportKind kind;

  /// open, reviewed or dismissed.
  final String status;
  final String reason;
  final String details;
  final DateTime createdAt;

  /// A short label of what was reported, from the snapshot.
  final String title;
  final String? subjectId;
  final String reporterName;

  /// Open reports about the same subject (this one included).
  final int repeatCount;
  final DateTime? handledAt;
  final String? handledBy;
  final ReportResolution? resolution;

  bool get isOpen => status == 'open';

  String get reasonLabel => _reasonLabel(reason);
}

/// The person who answers for a report: the reported person, a circle's
/// owner, a post's author.
class AdminPerson {
  const AdminPerson({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isSuspended,
    required this.isAdmin,
    required this.reportsAgainst,
    required this.openReportsAgainst,
    this.suspendedUntil,
    this.suspensionReason,
  });

  factory AdminPerson.fromJson(Map<String, dynamic> json) => AdminPerson(
    id: _string(json['id']),
    username: _string(json['username']),
    displayName: _string(json['display_name']),
    isSuspended: json['is_suspended'] == true,
    isAdmin: json['is_admin'] == true,
    reportsAgainst: json['reports_against'] is int
        ? json['reports_against'] as int
        : 0,
    openReportsAgainst: json['open_reports_against'] is int
        ? json['open_reports_against'] as int
        : 0,
    suspendedUntil: _time(json['suspended_until']),
    suspensionReason: json['suspension_reason'] is String
        ? json['suspension_reason'] as String
        : null,
  );

  final String id;
  final String username;
  final String displayName;
  final bool isSuspended;
  final bool isAdmin;
  final int reportsAgainst;
  final int openReportsAgainst;
  final DateTime? suspendedUntil;
  final String? suspensionReason;

  String get name => displayName.isNotEmpty ? displayName : '@$username';
}

/// An earlier report about the same subject.
class AdminReportHistoryEntry {
  const AdminReportHistoryEntry({
    required this.id,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.resolution,
  });

  factory AdminReportHistoryEntry.fromJson(Map<String, dynamic> json) =>
      AdminReportHistoryEntry(
        id: _string(json['id']),
        reason: _string(json['reason'], 'other'),
        status: _string(json['status'], 'open'),
        createdAt: _time(json['created_at']) ?? DateTime.now(),
        resolution: ReportResolution.parse(json['resolution']),
      );

  final String id;
  final String reason;
  final String status;
  final DateTime createdAt;
  final ReportResolution? resolution;

  String get reasonLabel => _reasonLabel(reason);
}

/// One thing an admin did before (the audit log, narrowed to a subject).
class AdminAuditEntry {
  const AdminAuditEntry({
    required this.id,
    required this.action,
    required this.actor,
    required this.targetType,
    required this.createdAt,
    required this.details,
    this.actorRole,
    this.targetId,
    this.reportId,
  });

  factory AdminAuditEntry.fromJson(Map<String, dynamic> json) {
    final details = json['details'];
    return AdminAuditEntry(
      id: _string(json['id']),
      action: _string(json['action']),
      actor: _string(json['actor_username']),
      actorRole: AdminRole.parse(json['actor_role']),
      targetType: _string(json['target_type']),
      targetId: json['target_id'] is String
          ? json['target_id'] as String
          : null,
      reportId: json['report_id'] is String
          ? json['report_id'] as String
          : null,
      createdAt: _time(json['created_at']) ?? DateTime.now(),
      details: details is Map ? Map<String, dynamic>.from(details) : const {},
    );
  }

  final String id;
  final String action;
  final String actor;
  final AdminRole? actorRole;
  final String targetType;
  final String? targetId;
  final String? reportId;
  final DateTime createdAt;
  final Map<String, dynamic> details;

  String get title => _string(details['title']);
  String get reason => _string(details['reason']);
}

/// A report with everything the admin needs to decide.
class AdminReportDetail {
  const AdminReportDetail({
    required this.report,
    required this.snapshot,
    required this.subject,
    required this.responsible,
    required this.history,
    required this.actions,
    required this.reporterTotal,
    required this.reporterDismissed,
  });

  factory AdminReportDetail.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<Map<String, dynamic>> list(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
    ];
    final reportJson = map(json['report']);
    final stats = map(json['reporter_stats']);
    final responsible = map(json['responsible_user']);
    return AdminReportDetail(
      report: AdminReport.fromJson(reportJson),
      snapshot: map(reportJson['snapshot']),
      subject: map(json['subject']),
      responsible: responsible.isEmpty
          ? null
          : AdminPerson.fromJson(responsible),
      history: [
        for (final entry in list(json['history']))
          AdminReportHistoryEntry.fromJson(entry),
      ],
      actions: [
        for (final entry in list(json['actions']))
          AdminAuditEntry.fromJson(entry),
      ],
      reporterTotal: stats['total'] is int ? stats['total'] as int : 0,
      reporterDismissed: stats['dismissed'] is int
          ? stats['dismissed'] as int
          : 0,
    );
  }

  final AdminReport report;

  /// A copy of what was reported, taken when it was reported.
  final Map<String, dynamic> snapshot;

  /// Non-content facts about the subject as it is now.
  final Map<String, dynamic> subject;
  final AdminPerson? responsible;
  final List<AdminReportHistoryEntry> history;
  final List<AdminAuditEntry> actions;
  final int reporterTotal;
  final int reporterDismissed;

  ReportKind get kind => report.kind;

  /// The circle involved (the reported circle, or the post's circle).
  String? get circleId => switch (kind) {
    ReportKind.circle => report.subjectId,
    ReportKind.post => subject['circle_id'] as String?,
    _ => null,
  };

  /// The take-down state of the circle involved, if it is down.
  CircleTakedownMode? get circleMode => CircleTakedownMode.parse(
    kind == ReportKind.circle
        ? subject['disabled_mode']
        : subject['circle_disabled_mode'],
  );

  bool get postDeleted => subject['deleted'] == true;
  bool get subjectMissing => subject['missing'] == true;
}

/// A circle of the caller that an admin took down.
class CircleTakedown {
  const CircleTakedown({required this.circleId, required this.mode});

  final String circleId;
  final CircleTakedownMode mode;
}
