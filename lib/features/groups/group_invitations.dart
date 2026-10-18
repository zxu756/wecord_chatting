import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "{inviter} invited you to join {group}": an invitation to a group from a
/// friend, held back because the person asked to approve being added
/// (Settings → Privacy & Safety → Group invitations). It lasts 7 days.
class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.conversationId,
    required this.groupTitle,
    required this.inviterId,
    required this.inviterName,
    required this.inviterUsername,
    required this.createdAt,
    required this.expiresAt,
    this.inviterAvatarUrl,
  });

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    return GroupInvitation(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      groupTitle: json['group_title'] as String? ?? '',
      inviterId: json['inviter_id'] as String,
      inviterName: json['inviter_name'] as String? ?? '',
      inviterUsername: json['inviter_username'] as String? ?? '',
      inviterAvatarUrl: json['inviter_avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    );
  }

  final String id;
  final String conversationId;
  final String groupTitle;
  final String inviterId;
  final String inviterName;
  final String inviterUsername;
  final String? inviterAvatarUrl;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// The group's name, or a plain word when it has none.
  String get groupLabel => groupTitle.isEmpty ? tr('a group') : groupTitle;
}

abstract interface class GroupInvitationsRepository {
  /// The caller's open invitations, newest first.
  Future<List<GroupInvitation>> list();

  /// Accepts or declines; accepting returns the group's id.
  Future<String?> respond(String invitationId, {required bool accept});
}

class SupabaseGroupInvitationsRepository implements GroupInvitationsRepository {
  const SupabaseGroupInvitationsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<GroupInvitation>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_my_group_invitations');
    return [
      for (final row in rows)
        GroupInvitation.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<String?> respond(String invitationId, {required bool accept}) async {
    final conversationId = await _client.rpc<dynamic>(
      'respond_group_invitation',
      params: {'invitation_id': invitationId, 'accept': accept},
    );
    return conversationId as String?;
  }
}

class _UninitializedGroupInvitationsRepository
    implements GroupInvitationsRepository {
  const _UninitializedGroupInvitationsRepository();

  @override
  Future<List<GroupInvitation>> list() async => const [];

  @override
  Future<String?> respond(String invitationId, {required bool accept}) async =>
      null;
}

final groupInvitationsRepositoryProvider = Provider<GroupInvitationsRepository>(
  (ref) {
    try {
      return SupabaseGroupInvitationsRepository(
        ref.watch(supabaseClientProvider),
      );
    } on ProviderException {
      return const _UninitializedGroupInvitationsRepository();
    }
  },
);

final groupInvitationsProvider =
    FutureProvider.autoDispose<List<GroupInvitation>>((ref) {
      return ref.watch(groupInvitationsRepositoryProvider).list();
    });

/// "Expires in 6 days", "Expires in 1 day" or "Expires today".
String invitationExpiryLabel(DateTime expiresAt, {DateTime? now}) {
  final left = expiresAt.difference(now ?? DateTime.now().toUtc());
  final days = (left.inHours / 24).ceil();
  if (left.inHours < 24) {
    return tr('Expires today');
  }
  return days == 1
      ? tr('Expires in 1 day')
      : tr('Expires in {count} days', {'count': days});
}

/// [template] with each `{name}` placeholder replaced by its span, so a
/// translated sentence keeps its word order.
List<InlineSpan> spansFromTemplate(
  String template,
  Map<String, InlineSpan> replacements,
) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\{(\w+)\}');
  var position = 0;
  for (final match in pattern.allMatches(template)) {
    if (match.start > position) {
      spans.add(TextSpan(text: template.substring(position, match.start)));
    }
    final replacement = replacements[match.group(1)];
    spans.add(replacement ?? TextSpan(text: match.group(0)));
    position = match.end;
  }
  if (position < template.length) {
    spans.add(TextSpan(text: template.substring(position)));
  }
  return spans;
}

/// An invitation in Notifications → Friends, with Accept and Decline.
class GroupInvitationCard extends ConsumerStatefulWidget {
  const GroupInvitationCard({required this.invitation, super.key});

