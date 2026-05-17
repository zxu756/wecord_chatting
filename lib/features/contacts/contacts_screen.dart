import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/friend_request.dart';
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
    FutureProvider.autoDispose<List<FriendRequest>>((ref) {
      return ref.watch(contactsRepositoryProvider).listIncomingRequests();
    });

final friendsProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(contactsRepositoryProvider).listFriends();
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
                          trailing: FilledButton(
                            onPressed: () async {
                              await ref
                                  .read(contactsRepositoryProvider)
                                  .sendFriendRequest(profile.id);
                            },
                            child: const Text('Add'),
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
              for (final request in requests)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(request.requesterId),
                  subtitle: const Text('Pending friend request'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () async {
                          await ref
                              .read(contactsRepositoryProvider)
                              .acceptFriendRequest(request.id);
                          ref.invalidate(incomingFriendRequestsProvider);
                          ref.invalidate(friendsProvider);
                        },
                        child: const Text('Accept'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          await ref
                              .read(contactsRepositoryProvider)
                              .rejectFriendRequest(request.id);
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

    return _Section(
      title: 'Friends',
      child: friends.when(
        loading: () => const _LoadingRow(label: 'Loading friends'),
        error: (error, stackTrace) => _ErrorText(error),
        data: (friends) {
          if (friends.isEmpty) {
            return const Text('No friends yet.');
          }
          return Column(
            children: [
              for (final friend in friends) _ProfileTile(profile: friend),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
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
      title: Text(profile.displayName),
      subtitle: Text('@${profile.username}'),
      trailing: trailing,
    );
  }
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
