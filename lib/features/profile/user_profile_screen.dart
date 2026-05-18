import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/report_user_sheet.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/profile_relationship.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({required this.userId, super.key});

  static const path = '/profile';

  final String userId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  late Future<ProfileSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _reload();
    }
  }

  void _reload() {
    _summaryFuture = ref
        .read(profileRepositoryProvider)
        .getProfileSummary(widget.userId);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        setState(_reload);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update profile action. Try again.'),
        ),
      );
    }
  }

  Future<void> _openConversation(Profile profile) async {
    try {
      final conversationId = await ref
          .read(chatsRepositoryProvider)
          .getOrCreateDirectConversation(profile.id);
      if (!mounted) {
        return;
      }
      context.go(
        '${ChatsScreen.path}/$conversationId',
        extra: ChatThreadRouteExtra(
          title: profile.displayLabel,
          type: ConversationType.direct,
          avatarUrl: profile.avatarUrl,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start chat. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<ProfileSummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: FilledButton(
                onPressed: () => setState(_reload),
                child: const Text('Try again'),
              ),
            );
          }

          final summary = snapshot.data!;
          final profile = summary.profile;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              CircleAvatar(
                radius: 40,
                child: Text(_initials(profile.displayLabel)),
              ),
              const SizedBox(height: 16),
              Text(
                profile.displayLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('@${profile.username}', textAlign: TextAlign.center),
              if (profile.bio.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(profile.bio, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              _ProfileActions(
                summary: summary,
                onMessage: () => _openConversation(profile),
                onAddFriend: () => _run(
                  () => ref
                      .read(contactsRepositoryProvider)
                      .sendFriendRequest(profile.id),
                ),
                onAcceptRequest: () => _run(
                  () => ref
                      .read(contactsRepositoryProvider)
                      .acceptFriendRequest(summary.incomingRequestId!),
                ),
                onBlock: () => _run(
                  () =>
                      ref.read(profileRepositoryProvider).blockUser(profile.id),
                ),
                onUnblock: () => _run(
                  () => ref
                      .read(profileRepositoryProvider)
                      .unblockUser(profile.id),
                ),
                onReport: () => showReportUserSheet(context, profile),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.summary,
    required this.onMessage,
    required this.onAddFriend,
    required this.onAcceptRequest,
    required this.onBlock,
    required this.onUnblock,
    required this.onReport,
  });

  final ProfileSummary summary;
  final VoidCallback onMessage;
  final VoidCallback onAddFriend;
  final VoidCallback onAcceptRequest;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final isSelf = summary.relationshipStatus == ProfileRelationshipStatus.self;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.canStartChat)
          FilledButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Message'),
          ),
        if (summary.canSendFriendRequest)
          FilledButton.icon(
            onPressed: onAddFriend,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add Friend'),
          ),
        if (summary.canAcceptRequest)
          FilledButton.icon(
            onPressed: onAcceptRequest,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Accept Request'),
          ),
        if (summary.relationshipStatus == ProfileRelationshipStatus.blocked)
          OutlinedButton.icon(
            onPressed: onUnblock,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Unblock'),
          )
        else if (!isSelf)
          OutlinedButton.icon(
            onPressed: onBlock,
            icon: const Icon(Icons.block_outlined),
            label: const Text('Block'),
          ),
        if (!isSelf)
          TextButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Report'),
          ),
      ],
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
