import 'package:wecord/shared/models/circle_role.dart';

/// A channel's permission overwrite for one role or one member: [allow]
/// and [deny] are [CirclePermission] bits (never both for the same bit).
class CircleChannelOverwrite {
  const CircleChannelOverwrite({
    required this.id,
    required this.channelId,
    this.roleId,
    this.userId,
    this.allow = 0,
    this.deny = 0,
  });

  factory CircleChannelOverwrite.fromJson(Map<String, dynamic> json) {
    return CircleChannelOverwrite(
      id: json['id'] as String,
      channelId: json['channel_id'] as String,
      roleId: json['role_id'] as String?,
      userId: json['user_id'] as String?,
      allow: (json['allow'] as num?)?.toInt() ?? 0,
      deny: (json['deny'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String channelId;

  /// Set for a role's overwrite (including `@everyone`).
  final String? roleId;

  /// Set for a member's overwrite.
  final String? userId;
  final int allow;
  final int deny;

  OverwriteState stateOf(CirclePermission permission) {
    return OverwriteState.of(permission, allow: allow, deny: deny);
  }
}

/// What an overwrite does with one permission.
enum OverwriteState {
  deny,

  /// Neither allowed nor denied: the permission comes from the roles.
  inherit,
  allow;

  static OverwriteState of(
    CirclePermission permission, {
    required int allow,
    required int deny,
  }) {
    if (allow & permission.bit != 0) {
      return OverwriteState.allow;
    }
    if (deny & permission.bit != 0) {
      return OverwriteState.deny;
    }
    return OverwriteState.inherit;
  }
}
