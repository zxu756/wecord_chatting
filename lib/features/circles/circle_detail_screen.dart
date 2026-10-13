import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_rail.dart';
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
    // Keep announcing presence for as long as the circle is open, whichever
    // layout shows it.
    ref.watch(circlePresenceProvider(circleId));
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
        return CircleMobileHome(
          key: ValueKey(detail.circle.id),
          detail: detail,
          onChanged: refresh,
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

/// Narrow circle layout: the circle rail beside the channel list. Channels
/// open full screen on top (back returns here), and so does the feed.
class CircleMobileHome extends ConsumerWidget {
  const CircleMobileHome({
    required this.detail,
    required this.onChanged,
    super.key,
  });

  final CircleDetail detail;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleId = detail.circle.id;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleRail(selectedCircleId: circleId),
            Expanded(
              child: CircleChannelSidebar(
                detail: detail,
                width: null,
                onChanged: onChanged,
                onChangeNickname: (member) => changeCircleNickname(
                  context,
                  ref,
                  circleId: circleId,
                  member: member,
                  onChanged: onChanged,
                ),
                onSelectChannel: (channel) => context.push(
                  '${ChatsScreen.path}/${channel.conversationId}',
                  extra: ChatThreadRouteExtra(
                    title: '# ${channel.name}',
                    type: ConversationType.channel,
                    circleId: circleId,
                  ),
                ),
                onSelectFeed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => _CircleFeedPage(circleId: circleId),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleFeedPage extends ConsumerWidget {
  const _CircleFeedPage({required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: ref
          .watch(circleDetailProvider(circleId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text(error.toString())),
            data: (detail) => CircleFeedView(
              circleId: circleId,
              posts: detail.posts,
              onChanged: () => ref.invalidate(circleDetailProvider(circleId)),
            ),
          ),
    );
  }
}
