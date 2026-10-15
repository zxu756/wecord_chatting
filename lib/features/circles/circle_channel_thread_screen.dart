import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/announcement_widgets.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_forum_view.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/shared/l10n/l10n.dart';
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
    return '${CircleRoutes.path}/$circleId/channels/$conversationId';
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
      title = channel.isVoice ? channel.name : '# ${channel.name}';
    }
    final announcementChannel = channel != null && channel.isAnnouncement
        ? channel
        : null;
    final actions = [
      if (announcementChannel != null)
        ChatThreadAction(
          tooltip: tr('Follow'),
          icon: Icons.campaign_outlined,
          onPressed: () =>
              showFollowChannelSheet(context, channel: announcementChannel),
        ),
      ChatThreadAction(
        tooltip: tr('Show member list'),
        icon: Icons.people_outline,
        onPressed: detail == null
            ? null
            : () => _scaffoldKey.currentState?.openEndDrawer(),
      ),
      if (detail != null && channel != null && detail.canOpenChannelSettings)
        ChatThreadAction(
          tooltip: tr('Channel settings'),
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
        appBar: AppBar(title: Text(title ?? tr('Channel'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('This channel was deleted or is no longer available.'),
                  key: const ValueKey('circle-channel-unavailable'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('${CircleRoutes.path}/$circleId'),
                  child: Text(tr('Back to channels')),
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
          (detail != null && channel != null && channel.isVoice
              ? VoiceChannelView(
                  key: ValueKey('voice-${channel.id}'),
                  circleId: circleId,
                  channelId: channel.id,
                  conversationId: channel.conversationId,
                  channelName: channel.name,
                  canConnect: detail.canInChannel(
                    channel,
                    CirclePermission.connectVoice,
                  ),
                  actions: actions,
                  moderation: VoiceModeration.forCircle(detail),
                  chatBuilder: (context) => voiceChannelChat(detail, channel!),
                  isStage: channel.isStage,
                  stageModerator: detail.canModerateStage(channel),
                  canManageSounds: detail.canManageEmojis,
                )
              : null) ??
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
                  timedOutUntil: detail.currentUserTimedOutUntil,
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
            timedOutUntil: detail?.currentUserTimedOutUntil,
            slowmodeSeconds: detail != null && channel != null
                ? detail.slowmodeFor(channel)
                : null,
            topic: channel?.topic,
            isAnnouncementChannel: channel?.isAnnouncement ?? false,
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
