import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_creation_sheet.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circle_feed_composer.dart';
import 'package:wecord/features/circles/circle_post_tile.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

final circleDetailProvider = FutureProvider.autoDispose
    .family<CircleDetail, String>((ref, circleId) {
      final repository = ref.watch(circlesRepositoryProvider);
      final subscription = repository.circleChanges(circleId).listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      return repository.getCircleDetail(circleId);
    });

class CircleDetailScreen extends ConsumerWidget {
  const CircleDetailScreen({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    return detail.when(
      loading: () => const Scaffold(
        appBar: _CircleAppBar(title: 'Circle'),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: const _CircleAppBar(title: 'Circle'),
        body: Center(child: Text(error.toString())),
      ),
      data: (detail) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(detail.circle.name),
            actions: [
              if (detail.canManageCircle) ...[
                IconButton(
                  tooltip: 'Invite friends',
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => CircleInviteSheet(detail: detail),
                  ),
                ),
                IconButton(
                  tooltip: 'Create channel',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) =>
                        CircleChannelCreationSheet(circleId: circleId),
                  ),
                ),
              ],
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Channels'),
                Tab(text: 'Feed'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _ChannelsTab(channels: detail.channels),
              _FeedTab(circleId: circleId, posts: detail.posts),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CircleAppBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AppBar(title: Text(title));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ChannelsTab extends StatelessWidget {
  const _ChannelsTab({required this.channels});

  final List<CircleChannel> channels;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(child: Text('No channels yet'));
    }
    return ListView.separated(
      itemCount: channels.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ListTile(
          leading: const Icon(Icons.tag),
          title: Text(channel.name),
          onTap: () {
            context.go(
              '${ChatsScreen.path}/${channel.conversationId}',
              extra: ChatThreadRouteExtra(
                title: '# ${channel.name}',
                type: ConversationType.channel,
              ),
            );
          },
        );
      },
    );
  }
}

class _FeedTab extends ConsumerWidget {
  const _FeedTab({required this.circleId, required this.posts});

  final String circleId;
  final List<CirclePost> posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void refresh() => ref.invalidate(circleDetailProvider(circleId));

    return ListView.separated(
      itemCount: posts.length + 1,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleFeedComposer(circleId: circleId, onPosted: refresh),
              if (posts.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 28, 16, 40),
                  child: Center(child: Text('No posts yet')),
                ),
            ],
          );
        }
        return CirclePostTile(post: posts[index - 1], onChanged: refresh);
      },
    );
  }
}
