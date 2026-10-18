import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/friend_tags/friend_tags_screen.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/notifications/important_contact_row.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Switches [friend]'s star, saving it and refreshing the lists. Shows a
/// message when it could not be saved.
Future<void> toggleFriendStar(
  BuildContext context,
  WidgetRef ref,
  Profile friend, {
  required bool starred,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(friendTagsRepositoryProvider)
        .setStarred(friend.id, starred: starred);
    ref.invalidate(friendTagsProvider);
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not update the star. Try again.'))),
    );
  }
}

/// What only the person sees about a friend, on the friend's profile: the
/// star, their tags and a way into their Moments.
class FriendProfileExtras extends ConsumerWidget {
  const FriendProfileExtras({required this.friend, super.key});

  final Profile friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(friendTagsProvider).value ?? const FriendTagsData();
    final tags = data.tagsOf(friend.id);
    final starred = data.isStarred(friend.id);
    return SettingsGroup(
      key: const ValueKey('profile-friend-extras'),
      color: context.tokens.colors.well,
      separatorIndent: 58,
      children: [
        SettingsRow.toggle(
          key: const ValueKey('profile-star'),
          icon: starred ? Icons.star_rounded : Icons.star_border_rounded,
          tone: starred ? SettingsTone.warning : SettingsTone.neutral,
          title: tr('Star'),
          subtitle: tr('Starred friends are listed first.'),
          value: starred,
          onChanged: (value) =>
              unawaited(toggleFriendStar(context, ref, friend, starred: value)),
        ),
        ImportantContactRow(friend: friend),
        SettingsRow(
          key: const ValueKey('profile-tags'),
          icon: Icons.sell_outlined,
          title: tr('Tags'),
          subtitle: tags.isEmpty
              ? tr('Only you can see tags.')
              : tags.map((tag) => tag.name).join(', '),
          onTap: () => unawaited(showFriendTagsPicker(context, friend: friend)),
        ),
        SettingsRow(
          key: const ValueKey('profile-moments'),
          icon: Icons.auto_awesome_motion_outlined,
          title: tr('Moments'),
          onTap: () =>
              openPage(context, '${MomentsScreen.path}/of/${friend.id}'),
        ),
      ],
    );
  }
}
