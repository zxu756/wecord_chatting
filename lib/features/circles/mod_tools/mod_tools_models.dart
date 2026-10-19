import 'package:wecord/shared/l10n/l10n.dart';

/// What the moderator tools of a circle read and show (C5 and C6): the
/// filtered member list, notes and warnings, ban appeals, and the circle's
/// raid protection state. They mirror the RPCs of migrations 202610250200 to
/// 202610250280.

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// A row of `list_circle_members_for_moderation`: a member with what a
/// moderator filters on, and what the caller may do to them.
class ModMember {
  const ModMember({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.joinedAt,
    this.nickname,
    this.avatarUrl,
    this.role = 'member',
    this.accountCreatedAt,
    this.messageCount = 0,
    this.warningCount = 0,
    this.flagged = false,
    this.timedOutUntil,
    this.roleIds = const [],
    this.canTimeout = false,
    this.canKick = false,
    this.canBan = false,
  });

  factory ModMember.fromJson(Map<String, dynamic> json) {
    return ModMember(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['member_role'] as String? ?? 'member',
      joinedAt: _time(json['joined_at']) ?? DateTime.now(),
      accountCreatedAt: _time(json['account_created_at']),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      warningCount: (json['warning_count'] as num?)?.toInt() ?? 0,
      flagged: json['flagged'] == true,
      timedOutUntil: _time(json['timed_out_until']),
      roleIds: [
        if (json['role_ids'] is List)
          for (final id in json['role_ids'] as List)
            if (id is String) id,
      ],
      canTimeout: json['can_timeout'] == true,
      canKick: json['can_kick'] == true,
      canBan: json['can_ban'] == true,
    );
  }

  final String userId;
  final String username;
  final String displayName;
  final String? nickname;
  final String? avatarUrl;
  final String role;
  final DateTime joinedAt;
  final DateTime? accountCreatedAt;
  final int messageCount;
  final int warningCount;

  /// A warning, an open report, or a message the AI guard held or flagged.
  final bool flagged;
  final DateTime? timedOutUntil;
  final List<String> roleIds;
  final bool canTimeout;
  final bool canKick;
  final bool canBan;

  /// The circle nickname, then the display name, then the username.
  String get name {
    final nick = nickname?.trim() ?? '';
    if (nick.isNotEmpty) {
      return nick;
    }
    final display = displayName.trim();
    return display.isEmpty ? username : display;
  }

  /// Whether the caller may do anything to this member from the list.
  bool get actionable => canTimeout || canKick || canBan;
}

class ModMemberPage {
  const ModMemberPage({required this.members, required this.total});

  final List<ModMember> members;
  final int total;
}

/// The filters of the member list.
class ModMemberFilter {
  const ModMemberFilter({
    this.joinedWithinDays,
    this.joinedBeforeDays,
    this.accountWithinDays,
    this.minMessages,
    this.maxMessages,
    this.roleId,
    this.onlyFlagged = false,
    this.query = '',
  });

  final int? joinedWithinDays;
  final int? joinedBeforeDays;
  final int? accountWithinDays;
  final int? minMessages;
  final int? maxMessages;
  final String? roleId;
  final bool onlyFlagged;
  final String query;

  /// How many filters besides the search text are on.
  int get activeCount => [
    joinedWithinDays != null || joinedBeforeDays != null,
    accountWithinDays != null,
    minMessages != null || maxMessages != null,
    roleId != null,
    onlyFlagged,
  ].where((on) => on).length;

  ModMemberFilter copyWith({
    Object? joinedWithinDays = _keep,
    Object? joinedBeforeDays = _keep,
    Object? accountWithinDays = _keep,
    Object? minMessages = _keep,
    Object? maxMessages = _keep,
    Object? roleId = _keep,
    bool? onlyFlagged,
    String? query,
  }) {
    return ModMemberFilter(
      joinedWithinDays: identical(joinedWithinDays, _keep)
          ? this.joinedWithinDays
          : joinedWithinDays as int?,
      joinedBeforeDays: identical(joinedBeforeDays, _keep)
          ? this.joinedBeforeDays
          : joinedBeforeDays as int?,
      accountWithinDays: identical(accountWithinDays, _keep)
          ? this.accountWithinDays
          : accountWithinDays as int?,
      minMessages: identical(minMessages, _keep)
          ? this.minMessages
          : minMessages as int?,
      maxMessages: identical(maxMessages, _keep)
          ? this.maxMessages
          : maxMessages as int?,
      roleId: identical(roleId, _keep) ? this.roleId : roleId as String?,
      onlyFlagged: onlyFlagged ?? this.onlyFlagged,
      query: query ?? this.query,
    );
  }

  static const _keep = Object();

