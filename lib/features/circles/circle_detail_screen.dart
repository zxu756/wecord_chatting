import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
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
  const CircleDetailScreen({
    required this.circleId,
    this.channelViewBuilder,
    super.key,
  });

  /// From this width the circle opens as a multi-column workspace.
  static const workspaceBreakpoint = 1000.0;

  final String circleId;
  final CircleChannelViewBuilder? channelViewBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    void refresh() => ref.invalidate(circleDetailProvider(circleId));

    return detail.when(
      loading: () => const Scaffold(
        appBar: _CircleAppBar(title: 'Circle'),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: const _CircleAppBar(title: 'Circle'),
        body: Center(child: Text(error.toString())),
      ),
      data: (detail) {
        if (MediaQuery.sizeOf(context).width >= workspaceBreakpoint) {
          return CircleWorkspace(
            key: ValueKey(detail.circle.id),
            detail: detail,
            onChanged: refresh,
            channelViewBuilder: channelViewBuilder,
          );
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(detail.circle.name),
              actions: [
                if (detail.canManageCircle) ...[
                  IconButton(
                    tooltip: 'Invite friends',
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    onPressed: () => showCircleInviteSheet(context, detail),
                  ),
                  IconButton(
                    tooltip: 'Create channel',
                    icon: const Icon(Icons.add_comment_outlined),
                    onPressed: () =>
                        showCircleChannelCreationSheet(context, circleId),
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
                CircleFeedView(
                  circleId: circleId,
                  posts: detail.posts,
                  onChanged: refresh,
                ),
              ],
            ),
          ),
        );
      },
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
