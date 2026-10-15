import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/profile/custom_status_label.dart';
import 'package:wecord/features/profile/profile_banner.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/report_user_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
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
        SnackBar(
          content: Text(tr('Could not update profile action. Try again.')),
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
      openPage(
        context,
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
        SnackBar(content: Text(tr('Could not start chat. Try again.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Profile'))),
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
                child: Text(tr('Try again')),
              ),
            );
          }

          final summary = snapshot.data!;
          final profile = summary.profile;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ProfileBannerHeader(
                bannerUrl: profile.bannerUrl,
                avatarRadius: 40,
                avatar: FallbackAvatar(
                  title: profile.displayLabel,
                  avatarUrl: profile.avatarUrl,
                  radius: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                profile.displayLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Center(
                child: ProfileNameBadges(userId: profile.id, leadingGap: 0),
              ),
              Text(
                ['@${profile.username}', ?profile.pronouns].join(' · '),
                key: const ValueKey('profile-username-line'),
                textAlign: TextAlign.center,
              ),
              if (activeCustomStatus(profile.customStatus) != null) ...[
                const SizedBox(height: 8),
                CustomStatusLabel(
                  status: profile.customStatus,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
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
              if (summary.mutualCircles.isNotEmpty)
                _MutualSection(
                  key: const ValueKey('mutual-circles'),
                  title: summary.mutualCircles.length == 1
                      ? tr('1 mutual circle')
                      : tr('{count} mutual circles', {
                          'count': summary.mutualCircles.length,
                        }),
                  children: [
                    for (final circle in summary.mutualCircles)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: FallbackAvatar(
                          title: circle.name,
                          avatarUrl: circle.avatarUrl,
                          radius: 18,
                        ),
                        title: Text(circle.name),
                        onTap: () =>
                            openPage(context, circleLocation(circle.id)),
                      ),
                  ],
                ),
              if (summary.mutualFriends.isNotEmpty)
                _MutualSection(
                  key: const ValueKey('mutual-friends'),
                  title: summary.mutualFriends.length == 1
                      ? tr('1 mutual friend')
                      : tr('{count} mutual friends', {
                          'count': summary.mutualFriends.length,
                        }),
                  children: [
                    for (final friend in summary.mutualFriends)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: FallbackAvatar(
                          title: friend.label,
                          avatarUrl: friend.avatarUrl,
                          radius: 18,
                        ),
                        title: Text(friend.label),
                        subtitle: Text('@${friend.username}'),
                        onTap: () => context.push(
                          '${UserProfileScreen.path}/${friend.id}',
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The friends or circles a profile shares with the viewer.
class _MutualSection extends StatelessWidget {
  const _MutualSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
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
            label: Text(tr('Message')),
          ),
        if (summary.canSendFriendRequest)
          FilledButton.icon(
            onPressed: onAddFriend,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(tr('Add Friend')),
          ),
        if (summary.canAcceptRequest)
          FilledButton.icon(
            onPressed: onAcceptRequest,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(tr('Accept Request')),
          ),
        if (summary.relationshipStatus == ProfileRelationshipStatus.blocked)
          OutlinedButton.icon(
            onPressed: onUnblock,
            icon: const Icon(Icons.lock_open_outlined),
            label: Text(tr('Unblock')),
          )
        else if (!isSelf)
          OutlinedButton.icon(
            onPressed: onBlock,
            icon: const Icon(Icons.block_outlined),
            label: Text(tr('Block')),
          ),
        if (!isSelf)
          TextButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.flag_outlined),
            label: Text(tr('Report')),
          ),
      ],
    );
  }
}
