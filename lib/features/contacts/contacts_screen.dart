import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/contacts/contact_alias_sheet.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/developer/bot_directory.dart';
import 'package:wecord/features/friend_tags/friend_profile_extras.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/friend_tags/friend_tags_screen.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/profile_insights_blocks.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/groups/group_creation_sheet.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/qr/qr_entries.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

final contactsSearchQueryProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final contactsSearchResultsProvider = FutureProvider.autoDispose<List<Profile>>(
  (ref) {
    final query = ref.watch(contactsSearchQueryProvider);
    return ref.watch(contactsRepositoryProvider).searchProfiles(query);
  },
);

final incomingFriendRequestsProvider =
    FutureProvider.autoDispose<List<IncomingFriendRequest>>((ref) {
      return ref.watch(contactsRepositoryProvider).listIncomingRequests();
    });

final friendsProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(contactsRepositoryProvider).listFriends();
});

final friendsSearchQueryProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final sentFriendRequestIdsProvider = StateProvider.autoDispose<Set<String>>((
  ref,
) {
  return const {};
});

/// Whether the friends list shows everyone or only who is online.
final _onlineOnlyProvider = StateProvider.autoDispose<bool>((ref) => false);

/// The tag the friends list is narrowed to; null for no tag.
final _tagFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

/// Friends: find people to add, answer requests, and the friends list.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  static const path = '/contacts';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                PaperPageHeader(title: tr('Friends')),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SearchSection(),
                      _IncomingRequestsSection(),
                      FindBotEntry(),
                      _FriendsSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchSection extends ConsumerWidget {
  const _SearchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final query = ref.watch(contactsSearchQueryProvider).trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('Add friend')),
        const AddFriendQrActions(),
        WeCordTextField(
          hint: tr('Search profiles'),
          prefixIcon: Icons.person_search_outlined,
          onPaper: true,
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            ref.read(contactsSearchQueryProvider.notifier).state = value;
          },
        ),
        const SizedBox(height: 10),
        if (query.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              tr('Search by username.'),
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          )
        else
          ref
              .watch(contactsSearchResultsProvider)
              .when(
                loading: () => _LoadingRow(label: tr('Searching')),
                error: (error, stackTrace) => _ErrorText(error),
                data: (profiles) {
                  if (profiles.isEmpty) {
                    return _Note(tr('No matching profiles.'));
                  }
                  return SettingsGroup(
                    separatorIndent: 72,
                    children: [
                      for (final profile in profiles)
                        _PersonRow(
                          profile: profile,
                          onTap: () => context.push(
                            userProfileLocation(
                              profile.id,
                              source: FriendSource.search,
                            ),
                          ),
                          trailing: _AddFriendButton(profile: profile),
                        ),
                    ],
                  );
                },
              ),
      ],
    );
  }
}

class _AddFriendButton extends ConsumerWidget {
  const _AddFriendButton({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requested = ref
        .watch(sentFriendRequestIdsProvider)
        .contains(profile.id);

    return WeCordButton(
      key: ValueKey('add-friend-${profile.id}'),
      label: requested ? tr('Requested') : tr('Add'),
      icon: requested ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
      size: WeCordButtonSize.small,
      variant: requested
          ? WeCordButtonVariant.secondary
          : WeCordButtonVariant.accent,
      onPressed: requested
          ? null
          : () async {
              try {
                await ref
                    .read(contactsRepositoryProvider)
                    .sendFriendRequest(profile.id);
              } on FriendRequestRefused catch (refused) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(refused.refusal.text)));
                }
                return;
              }
              await recordFriendRequestSource(
                ref,
                profile.id,
                FriendSource.search,
              );
              ref.read(sentFriendRequestIdsProvider.notifier).update((ids) {
                return {...ids, profile.id};
              });
              ref.invalidate(contactsSearchResultsProvider);
            },
    );
  }
}

