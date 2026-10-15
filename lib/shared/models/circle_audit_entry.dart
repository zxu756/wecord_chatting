import 'package:wecord/shared/l10n/l10n.dart';

/// One entry of a circle's audit log, as `list_circle_audit_log` returns
/// it.
class CircleAuditEntry {
  const CircleAuditEntry({
    required this.id,
    required this.circleId,
    required this.action,
    required this.targetType,
    required this.createdAt,
    this.targetId,
    this.targetLabel,
    this.changes = const {},
    this.actor,
  });

  factory CircleAuditEntry.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    final changes = json['changes'];
    return CircleAuditEntry(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      action: json['action'] as String,
      targetType: json['target_type'] as String,
      targetId: json['target_id'] as String?,
      targetLabel: json['target_label'] as String?,
      changes: changes is Map<String, dynamic> ? changes : const {},
      createdAt: DateTime.parse(json['created_at'] as String),
      actor: actor is Map<String, dynamic>
          ? CircleAuditActor.fromJson(actor)
          : null,
    );
  }

  final String id;
  final String circleId;

  /// For example `channel_create` or `member_kick`; see
  /// [CircleAuditActionGroup] for the groups.
  final String action;

  /// `channel`, `category`, `role`, `member`, `invite`, `message`,
  /// `thread`, `post`, `tag`, `event`, `webhook`, `emoji`, `sticker`,
  /// `rule` (AutoMod) or `circle`.
  final String targetType;
  final String? targetId;

  /// The target's name when the entry was written.
  final String? targetLabel;

  /// What changed: fields as `{old, new}`, or details of the target.
  final Map<String, dynamic> changes;
  final DateTime createdAt;

  /// Null when the actor's account is gone.
  final CircleAuditActor? actor;

  CircleAuditActionGroup get group => CircleAuditActionGroup.of(action);
}

class CircleAuditActor {
  const CircleAuditActor({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.nickname,
  });

  factory CircleAuditActor.fromJson(Map<String, dynamic> json) {
    return CircleAuditActor(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      nickname: json['nickname'] as String?,
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  /// Their nickname in the circle, if they still have one there.
  final String? nickname;

  /// Nickname, then display name, then username.
  String get name {
    final nickname = this.nickname?.trim();
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    return displayName.trim().isEmpty ? username : displayName;
  }
}

/// Audit actions grouped by the prefix before their first underscore, which
/// `list_circle_audit_log` filters on.
enum CircleAuditActionGroup {
  channel('channel', 'Channels'),
  category('category', 'Categories'),
  role('role', 'Roles'),
  member('member', 'Members'),
  circle('circle', 'Ownership'),
  invite('invite', 'Invites'),
  message('message', 'Messages'),
  thread('thread', 'Threads'),
  post('post', 'Posts'),
  forum('forum', 'Forums'),
  event('event', 'Events'),
  webhook('webhook', 'Webhooks'),
  emoji('emoji', 'Emoji'),
  sticker('sticker', 'Stickers'),
  automod('automod', 'AutoMod'),
  onboarding('onboarding', 'Onboarding'),
  other('', 'Other');

  const CircleAuditActionGroup(this.filter, this._label);

  /// The value passed as `action_filter`.
  final String filter;
  final String _label;

  String get label => trIn('audit', _label);

  static CircleAuditActionGroup of(String action) {
    final prefix = action.split('_').first;
    for (final group in values) {
      if (group != other && group.filter == prefix) {
        return group;
      }
    }
    return other;
  }

  /// The groups offered as filters.
  static const filters = [
    channel,
    category,
    role,
    member,
    circle,
    invite,
    message,
    thread,
    post,
    forum,
    event,
    webhook,
    emoji,
    sticker,
    automod,
    onboarding,
  ];
}
