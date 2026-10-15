import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_membership_actions.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/home/phone_home.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';

final circleDetailProvider = FutureProvider.autoDispose
    .family<CircleDetail, String>((ref, circleId) {
      final repository = ref.watch(circlesRepositoryProvider);
      final subscription = repository.circleChanges(circleId).listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      return repository.getCircleDetail(circleId).then((detail) {
        // The server lifts a timeout by the clock alone, so reload then to
        // get the permissions back.
        final until = detail.currentUserTimedOutUntil;
        if (until != null) {
          final timer = Timer(
            until.difference(DateTime.now()) + const Duration(seconds: 1),
            ref.invalidateSelf,
          );
          ref.onDispose(timer.cancel);
        }
        return detail;
      });
    });

class CircleDetailScreen extends ConsumerWidget {
  const CircleDetailScreen({
    required this.circleId,
    this.initialConversationId,
    this.channelViewBuilder,
    this.threadViewBuilder,
    super.key,
  });

  final String circleId;

  /// A channel (or channel thread) conversation to open in the wide
  /// workspace instead of the first channel.
  final String? initialConversationId;
  final CircleChannelViewBuilder? channelViewBuilder;
  final CircleThreadViewBuilder? threadViewBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    void refresh() => ref.invalidate(circleDetailProvider(circleId));

    return detail.when(
      loading: () => Scaffold(
        appBar: _CircleAppBar(title: tr('Circle')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => error is CircleMembershipLostException
          ? CircleMembershipLostView(circleId: circleId)
          : Scaffold(
              appBar: _CircleAppBar(title: tr('Circle')),
              body: Center(child: Text(error.toString())),
            ),
      data: (detail) => CircleOnboardingGate(
        key: ValueKey('onboarding-${detail.circle.id}'),
        circleId: detail.circle.id,
        circleName: detail.circle.name,
        child: isWideLayout(MediaQuery.sizeOf(context).width)
            ? CircleWorkspace(
                key: ValueKey(detail.circle.id),
                detail: detail,
                initialConversationId: initialConversationId,
                onChanged: refresh,
                channelViewBuilder: channelViewBuilder,
                threadViewBuilder: threadViewBuilder,
              )
            : CircleMobileHome(
                key: ValueKey(detail.circle.id),
                detail: detail,
                onChanged: refresh,
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

/// Narrow circle layout: the phone home frame (rail, rounded panel and the
/// floating user panel) with the channel list in the panel. Channels open
/// full screen on top (back returns here), and so does the feed.
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
      body: PhoneHomeFrame(
        selectedCircleId: circleId,
        panelBuilder: (context, bottomInset) => CircleChannelSidebar(
          detail: detail,
          width: null,
          color: PhoneHomeColors.panel(Theme.of(context).colorScheme),
          listBottomPadding: bottomInset,
          onChanged: onChanged,
          onChangeNickname: (member) => changeCircleNickname(
            context,
            ref,
            circleId: circleId,
            member: member,
            onChanged: onChanged,
          ),
          onSelectChannel: (channel) {
            context.push(
              CircleChannelThreadScreen.pathFor(
                circleId,
                channel.conversationId,
              ),
              extra: ChatThreadRouteExtra(
                title: channel.isVoice ? channel.name : '# ${channel.name}',
                type: ConversationType.channel,
                circleId: circleId,
              ),
            );
            // Voice channels open their call view and join.
            if (channel.isVoice &&
                detail.canInChannel(channel, CirclePermission.connectVoice) &&
                ref.read(voiceSessionProvider)?.channelId != channel.id) {
              joinVoiceChannel(
                context,
                ref,
                circleId: circleId,
                channelId: channel.id,
                conversationId: channel.conversationId,
                channelName: channel.name,
              );
            }
          },
          onOpenVoice: (session) => context.push(voiceSessionPath(session)),
          onSelectThread: (thread) => context.push(
            CircleChannelThreadScreen.pathFor(circleId, thread.id),
            extra: ChatThreadRouteExtra(
              title: thread.title ?? tr('Thread'),
              type: ConversationType.thread,
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
    );
  }
}

class _CircleFeedPage extends ConsumerWidget {
  const _CircleFeedPage({required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Feed'))),
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
