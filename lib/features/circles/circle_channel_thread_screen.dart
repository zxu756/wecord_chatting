import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/presence/presence_repository.dart';
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
    // Deep links carry no title; name the channel from the circle.
    var title = widget.title;
    if (title == null && detail != null) {
      for (final channel in detail.channels) {
        if (channel.conversationId == widget.conversationId) {
          title = '# ${channel.name}';
          break;
        }
      }
    }
    final actions = [
      IconButton(
        tooltip: 'Show member list',
        icon: const Icon(Icons.people_outline),
        onPressed: detail == null
            ? null
            : () => _scaffoldKey.currentState?.openEndDrawer(),
      ),
    ];

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
          widget.threadBuilder?.call(context, actions) ??
          ChatThreadScreen(
            conversationId: widget.conversationId,
            title: title,
            conversationType: widget.conversationType,
            extraActions: actions,
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
