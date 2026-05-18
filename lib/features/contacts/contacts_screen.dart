import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/groups/group_creation_sheet.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/profile.dart';

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

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  static const path = '/contacts';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _SearchSection(),
          SizedBox(height: 24),
          _IncomingRequestsSection(),
          SizedBox(height: 24),
          _FriendsSection(),
        ],
      ),
    );
  }
}

class _SearchSection extends ConsumerWidget {
  const _SearchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(contactsSearchQueryProvider).trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Search profiles',
          ),
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            ref.read(contactsSearchQueryProvider.notifier).state = value;
          },
        ),
        const SizedBox(height: 12),
        if (query.isEmpty)
          const Text('Search by username.')
        else
          ref
              .watch(contactsSearchResultsProvider)
              .when(
                loading: () => const _LoadingRow(label: 'Searching'),
                error: (error, stackTrace) => _ErrorText(error),
                data: (profiles) {
                  if (profiles.isEmpty) {
                    return const Text('No matching profiles.');
                  }
                  return Column(
                    children: [
                      for (final profile in profiles)
                        _ProfileTile(
                          profile: profile,
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

    return FilledButton(
      onPressed: requested
          ? null
          : () async {
              await ref
                  .read(contactsRepositoryProvider)
                  .sendFriendRequest(profile.id);
              ref.read(sentFriendRequestIdsProvider.notifier).update((ids) {
                return {...ids, profile.id};
              });
              ref.invalidate(contactsSearchResultsProvider);
            },
      child: Text(requested ? 'Requested' : 'Add'),
    );
  }
}

class _IncomingRequestsSection extends ConsumerWidget {
  const _IncomingRequestsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(incomingFriendRequestsProvider);

    return _Section(
      title: 'Incoming requests',
      child: requests.when(
        loading: () => const _LoadingRow(label: 'Loading requests'),
        error: (error, stackTrace) => _ErrorText(error),
        data: (requests) {
          if (requests.isEmpty) {
            return const Text('No incoming requests.');
          }
          return Column(
            children: [
              for (final incomingRequest in requests)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _ProfileAvatar(profile: incomingRequest.requester),
                  title: Text(incomingRequest.requester.displayName),
                  subtitle: Text('@${incomingRequest.requester.username}'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () async {
                          await ref
                              .read(contactsRepositoryProvider)
                              .acceptFriendRequest(incomingRequest.request.id);
                          ref.invalidate(incomingFriendRequestsProvider);
                          ref.invalidate(friendsProvider);
                        },
                        child: const Text('Accept'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          await ref
                              .read(contactsRepositoryProvider)
                              .rejectFriendRequest(incomingRequest.request.id);
                          ref.invalidate(incomingFriendRequestsProvider);
                        },
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FriendsSection extends ConsumerWidget {
  const _FriendsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    final query = ref.watch(friendsSearchQueryProvider).trim().toLowerCase();

    return _Section(
      title: 'Friends',
      trailing: friends.maybeWhen(
        data: (friends) => _NewGroupButton(friends: friends),
        orElse: () => const _NewGroupButton(friends: []),
      ),
      child: friends.when(
        loading: () => const _LoadingRow(label: 'Loading friends'),
        error: (error, stackTrace) => _ErrorText(error),
        data: (friends) {
          if (friends.isEmpty) {
            return const Text('No friends yet.');
          }

          final visibleFriends = query.isEmpty
              ? friends
              : friends
                    .where((friend) {
                      return friend.displayName.toLowerCase().contains(query) ||
                          friend.username.toLowerCase().contains(query);
                    })
                    .toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Search friends',
                ),
                onChanged: (value) {
                  ref.read(friendsSearchQueryProvider.notifier).state = value;
                },
              ),
              const SizedBox(height: 12),
              if (visibleFriends.isEmpty)
                const Text('No matching friends.')
              else
                for (final friend in visibleFriends)
                  _ProfileTile(
                    profile: friend,
                    trailing: _MessageFriendButton(profile: friend),
                  ),
            ],
          );
        },
      ),
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
    return FilledButton.icon(
      onPressed: widget.friends.length < 2 ? null : _openGroupCreation,
      icon: const Icon(Icons.group_add_outlined),
      label: const Text('New Group'),
    );
  }

  Future<void> _openGroupCreation() async {
    final result = await showModalBottomSheet<GroupCreationResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return GroupCreationSheet(friends: widget.friends);
      },
    );
    if (result == null || !mounted) {
      return;
    }
    ref.invalidate(conversationsProvider);
    context.go(
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
    return FilledButton.icon(
      onPressed: _opening ? null : _openConversation,
      icon: _opening
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chat_bubble_outline),
      label: const Text('Message'),
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
      context.go(
        '${ChatsScreen.path}/$conversationId',
        extra: ChatThreadRouteExtra(
          title: widget.profile.displayName,
          type: ConversationType.direct,
          avatarUrl: widget.profile.avatarUrl,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to start chat: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, this.trailing});

  final Profile profile;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _ProfileAvatar(profile: profile),
      title: Text(profile.displayName),
      subtitle: Text('@${profile.username}'),
      trailing: trailing,
    );
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUrl = ref.watch(avatarDisplayUrlProvider(profile.avatarUrl));
    final image = displayUrl.valueOrNull == null
        ? null
        : NetworkImage(displayUrl.valueOrNull!);
    return CircleAvatar(
      backgroundImage: image,
      onBackgroundImageError: image == null ? null : (_, _) {},
      child: image == null ? Text(_initials(profile.displayName)) : null,
    );
  }
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Text(
      error.toString(),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}
