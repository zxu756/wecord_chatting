import 'package:wecord/shared/l10n/l10n.dart';

/// Circle permissions. The bits mirror `circle_permission_bit()` in
/// `supabase/migrations/202610130012_circle_roles.sql`.
enum CirclePermission {
  viewChannel(
    1 << 0,
    'view_channel',
    CirclePermissionGroup.general,
    'View channels',
    'See channels and read their messages.',
  ),
  sendMessages(
    1 << 1,
    'send_messages',
    CirclePermissionGroup.text,
    'Send messages',
    'Post messages in channels and threads.',
  ),
  manageMessages(
    1 << 2,
    'manage_messages',
    CirclePermissionGroup.text,
    'Manage messages',
    "Pin messages, archive threads and delete other members' posts.",
  ),
  manageChannels(
    1 << 3,
    'manage_channels',
    CirclePermissionGroup.general,
    'Manage channels',
    "Create, sort and organize channels and categories, and manage "
        "everyone's invite links.",
  ),
  manageRoles(
    1 << 4,
    'manage_roles',
    CirclePermissionGroup.general,
    'Manage roles',
    'Create and edit roles below their highest role, and assign them.',
  ),
  kickMembers(
    1 << 5,
    'kick_members',
    CirclePermissionGroup.membership,
    'Kick members',
    'Remove members ranked below them from the circle.',
  ),
  banMembers(
    1 << 15,
    'ban_members',
    CirclePermissionGroup.membership,
    'Ban members',
    'Ban members ranked below them, keep them from rejoining and unban '
        'them.',
  ),
  moderateMembers(
    1 << 16,
    'moderate_members',
    CirclePermissionGroup.membership,
    'Time out members',
    'Stop members ranked below them from talking, reacting and joining '
        'voice for a while.',
  ),
  createInvites(
    1 << 6,
    'create_invites',
    CirclePermissionGroup.membership,
    'Create invites',
    'Invite friends and create invite links.',
  ),
  manageNicknames(
    1 << 7,
    'manage_nicknames',
    CirclePermissionGroup.membership,
    'Manage nicknames',
    'Change the nicknames of members ranked below them.',
  ),
  mentionEveryone(
    1 << 8,
    'mention_everyone',
    CirclePermissionGroup.text,
    'Mention everyone',
    'Notify every member of a channel at once.',
  ),
  manageEvents(
    1 << 9,
    'manage_events',
    CirclePermissionGroup.general,
    'Manage events',
    'Create, edit and cancel circle events.',
  ),
  manageEmojis(
    1 << 10,
    'manage_emojis',
    CirclePermissionGroup.general,
    'Manage emojis',
    'Upload, rename and delete custom emojis and stickers.',
  ),
  manageWebhooks(
    1 << 11,
    'manage_webhooks',
    CirclePermissionGroup.general,
    'Manage webhooks',
    'Create, reset and delete channel webhooks.',
  ),
  viewAuditLog(
    1 << 12,
    'view_audit_log',
    CirclePermissionGroup.general,
    'View audit log',
    'See who changed what in the circle.',
  ),
  connectVoice(
    1 << 13,
    'connect_voice',
    CirclePermissionGroup.voice,
    'Connect',
    'Join voice channels.',
  ),
  muteMembers(
    1 << 17,
    'mute_members',
    CirclePermissionGroup.voice,
    'Mute members',
    'Server mute members ranked below them in voice channels.',
  ),
  deafenMembers(
    1 << 18,
    'deafen_members',
    CirclePermissionGroup.voice,
    'Deafen members',
    'Server deafen members ranked below them in voice channels.',
  ),
  moveMembers(
    1 << 19,
    'move_members',
    CirclePermissionGroup.voice,
    'Move members',
    'Move members ranked below them between voice channels, disconnect '
        'them, and join full channels.',
  ),
  administrator(
    1 << 14,
    'administrator',
    CirclePermissionGroup.advanced,
    'Administrator',
    'Every permission. Grant with care.',
  );

  const CirclePermission(
    this.bit,
    this.key,
    this.group,
    this._label,
    this._description,
  );

  /// Every permission bit.
  static const all = (1 << 20) - 1;

  /// What `@everyone` gets in a new circle.
  static final defaultRolePermissions = maskOf(const [
    viewChannel,
    sendMessages,
    createInvites,
    connectVoice,
  ]);

  /// The permissions a channel can overwrite, mirrored by
  /// `circle_channel_overwrite_permissions()` in
  /// `supabase/migrations/202610130014_channel_permission_overwrites.sql`.
  static const channelPermissions = [
    viewChannel,
    sendMessages,
    manageMessages,
    createInvites,
    mentionEveryone,
    connectVoice,
  ];

  static final channelPermissionMask = maskOf(channelPermissions);

  final int bit;

  /// The name used by the SQL helpers.
  final String key;
  final CirclePermissionGroup group;
  final String _label;
  final String _description;

  String get label => tr(_label);

  String get description => tr(_description);

  /// Whether [permissions] grants this permission. Administrators have
  /// every permission.
  bool isGrantedBy(int permissions) {
    return permissions & bit != 0 || permissions & administrator.bit != 0;
  }

  static int maskOf(Iterable<CirclePermission> permissions) {
    var mask = 0;
    for (final permission in permissions) {
      mask |= permission.bit;
    }
    return mask;
  }
}

enum CirclePermissionGroup {
  general('General'),
  membership('Membership'),
  text('Text'),
  voice('Voice'),
  advanced('Advanced');

  const CirclePermissionGroup(this._label);

  final String _label;

  String get label => tr(_label);
}

class CircleRole {
  const CircleRole({
    required this.id,
    required this.name,
    required this.position,
    required this.permissions,
    this.color,
    this.hoist = false,
    this.isDefault = false,
    this.memberCount = 0,
  });

  factory CircleRole.fromJson(Map<String, dynamic> json) {
    return CircleRole(
      id: json['id'] as String,
      name: json['name'] as String,
      color: (json['color'] as num?)?.toInt(),
      position: (json['position'] as num?)?.toInt() ?? 0,
      permissions: (json['permissions'] as num?)?.toInt() ?? 0,
      hoist: json['hoist'] == true,
      isDefault: json['is_default'] == true,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;

  /// 0xRRGGBB, or null for no colour.
  final int? color;

  /// Higher ranks higher; `@everyone` is 0.
  final int position;
  final int permissions;

  /// Members are listed under this role in the member list.
  final bool hoist;

  /// `@everyone`, held by every member.
  final bool isDefault;
  final int memberCount;

  bool grants(CirclePermission permission) {
    return permission.isGrantedBy(permissions);
  }
}

/// Role colours offered by the role editor, as 0xRRGGBB.
const circleRoleColors = <int>[
  0x1ABC9C,
  0x2ECC71,
  0x3498DB,
  0x9B59B6,
  0xE91E63,
  0xF1C40F,
  0xE67E22,
  0xE74C3C,
  0x95A5A6,
  0x607D8B,
  0x11806A,
  0x1F8B4C,
  0x206694,
  0x71368A,
  0xAD1457,
  0xC27C0E,
  0xA84300,
  0x992D22,
];
