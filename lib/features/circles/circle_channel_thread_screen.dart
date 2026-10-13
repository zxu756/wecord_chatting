import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_forum_view.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';

typedef CircleChannelThreadBuilder =
    Widget Function(BuildContext context, List<Widget> actions);

/// Full-screen circle channel, pushed from the narrow circle home. The app
/// bar's members button opens the circle's member list as an end drawer.
class CircleChannelThreadScreen extends ConsumerStatefulWidget {
  const CircleChannelThreadScreen({
    required this.circleId,
    required this.conversationId,
    this.title,
    this.conversationType = ConversationType.channel,
    this.threadBuilder,
    super.key,
  });

  /// Where a circle channel opens full screen, under its circle.
  static String pathFor(String circleId, String conversationId) {
    return '${CirclesScreen.path}/$circleId/channels/$conversationId';
  }

  final String circleId;
  final String conversationId;
  final String? title;

  /// [ConversationType.channel], or [ConversationType.thread] for a thread
  /// of one of the circle's channels.
  final ConversationType conversationType;

  /// Replaces the chat thread, for tests.
  final CircleChannelThreadBuilder? threadBuilder;

  @override
  ConsumerState<CircleChannelThreadScreen> createState() =>
      _CircleChannelThreadScreenState();
}

class _CircleChannelThreadScreenState
    extends ConsumerState<CircleChannelThreadScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final circleId = widget.circleId;
    final detail = ref.watch(circleDetailProvider(circleId)).valueOrNull;
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).valueOrNull ?? const <String>{};
    CircleChannel? channel;
    if (widget.conversationType == ConversationType.channel) {
      for (final candidate in detail?.channels ?? const <CircleChannel>[]) {
        if (candidate.conversationId == widget.conversationId) {
          channel = candidate;
          break;
        }
      }
    }
    // A thread of a forum is one of its posts.
    CircleChannel? forum;
    if (widget.conversationType == ConversationType.thread && detail != null) {
      final parentId = ref
          .watch(chatConversationSummaryProvider(widget.conversationId))
          .valueOrNull
          ?.parentConversationId;
      for (final candidate in detail.channels) {
        if (candidate.isForum && candidate.conversationId == parentId) {
          forum = candidate;
        }
      }
    }
    // Deep links carry no title; name the channel from the circle.
    var title = widget.title;
    if (title == null && channel != null) {
      title = '# ${channel.name}';
    }
    final actions = [
      ChatThreadAction(
        tooltip: 'Show member list',
        icon: Icons.people_outline,
        onPressed: detail == null
            ? null
            : () => _scaffoldKey.currentState?.openEndDrawer(),
      ),
      if (detail != null && channel != null && detail.canOpenChannelSettings)
        ChatThreadAction(
          tooltip: 'Channel settings',
          icon: Icons.settings_outlined,
          onPressed: () => openCircleChannelSettings(
            context,
            circleId: circleId,
            channelId: channel!.id,
          ),
        ),
    ];

    // The channel was deleted, or the user can no longer see it.
    if (detail != null &&
        channel == null &&
        widget.conversationType == ConversationType.channel) {
      return Scaffold(
        appBar: AppBar(title: Text(title ?? 'Channel')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This channel was deleted or is no longer available.',
                  key: ValueKey('circle-channel-unavailable'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('${CirclesScreen.path}/$circleId'),
                  child: const Text('Back to channels'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: detail == null
          ? null
          : Drawer(
              child: SafeArea(
                child: CircleMemberList(
                  detail: detail,
                  width: null,
                  onlineUserIds: onlineUserIds,
                  onChangeNickname: (member) => changeCircleNickname(
                    context,
                    ref,
                    circleId: circleId,
                    member: member,
                    onChanged: () =>
                        ref.invalidate(circleDetailProvider(circleId)),
                  ),
                ),
              ),
            ),
      body:
          widget.threadBuilder?.call(context, [
            for (final action in actions) action.toIconButton(),
          ]) ??
          (detail != null && channel != null && channel.isForum
              ? CircleForumView(
                  key: ValueKey('forum-${channel.id}'),
                  detail: detail,
                  channel: channel,
                  actions: actions,
                  onOpenPost: (post) => context.push(
                    CircleChannelThreadScreen.pathFor(
                      circleId,
                      post.conversationId,
                    ),
                    extra: ChatThreadRouteExtra(
                      title: post.title,
                      type: ConversationType.thread,
                      circleId: circleId,
                    ),
                  ),
                )
              : null) ??
          (detail != null && forum != null
              ? ChatThreadScreen(
                  conversationId: widget.conversationId,
                  title: title,
                  conversationType: ConversationType.thread,
                  forumPost: true,
                  onBack: () => Navigator.of(context).maybePop(),
                  extraActions: actions,
                  canSendMessages: detail.canInChannel(
                    forum,
                    CirclePermission.sendMessages,
                  ),
                  slowmodeSeconds: 0,
                )
              : null) ??
          ChatThreadScreen(
            conversationId: widget.conversationId,
            title: title,
            conversationType: widget.conversationType,
            extraActions: actions,
            // Threads fall back to the conversation list's answer.
            canSendMessages: detail != null && channel != null
                ? detail.canInChannel(channel, CirclePermission.sendMessages)
                : null,
            slowmodeSeconds: detail != null && channel != null
                ? detail.slowmodeFor(channel)
                : null,
            topic: channel?.topic,
            onOpenThread: (thread) => context.push(
              CircleChannelThreadScreen.pathFor(
                circleId,
                thread.conversationId,
              ),
              extra: ChatThreadRouteExtra(
                title: thread.title,
                type: ConversationType.thread,
                circleId: circleId,
              ),
            ),
          ),
    );
  }
}