  final GroupInvitation invitation;

  @override
  ConsumerState<GroupInvitationCard> createState() =>
      _GroupInvitationCardState();
}

class _GroupInvitationCardState extends ConsumerState<GroupInvitationCard> {
  var _busy = false;

  Future<void> _answer({required bool accept}) async {
    final invitation = widget.invitation;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final joined = await ref
          .read(groupInvitationsRepositoryProvider)
          .respond(invitation.id, accept: accept);
      if (accept) {
        ref.invalidate(conversationsProvider);
        // Open the group before the card goes away with the answer.
        if (joined != null && mounted) {
          openPage(
            context,
            '${ChatsScreen.path}/$joined',
            extra: ChatThreadRouteExtra(
              title: invitation.groupTitle,
              type: ConversationType.group,
            ),
          );
        }
      }
      ref.invalidate(groupInvitationsProvider);
    } catch (_) {
      ref.invalidate(groupInvitationsProvider);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'This invitation is no longer available. Ask to be invited again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final invitation = widget.invitation;
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    return Semantics(
      container: true,
      label: tr('{name} invited you to join {group}', {
        'name': invitation.inviterName,
        'group': invitation.groupLabel,
      }),
      child: InboxCardShell(
        key: ValueKey('inbox-group-invitation-${invitation.id}'),
        highlighted: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(
              name: invitation.inviterName,
              avatarUrl: invitation.inviterAvatarUrl,
              badge: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.panel, width: 2.5),
                ),
                child: const Icon(
                  Icons.group_add_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text.rich(
                    TextSpan(
                      children: spansFromTemplate(
                        tr('{name} invited you to join {group}'),
                        {
                          'name': TextSpan(
                            text: invitation.inviterName,
                            style: bold,
                          ),
                          'group': TextSpan(
                            text: invitation.groupLabel,
                            style: bold,
                          ),
                        },
                      ),
                    ),
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      spokenAge(invitation.createdAt),
                      invitationExpiryLabel(invitation.expiresAt),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      // Wide windows keep the two pills at phone size.
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Row(
                        children: [
                          Expanded(
                            child: WeCordButton(
                              key: const ValueKey('group-invitation-accept'),
                              label: tr('Accept'),
                              size: WeCordButtonSize.small,
                              expand: true,
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_answer(accept: true)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: WeCordButton(
                              key: const ValueKey('group-invitation-decline'),
                              label: tr('Decline'),
                              size: WeCordButtonSize.small,
                              variant: WeCordButtonVariant.secondary,
                              expand: true,
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_answer(accept: false)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// After people were picked for a group, how many of them still have to
/// accept an invitation (they are not in the group yet). [picked] are the
/// ids chosen, [memberIds] the group's members afterwards.
int pendingInviteCount(Iterable<String> picked, Iterable<String> memberIds) {
  final members = memberIds.toSet();
  return picked.where((id) => !members.contains(id)).length;
}

/// "Invitations sent to {count} people. They join when they accept."
String invitationsSentNotice(int count) {
  return count == 1
      ? tr('Invitation sent to 1 person. They join when they accept.')
      : tr('Invitations sent to {count} people. They join when they accept.', {
          'count': count,
        });
}

/// Once [picked] were added to the group [conversationId], tells the person
/// how many of them were sent an invitation instead (they asked to approve
/// being added). Says nothing when everyone joined, or when the group
/// cannot be read.
Future<void> noticePendingInvitations(
  WidgetRef ref,
  ScaffoldMessengerState? messenger,
  String conversationId,
  Iterable<String> picked,
) async {
  try {
    ref.invalidate(groupDetailProvider(conversationId));
    final detail = await ref.read(groupDetailProvider(conversationId).future);
    final count = pendingInviteCount(picked, [
      for (final member in detail.members) member.profile.id,
    ]);
    if (count > 0) {
      messenger?.showSnackBar(
        SnackBar(content: Text(invitationsSentNotice(count))),
      );
    }
  } catch (_) {
    // The notice is a courtesy.
  }
}
