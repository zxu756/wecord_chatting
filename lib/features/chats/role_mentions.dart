import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// A circle role the current user may mention somewhere.
class MentionRole {
  const MentionRole({
    required this.id,
    required this.name,
    this.color,
    this.mentionable = false,
  });

  factory MentionRole.fromJson(Map<String, dynamic> json) {
    return MentionRole(
      id: json['id'] as String,
      name: json['name'] as String,
      color: (json['color'] as num?)?.toInt(),
      mentionable: json['mentionable'] == true,
    );
  }

  final String id;
  final String name;

  /// 0xRRGGBB, or null for no colour.
  final int? color;
  final bool mentionable;
}

/// What the current user may mention in a conversation besides members:
/// `@here` (with mention_everyone, or anywhere outside circles) and roles.
class MentionTargets {
  const MentionTargets({
    this.canMentionEveryone = false,
    this.roles = const [],
  });

  factory MentionTargets.fromJson(Object? json) {
    if (json is! Map) {
      return const MentionTargets();
    }
    return MentionTargets(
      canMentionEveryone: json['can_mention_everyone'] == true,
      roles: [
        for (final role in json['roles'] as List<dynamic>? ?? const [])
          MentionRole.fromJson(Map<String, dynamic>.from(role as Map)),
      ],
    );
  }

  final bool canMentionEveryone;
  final List<MentionRole> roles;
}

abstract interface class RoleMentionsRepository {
  Future<MentionTargets> mentionTargets(String conversationId);

  /// Ids of the circle's roles anyone may mention.
  Future<Set<String>> mentionableRoleIds(String circleId);

  Future<void> setRoleMentionable({
    required String roleId,
    required bool mentionable,
  });
}

class SupabaseRoleMentionsRepository implements RoleMentionsRepository {
  const SupabaseRoleMentionsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MentionTargets> mentionTargets(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'list_conversation_mention_roles',
      params: {'target_conversation_id': conversationId},
    );
    return MentionTargets.fromJson(data);
  }

  @override
  Future<Set<String>> mentionableRoleIds(String circleId) async {
    final rows = await _client
        .from('circle_roles')
        .select('id')
        .eq('circle_id', circleId)
        .eq('mentionable', true);
    return {for (final row in rows) row['id'] as String};
  }

  @override
  Future<void> setRoleMentionable({
    required String roleId,
    required bool mentionable,
  }) async {
    await _client.rpc<void>(
      'set_circle_role_mentionable',
      params: {'target_role_id': roleId, 'is_mentionable': mentionable},
    );
  }
}

/// Without Supabase (tests), nothing beyond members can be mentioned.
class NoRoleMentionsRepository implements RoleMentionsRepository {
  const NoRoleMentionsRepository();

  @override
  Future<MentionTargets> mentionTargets(String conversationId) async =>
      const MentionTargets();

  @override
  Future<Set<String>> mentionableRoleIds(String circleId) async => const {};

  @override
  Future<void> setRoleMentionable({
    required String roleId,
    required bool mentionable,
  }) {
    throw StateError('Supabase must be initialized before editing roles.');
  }
}

final roleMentionsRepositoryProvider = Provider<RoleMentionsRepository>((ref) {
  try {
    return SupabaseRoleMentionsRepository(ref.watch(supabaseClientProvider));
  } on AssertionError {
    return const NoRoleMentionsRepository();
  }
});

/// `@here` and the roles the current user may mention in a conversation;
/// nothing when that cannot be loaded.
final conversationMentionTargetsProvider = FutureProvider.autoDispose
    .family<MentionTargets, String>((ref, conversationId) async {
      try {
        return await ref
            .watch(roleMentionsRepositoryProvider)
            .mentionTargets(conversationId);
      } catch (_) {
        return const MentionTargets();
      }
    });

/// Ids of a circle's roles anyone may mention.
final circleMentionableRoleIdsProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, circleId) {
      return ref
          .watch(roleMentionsRepositoryProvider)
          .mentionableRoleIds(circleId);
    });

/// `@here` or a role, offered above the members while a mention is typed.
class SpecialMention {
  const SpecialMention.here() : roleId = null, name = 'here', color = null;

  const SpecialMention.role({
    required String this.roleId,
    required this.name,
    this.color,
  });

  /// Null for `@here`.
  final String? roleId;
  final String name;

  /// The role's colour as 0xRRGGBB.
  final int? color;

  bool get isHere => roleId == null;

  String get token => '@$name';
}

/// `@here` (when [allowHere]) and the roles of [targets] whose name
/// contains [query] (lowercase), up to [limit].
List<SpecialMention> specialMentionCandidates(
  MentionTargets targets,
  String query, {
  required bool allowHere,
  int limit = 5,
}) {
  return [
    if (allowHere && targets.canMentionEveryone && 'here'.startsWith(query))
      const SpecialMention.here(),
    for (final role in targets.roles)
      if (role.name.toLowerCase().contains(query))
        SpecialMention.role(
          roleId: role.id,
          name: role.name,
          color: role.color,
        ),
  ].take(limit).toList(growable: false);
}

/// 0xRRGGBB as an opaque colour.
Color mentionRoleColor(int rgb) => Color(0xFF000000 | rgb);

/// The `@here` and role suggestions shown above a message field.
class SpecialMentionCandidateList extends StatelessWidget {
  const SpecialMentionCandidateList({
    required this.candidates,
    required this.onSelect,
    required this.maxHeight,
    super.key,
  });

  final List<SpecialMention> candidates;
  final ValueChanged<SpecialMention> onSelect;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final candidate in candidates)
              ListTile(
                key: ValueKey(
                  candidate.isHere
                      ? 'mention-candidate-here'
                      : 'mention-candidate-role-${candidate.roleId}',
                ),
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: colorScheme.surfaceContainerLow,
                  child: Icon(
                    candidate.isHere
                        ? Icons.campaign_outlined
                        : Icons.alternate_email,
                    color: candidate.color == null
                        ? colorScheme.onSurfaceVariant
                        : mentionRoleColor(candidate.color!),
                  ),
                ),
                title: Text(
                  candidate.token,
                  style: TextStyle(
                    color: candidate.color == null
                        ? null
                        : mentionRoleColor(candidate.color!),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  candidate.isHere
                      ? tr('Notify everyone online here')
                      : tr('Notify everyone with this role'),
                ),
                onTap: () => onSelect(candidate),
              ),
          ],
        ),
      ),
    );
  }
}
