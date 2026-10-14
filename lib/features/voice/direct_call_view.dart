import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';

/// The call in a direct or group chat, above its messages: everyone in it
/// and the call controls while the current user is in it, otherwise who is
/// in it and a way to join. Nothing when no call is going on.
class DirectCallBar extends ConsumerWidget {
  const DirectCallBar({
    required this.conversationId,
    required this.title,
    super.key,
  });

  final String conversationId;

  /// The chat's title, which names the call elsewhere (the voice panel).
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final call = ref.watch(directCallInProvider(conversationId));
    final here =
        session != null &&
        session.isDirectCall &&
        session.conversationId == conversationId;
    final colorScheme = Theme.of(context).colorScheme;

    if (here) {
      final people = <String, VoiceCallPerson>{
        for (final participant
            in call?.participants ?? const <DirectCallParticipant>[])
          participant.userId: (
            name: participant.name,
            avatarUrl: participant.avatarUrl,
            selfDeaf: participant.selfDeaf,
          ),
      };
      final alone = session.isConnected && session.participants.length < 2;
      return Material(
        key: const ValueKey('direct-call-bar-connected'),
        color: colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!session.isConnected)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(tr('Connecting…')),
                  ],
                ),
              )
            else ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: VoiceCallGrid(session: session, people: people),
              ),
              if (alone)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    tr('Calling…'),
                    key: const ValueKey('direct-call-waiting'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: VoiceCallControls(session: session),
              ),
            ],
            const Divider(height: 1),
          ],
        ),
      );
    }

    if (call == null || call.participants.isEmpty) {
      return const SizedBox.shrink();
    }

    final count = call.participants.length;
    return Material(
      key: const ValueKey('direct-call-bar-join'),
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.call, size: 18, color: voiceConnectedColor),
            const SizedBox(width: 8),
            for (final participant in call.participants.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FallbackAvatar(
                  title: participant.name,
                  avatarUrl: participant.avatarUrl,
                  radius: 12,
                ),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                count == 1
                    ? tr('{name} is in a call', {
                        'name': call.participants.single.name,
                      })
                    : tr('{count} people are in a call', {'count': count}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: const ValueKey('direct-call-join-video'),
              tooltip: tr('Join with video'),
              onPressed: () => startDirectCall(
                context,
                ref,
                conversationId: conversationId,
                name: title,
                video: true,
              ),
              icon: const Icon(Icons.videocam_outlined),
            ),
            FilledButton.icon(
              key: const ValueKey('direct-call-join'),
              style: FilledButton.styleFrom(
                backgroundColor: voiceConnectedColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => startDirectCall(
                context,
                ref,
                conversationId: conversationId,
                name: title,
              ),
              icon: const Icon(Icons.call, size: 18),
              label: Text(tr('Join')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a prompt over [child] while a call rings for the current user,
/// with Decline, Join and Join with video.
class IncomingCallListener extends ConsumerStatefulWidget {
  const IncomingCallListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  /// Calls answered or declined here, hidden before the server catches up.
  final _handled = <String>{};

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authStateProvider).valueOrNull != null;
    final calls = signedIn
        ? ref.watch(activeDirectCallsProvider).valueOrNull ?? const []
        : const <DirectCall>[];
    final session = ref.watch(voiceSessionProvider);
    final ringing = calls.where(
      (call) =>
          call.ringing &&
          !_handled.contains(call.callId) &&
          call.participants.isNotEmpty &&
          !(session != null &&
              session.isDirectCall &&
              session.conversationId == call.conversationId),
    );
    final call = ringing.firstOrNull;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (call != null)
          Positioned(
            left: 12,
            right: 12,
            top: 0,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _IncomingCallCard(
                    key: ValueKey('incoming-call-${call.callId}'),
                    call: call,
                    onHandled: () => setState(() => _handled.add(call.callId)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IncomingCallCard extends ConsumerWidget {
  const _IncomingCallCard({
    required this.call,
    required this.onHandled,
    super.key,
  });

  final DirectCall call;
  final VoidCallback onHandled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    ConversationSummary? conversation;
    for (final candidate
        in ref.watch(conversationsProvider).valueOrNull ??
            const <ConversationSummary>[]) {
      if (candidate.id == call.conversationId) {
        conversation = candidate;
      }
    }
    final caller = call.caller;
    final callerName = caller?.name ?? tr('Someone');
    final isGroup = conversation?.type == ConversationType.group;
    final title = conversation?.title?.trim().isNotEmpty == true
        ? conversation!.title!.trim()
        : callerName;

    Future<void> join({required bool video}) async {
      onHandled();
      await startDirectCall(
        context,
        ref,
        conversationId: call.conversationId,
        name: title,
        video: video,
      );
    }

    return Card(
      key: const ValueKey('incoming-call-card'),
      elevation: 6,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            FallbackAvatar(
              title: isGroup ? title : callerName,
              avatarUrl: isGroup ? conversation?.avatarUrl : caller?.avatarUrl,
              radius: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    isGroup
                        ? tr('{name} started a call', {'name': callerName})
                        : tr('Incoming call'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              key: const ValueKey('incoming-call-decline'),
              tooltip: tr('Decline'),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () {
                onHandled();
                unawaited(
                  ref
                      .read(voiceRepositoryProvider)
                      .declineDirectCall(call.callId)
                      .catchError((Object _) {}),
                );
              },
              icon: const Icon(Icons.call_end),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              key: const ValueKey('incoming-call-join-video'),
              tooltip: tr('Join with video'),
              onPressed: () => join(video: true),
              icon: const Icon(Icons.videocam),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              key: const ValueKey('incoming-call-join'),
              tooltip: tr('Join'),
              style: IconButton.styleFrom(
                backgroundColor: voiceConnectedColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => join(video: false),
              icon: const Icon(Icons.call),
            ),
          ],
        ),
      ),
    );
  }
}