  Map<String, dynamic> toParams() => {
    'joined_within_days': joinedWithinDays,
    'joined_before_days': joinedBeforeDays,
    'account_within_days': accountWithinDays,
    'min_messages': minMessages,
    'max_messages': maxMessages,
    'filter_role_id': roleId,
    'only_flagged': onlyFlagged,
    'name_query': query.trim().isEmpty ? null : query.trim(),
  };

  @override
  bool operator ==(Object other) =>
      other is ModMemberFilter &&
      other.joinedWithinDays == joinedWithinDays &&
      other.joinedBeforeDays == joinedBeforeDays &&
      other.accountWithinDays == accountWithinDays &&
      other.minMessages == minMessages &&
      other.maxMessages == maxMessages &&
      other.roleId == roleId &&
      other.onlyFlagged == onlyFlagged &&
      other.query == query;

  @override
  int get hashCode => Object.hash(
    joinedWithinDays,
    joinedBeforeDays,
    accountWithinDays,
    minMessages,
    maxMessages,
    roleId,
    onlyFlagged,
    query,
  );
}

enum BatchAction { timeout, untimeout, kick, ban }

/// What `batch_moderate_circle_members` answered.
class BatchOutcome {
  const BatchOutcome({
    required this.requested,
    required this.done,
    required this.failures,
  });

  factory BatchOutcome.fromJson(Map<String, dynamic> json) {
    final results = [
      if (json['results'] is List)
        for (final row in json['results'] as List)
          if (row is Map) Map<String, dynamic>.from(row),
    ];
    return BatchOutcome(
      requested: results.length,
      done: (json['done'] as num?)?.toInt() ?? 0,
      failures: [
        for (final row in results)
          if (row['ok'] != true) row['user_id'] as String,
      ],
    );
  }

  final int requested;
  final int done;

  /// The ids that were refused, by rank or permission.
  final List<String> failures;

  bool get allDone => failures.isEmpty;
}

enum ModNoteKind {
  note,
  warning;

  static ModNoteKind parse(String? value) =>
      value == 'warning' ? ModNoteKind.warning : ModNoteKind.note;
}

/// A moderator's note or warning about a member.
class ModNote {
  const ModNote({
    required this.id,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.authorName,
    this.canDelete = false,
  });

  factory ModNote.fromJson(Map<String, dynamic> json) {
    return ModNote(
      id: json['id'] as String,
      kind: ModNoteKind.parse(json['kind'] as String?),
      body: json['body'] as String? ?? '',
      authorName: json['author_name'] as String?,
      createdAt: _time(json['created_at']) ?? DateTime.now(),
      canDelete: json['can_delete'] == true,
    );
  }

  final String id;
  final ModNoteKind kind;
  final String body;
  final String? authorName;
  final DateTime createdAt;
  final bool canDelete;
}

/// A banned person's appeal, as the moderators who can ban see it.
class BanAppeal {
  const BanAppeal({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.message,
    required this.createdAt,
    this.avatarUrl,
    this.banReason,
    this.bannedAt,
    this.banExpiresAt,
    this.bannedByName,
  });