class _IncomingRequestsSection extends ConsumerWidget {
  const _IncomingRequestsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(incomingFriendRequestsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('Incoming requests')),
        requests.when(
          loading: () => _LoadingRow(label: tr('Loading requests')),
          error: (error, stackTrace) => _ErrorText(error),
          data: (requests) {
            if (requests.isEmpty) {
              return _Note(tr('No incoming requests.'));
            }
            return SettingsGroup(
              separatorIndent: 72,
              children: [
                for (final incomingRequest in requests)
                  _PersonRow(
                    key: ValueKey(
                      'friend-request-${incomingRequest.request.id}',
                    ),
                    profile: incomingRequest.requester,
                    showAlias: false,
                    onTap: () {
                      context.push('/profile/${incomingRequest.requester.id}');
                    },
                    below: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MutualCountLine(
                          userId: incomingRequest.requester.id,
                          padding: const EdgeInsets.only(bottom: 8),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: WeCordButton(
                                label: tr('Accept'),
                                size: WeCordButtonSize.small,
                                expand: true,
                                onPressed: () async {
                                  await ref
                                      .read(contactsRepositoryProvider)
                                      .acceptFriendRequest(
                                        incomingRequest.request.id,
                                      );
                                  ref.invalidate(
                                    incomingFriendRequestsProvider,
                                  );
                                  ref.invalidate(friendsProvider);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: WeCordButton(
                                label: tr('Reject'),
                                size: WeCordButtonSize.small,
                                variant: WeCordButtonVariant.secondary,
                                expand: true,
                                onPressed: () async {
                                  await ref
                                      .read(contactsRepositoryProvider)
                                      .rejectFriendRequest(
                                        incomingRequest.request.id,
                                      );
                                  ref.invalidate(
                                    incomingFriendRequestsProvider,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FriendsSection extends ConsumerWidget {
  const _FriendsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    final query = ref.watch(friendsSearchQueryProvider).trim().toLowerCase();
    final onlineOnly = ref.watch(_onlineOnlyProvider);
    final onlineIds =
        ref.watch(onlineUserIdsProvider).value ?? const <String>{};
    final statuses = ref.watch(presenceStatusesProvider).value;
    PresenceStatus? presence(String id) =>
        presenceOf(id, onlineUserIds: onlineIds, statuses: statuses);
    final tagData =
        ref.watch(friendTagsProvider).value ?? const FriendTagsData();
    final tagId = ref.watch(_tagFilterProvider);
    // A tag that was deleted no longer narrows the list.
    final activeTag = tagId == null ? null : tagData.tagById(tagId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(
          tr('Friends'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WeCordButton(
                key: const ValueKey('contacts-tags'),
                label: tr('Tags'),
                icon: Icons.sell_outlined,
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.onPaper,
                onPressed: () => context.push(FriendTagsScreen.path),
              ),
              const SizedBox(width: 6),
              friends.maybeWhen(
                data: (friends) => _NewGroupButton(friends: friends),
                orElse: () => const _NewGroupButton(friends: []),
              ),
            ],
          ),
        ),
        friends.when(
          loading: () => _LoadingRow(label: tr('Loading friends')),
          error: (error, stackTrace) => _ErrorText(error),
          data: (friends) {
            if (friends.isEmpty) {
              return _Note(tr('No friends yet.'));
            }

            final online = [
              for (final friend in friends)
                if (presence(friend.id) != null) friend,
            ];
            // Online first, then everyone else.
            final ordered = [
              ...online,
              for (final friend in friends)
                if (presence(friend.id) == null) friend,
            ];
            final matching = query.isEmpty
                ? ordered
                : ordered
                      .where((friend) {
                        return friend.displayName.toLowerCase().contains(
                              query,
                            ) ||
                            friend.displayLabel.toLowerCase().contains(query) ||
                            friend.username.toLowerCase().contains(query);
                      })
                      .toList(growable: false);
            final shown = onlineOnly
                ? matching
                      .where((friend) => presence(friend.id) != null)
                      .toList(growable: false)
                : matching;
            final visibleFriends = activeTag == null
                ? shown
                : tagData.inTag(shown, activeTag.id);
            final starredFriends = [
              for (final friend in visibleFriends)
                if (tagData.isStarred(friend.id)) friend,
            ];
            final otherFriends = [
              for (final friend in visibleFriends)
                if (!tagData.isStarred(friend.id)) friend,
            ];

            Widget group(List<Profile> people) => SettingsGroup(
              separatorIndent: 72,
              children: [
                for (final friend in people)
                  _PersonRow(
                    key: ValueKey('friend-${friend.id}'),
                    profile: friend,
                    presence: presence(friend.id),
                    onTap: () => context.push('/profile/${friend.id}'),
                    trailing: _FriendActions(
                      profile: friend,
                      starred: tagData.isStarred(friend.id),
                    ),
                  ),
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      WeCordChip(
                        key: const ValueKey('friends-filter-all'),
                        label: tr('All'),
                        count: friends.length,
                        onPaper: true,
                        selected: !onlineOnly && activeTag == null,
                        onPressed: () {
                          ref.read(_onlineOnlyProvider.notifier).state = false;
                          ref.read(_tagFilterProvider.notifier).state = null;
                        },
                      ),
                      const SizedBox(width: 6),
                      WeCordChip(
                        key: const ValueKey('friends-filter-online'),
                        label: tr('Online'),
                        count: online.length,
                        onPaper: true,
                        selected: onlineOnly,
                        onPressed: () =>
                            ref.read(_onlineOnlyProvider.notifier).state = true,
                      ),
                      for (final tag in tagData.tags) ...[
                        const SizedBox(width: 6),
                        WeCordChip(
                          key: ValueKey('friends-filter-tag-${tag.id}'),
                          label: tag.name,
                          icon: Icons.sell_outlined,
                          count: tagData.membersOf(tag.id).length,
                          onPaper: true,
                          selected: activeTag?.id == tag.id,
                          onPressed: () =>
                              ref.read(_tagFilterProvider.notifier).state =
                                  activeTag?.id == tag.id ? null : tag.id,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                WeCordTextField(
                  hint: tr('Search friends'),
                  prefixIcon: Icons.search_rounded,
                  onPaper: true,
                  onChanged: (value) {
                    ref.read(friendsSearchQueryProvider.notifier).state = value;
                  },
                ),
                const SizedBox(height: 10),
                if (visibleFriends.isEmpty)
                  _Note(
                    activeTag != null && shown.isNotEmpty
                        ? tr('No friends in this tag.')
                        : tr('No matching friends.'),
                  )
                else ...[
                  if (starredFriends.isNotEmpty) ...[
                    SettingsSectionHeader(tr('Starred')),
                    group(starredFriends),
                  ],
                  if (starredFriends.isNotEmpty && otherFriends.isNotEmpty)
                    SettingsSectionHeader(tr('Other friends')),
                  if (otherFriends.isNotEmpty) group(otherFriends),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _NewGroupButton extends ConsumerStatefulWidget {
  const _NewGroupButton({required this.friends});

  final List<Profile> friends;

  @override
  ConsumerState<_NewGroupButton> createState() => _NewGroupButtonState();
}

class _NewGroupButtonState extends ConsumerState<_NewGroupButton> {
  @override
  Widget build(BuildContext context) {
    return WeCordButton(
      key: const ValueKey('contacts-new-group'),
      label: tr('New Group'),
      icon: Icons.group_add_outlined,
      size: WeCordButtonSize.small,
      variant: WeCordButtonVariant.onPaper,
      onPressed: widget.friends.length < 2 ? null : _openGroupCreation,
    );
  }

  Future<void> _openGroupCreation() async {
    final result = await showWeCordSheet<GroupCreationResult>(
      context,
      builder: (context, scrollController) {
        return GroupCreationSheet(friends: widget.friends);
      },
    );
    if (result == null || !mounted) {
      return;
    }
    ref.invalidate(conversationsProvider);
    openPage(
      context,
      '${ChatsScreen.path}/${result.conversationId}',
      extra: ChatThreadRouteExtra(
        title: result.title,
        type: ConversationType.group,
      ),
    );
  }
}

class _MessageFriendButton extends ConsumerStatefulWidget {
  const _MessageFriendButton({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_MessageFriendButton> createState() =>
      _MessageFriendButtonState();
}

class _MessageFriendButtonState extends ConsumerState<_MessageFriendButton> {
  var _opening = false;

  @override
  Widget build(BuildContext context) {
    // Phones keep the friend's name readable with an icon-only button.
    if (isCompactWidth(MediaQuery.sizeOf(context).width)) {
      return WeCordIconButton(
        icon: Icons.chat_bubble_outline_rounded,
        tooltip: tr('Message'),
        size: 38,
        onPressed: _opening ? null : _openConversation,
      );
    }
    return WeCordButton(
      label: tr('Message'),
      icon: Icons.chat_bubble_outline_rounded,
      size: WeCordButtonSize.small,
      variant: WeCordButtonVariant.secondary,
      loading: _opening,
      onPressed: _openConversation,
    );
  }

  Future<void> _openConversation() async {
    setState(() {
      _opening = true;
    });

    try {
      final conversationId = await ref
          .read(chatsRepositoryProvider)
          .getOrCreateDirectConversation(widget.profile.id);
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      openPage(
        context,
        '${ChatsScreen.path}/$conversationId',
        extra: ChatThreadRouteExtra(
          title: widget.profile.displayLabel,
          type: ConversationType.direct,
          avatarUrl: widget.profile.avatarUrl,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Unable to start chat: {error}', {'error': error})),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }
}

class _FriendActions extends ConsumerWidget {
  const _FriendActions({required this.profile, this.starred = false});

  final Profile profile;
  final bool starred;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WeCordIconButton(
          key: ValueKey('friend-star-${profile.id}'),
          icon: starred ? Icons.star_rounded : Icons.star_border_rounded,
          tooltip: starred ? tr('Remove star') : tr('Star'),
          size: 38,
          variant: WeCordButtonVariant.ghost,
          selected: starred,
          onPressed: () =>
              toggleFriendStar(context, ref, profile, starred: !starred),
        ),
        const SizedBox(width: 2),
        WeCordIconButton(
          icon: Icons.edit_outlined,
          tooltip: tr('Edit alias'),
          size: 38,
          variant: WeCordButtonVariant.ghost,
          onPressed: () async {
            final saved = await showWeCordSheet<bool>(
              context,
              builder: (context, scrollController) =>
                  ContactAliasSheet(profile: profile),
            );
            if (saved == true) {
              ref.invalidate(friendsProvider);
            }
          },
        ),
        const SizedBox(width: 2),
        _MessageFriendButton(profile: profile),
      ],
    );
  }
}

/// A person in a friends list group: avatar, name and @username, with
/// actions at the end or [below] the name.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.profile,
    this.trailing,
    this.below,
    this.onTap,
    this.presence,
    this.showAlias = true,
    super.key,
  });

  final Profile profile;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  /// Null while offline.
  final PresenceStatus? presence;

  /// Requests show the name people chose, not the alias.
  final bool showAlias;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final name = showAlias ? profile.displayLabel : profile.displayName;
    return WeCordPressable(
      onPressed: onTap,
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final highlighted =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          color: c.ink.withValues(alpha: highlighted ? 0.04 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: below == null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                name: name,
                avatarUrl: profile.avatarUrl,
                presence: presenceColor(context, presence),
                presenceShape: presenceShapeOf(presence),
                presenceLabel: presenceLabelOf(presence),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '@${profile.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                    if (below != null) ...[const SizedBox(height: 10), below!],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        );
      },
    );
  }
}

/// A quiet line of text in place of an empty list.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Text(text, style: TextStyle(fontSize: 14, color: c.muted)),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, color: c.muted)),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        errorText(error),
        style: TextStyle(color: context.tokens.colors.dangerText),
      ),
    );
  }
}
