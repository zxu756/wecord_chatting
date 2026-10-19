import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

import 'join_requests_fakes.dart' show JoinRpc;

export 'join_requests_fakes.dart' show JoinRpc;

/// A row of `list_circle_members_for_moderation`.
Map<String, dynamic> modMemberJson({
  String id = 'u1',
  String username = 'nia',
  String name = 'Nia Novak',
  String joinedAt = '2026-10-22T09:00:00Z',
  String accountCreatedAt = '2026-01-10T09:00:00Z',
  int messages = 3,
  int warnings = 0,
  bool flagged = false,
  String? timedOutUntil,
  bool canTimeout = true,
  bool canKick = true,
  bool canBan = true,
  int total = 1,
}) => {
  'user_id': id,
  'username': username,
  'display_name': name,
  'nickname': null,
  'avatar_url': null,
  'member_role': 'member',
  'joined_at': joinedAt,
  'account_created_at': accountCreatedAt,
  'message_count': messages,
  'warning_count': warnings,
  'flagged': flagged,
  'timed_out_until': timedOutUntil,
  'role_ids': const <String>[],
  'can_timeout': canTimeout,
  'can_kick': canKick,
  'can_ban': canBan,
  'total_count': total,
};

Map<String, dynamic> modNoteJson({
  String id = 'n1',
  String kind = 'note',
  String body = 'Asked to stop posting links',
  String author = 'Mia',
  bool canDelete = true,
}) => {
  'id': id,
  'kind': kind,
  'body': body,
  'author_id': 'mia',
  'author_name': author,
  'created_at': '2026-10-25T08:00:00Z',
  'can_delete': canDelete,
};

Map<String, dynamic> banAppealJson({
  String id = 'a1',
  String name = 'Eve Adler',
  String username = 'eve',
  String message = 'I am sorry, it will not happen again.',
  String? reason = 'rude',
}) => {
  'id': id,
  'user_id': 'user-$id',
  'username': username,
  'display_name': name,
  'avatar_url': null,
  'message': message,
  'ban_reason': reason,
  'banned_at': '2026-10-24T08:00:00Z',
  'ban_expires_at': null,
  'banned_by_name': 'Sam',
  'created_at': '2026-10-25T08:30:00Z',
};

Map<String, dynamic> myBanJson({
  String circleId = 'circle-1',
  String name = 'Pixel Club',
  String? expiresAt,
  String? appealStatus,
  String? appealNote,
}) => {
  'circle_id': circleId,
  'circle_name': name,
  'circle_avatar_url': null,
  'banned_at': '2026-10-24T08:00:00Z',
  'expires_at': expiresAt,
  'appeal_id': appealStatus == null ? null : 'ap1',
  'appeal_status': appealStatus,
  'appeal_note': appealNote,
  'appeal_decided_at': null,
};

/// A get_circle_security result.
Map<String, dynamic> securityJson({
  bool enabled = true,
  int threshold = 20,
  int hours = 1,
  bool canManage = true,
  String joinMode = 'open',
  String? invitesPausedUntil,
  Map<String, dynamic>? lockdown,
  int recentJoins = 0,
  int recentNew = 0,
}) => {
  'raid_enabled': enabled,
  'raid_threshold': threshold,
  'raid_lock_hours': hours,
  'can_manage': canManage,
  'join_mode': joinMode,
  'invites_paused_until': invitesPausedUntil,
  'lockdown': lockdown,
  'recent_joins': recentJoins,
  'recent_new_accounts': recentNew,
};

Map<String, dynamic> lockdownJson({
  String source = 'auto',
  int joins = 24,
  int newAccounts = 9,
  bool modeSwitched = true,
}) => {
  'until': '2099-01-01T10:00:00Z',
  'started_at': '2099-01-01T09:00:00Z',
  'source': source,
  'joins': joins,
  'new_accounts': newAccounts,
  'mode_switched': modeSwitched,
};

/// A circle detail the moderator tools read permissions and roles from.
CircleDetail modDetail({
  int permissions = 1 | 2 | 32 | 4 | 32768 | 65536 | 1048576,
  String id = 'circle-1',
}) {
  return CircleDetail(
    circle: CircleSummary(
      id: id,
      name: 'Pixel Club',
      memberCount: 40,
      channelCount: 2,
      currentUserRole: 'member',
      currentUserPermissions: permissions,
    ),
    members: const [],
    channels: const [],
    posts: const [],
    roles: const [
      CircleRole(id: 'role-mod', name: 'Mod', position: 2, permissions: 98340),
      CircleRole(
        id: 'role-everyone',
        name: '@everyone',
        position: 0,
        permissions: 3,
        isDefault: true,
      ),
    ],
  );
}

List<Override> modToolsOverrides(JoinRpc rpc, {CircleDetail? detail}) => [
  circleRpcProvider.overrideWithValue(rpc.call),
  circleDetailProvider(
    'circle-1',
  ).overrideWith((ref) async => detail ?? modDetail()),
];