  factory BanAppeal.fromJson(Map<String, dynamic> json) {
    return BanAppeal(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      message: json['message'] as String? ?? '',
      banReason: json['ban_reason'] as String?,
      bannedAt: _time(json['banned_at']),
      banExpiresAt: _time(json['ban_expires_at']),
      bannedByName: json['banned_by_name'] as String?,
      createdAt: _time(json['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String message;
  final String? banReason;
  final DateTime? bannedAt;
  final DateTime? banExpiresAt;
  final String? bannedByName;
  final DateTime createdAt;

  String get name {
    final display = displayName.trim();
    return display.isEmpty ? username : display;
  }
}

enum AppealStatus {
  none,
  pending,
  approved,
  denied,
  closed;

  static AppealStatus parse(String? value) => switch (value) {
    'pending' => AppealStatus.pending,
    'approved' => AppealStatus.approved,
    'denied' => AppealStatus.denied,
    'closed' => AppealStatus.closed,
    _ => AppealStatus.none,
  };
}

/// A circle the current user is banned from (`my_circle_bans`), with how the
/// ban ends and where their appeal stands.
class MyCircleBan {
  const MyCircleBan({
    required this.circleId,
    required this.circleName,
    required this.bannedAt,
    this.circleAvatarUrl,
    this.expiresAt,
    this.appealId,
    this.appealStatus = AppealStatus.none,
    this.appealNote,
  });

  factory MyCircleBan.fromJson(Map<String, dynamic> json) {
    return MyCircleBan(
      circleId: json['circle_id'] as String,
      circleName: json['circle_name'] as String? ?? '',
      circleAvatarUrl: json['circle_avatar_url'] as String?,
      bannedAt: _time(json['banned_at']) ?? DateTime.now(),
      expiresAt: _time(json['expires_at']),
      appealId: json['appeal_id'] as String?,
      appealStatus: AppealStatus.parse(json['appeal_status'] as String?),
      appealNote: json['appeal_note'] as String?,
    );
  }

  final String circleId;
  final String circleName;
  final String? circleAvatarUrl;
  final DateTime bannedAt;

  /// Null for a ban without an end.
  final DateTime? expiresAt;
  final String? appealId;
  final AppealStatus appealStatus;
  final String? appealNote;

  /// An appeal can be sent once per ban.
  bool get canAppeal => appealStatus == AppealStatus.none;
}

/// A lockdown that is on (`get_circle_security().lockdown`).
class RaidLockdown {
  const RaidLockdown({
    required this.until,
    required this.source,
    this.startedAt,
    this.joins,
    this.newAccounts,
    this.modeSwitched = false,
  });

  factory RaidLockdown.fromJson(Map<String, dynamic> json) {
    return RaidLockdown(
      until: _time(json['until']) ?? DateTime.now(),
      startedAt: _time(json['started_at']),
      source: json['source'] as String? ?? 'manual',
      joins: (json['joins'] as num?)?.toInt(),
      newAccounts: (json['new_accounts'] as num?)?.toInt(),
      modeSwitched: json['mode_switched'] == true,
    );
  }

  final DateTime until;
  final DateTime? startedAt;

  /// 'auto' (the circle noticed a burst) or 'manual' (a moderator).
  final String source;
  final int? joins;
  final int? newAccounts;

  /// The circle was open and now asks people to apply.
  final bool modeSwitched;

  bool get automatic => source == 'auto';
}

/// A circle's safety state: raid protection settings, a lockdown, paused
/// invites (`get_circle_security`).
class CircleSecurity {
  const CircleSecurity({
    this.raidEnabled = true,
    this.raidThreshold = 20,
    this.raidLockHours = 1,
    this.canManage = false,
    this.joinMode = 'open',
    this.invitesPausedUntil,
    this.lockdown,
    this.recentJoins = 0,
    this.recentNewAccounts = 0,
  });

  factory CircleSecurity.fromJson(Map<String, dynamic> json) {
    final lockdown = json['lockdown'];
    return CircleSecurity(
      raidEnabled: json['raid_enabled'] != false,
      raidThreshold: (json['raid_threshold'] as num?)?.toInt() ?? 20,
      raidLockHours: (json['raid_lock_hours'] as num?)?.toInt() ?? 1,
      canManage: json['can_manage'] == true,
      joinMode: json['join_mode'] as String? ?? 'open',
      invitesPausedUntil: _time(json['invites_paused_until']),
      lockdown: lockdown is Map
          ? RaidLockdown.fromJson(Map<String, dynamic>.from(lockdown))
          : null,
      recentJoins: (json['recent_joins'] as num?)?.toInt() ?? 0,
      recentNewAccounts: (json['recent_new_accounts'] as num?)?.toInt() ?? 0,
    );
  }

  final bool raidEnabled;
  final int raidThreshold;
  final int raidLockHours;
  final bool canManage;
  final String joinMode;
  final DateTime? invitesPausedUntil;
  final RaidLockdown? lockdown;
  final int recentJoins;
  final int recentNewAccounts;

  bool get lockedDown => lockdown != null;
  bool get invitesPaused => invitesPausedUntil != null;

  /// Whether anything is switched on that a moderator may want to undo.
  bool get active => lockedDown || invitesPaused;
}

/// Whether a thread is locked and what the current user may do about it
/// (`get_thread_lock_state`).
class ThreadLockState {
  const ThreadLockState({
    required this.threadId,
    required this.locked,
    required this.canLock,
    required this.canPost,
  });

  factory ThreadLockState.fromJson(Map<String, dynamic> json) {
    return ThreadLockState(
      threadId: json['thread_id'] as String? ?? '',
      locked: json['locked'] == true,
      canLock: json['can_lock'] == true,
      canPost: json['can_post'] != false,
    );
  }

  final String threadId;
  final bool locked;
  final bool canLock;
  final bool canPost;
}

/// How long a ban lasts, as offered when banning.
const banDurations = <(String, Duration?)>[
  ('Permanent', null),
  ('1 hour', Duration(hours: 1)),
  ('1 day', Duration(days: 1)),
  ('7 days', Duration(days: 7)),
  ('30 days', Duration(days: 30)),
];

/// "ends 10/21 15:30" for a ban with an end, "permanent" without.
String banEndLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) {
    return tr('Permanent');
  }
  final local = expiresAt.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return tr('Ends {time}', {
    'time': sameDay ? time : '${local.month}/${local.day} $time',
  });
}
