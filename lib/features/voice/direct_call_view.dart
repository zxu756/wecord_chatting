import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The call in a direct or group chat, above its messages: while the
/// current user is in it, a dark call card with everyone in it and the
/// glass call controls; otherwise who is in it and a way to join. Nothing
/// when no call is going on.
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

    if (here) {
      final people = <String, VoiceCallPerson>{
        for (final participant
            in call?.participants ?? const <DirectCallParticipant>[])
          participant.userId: (
            name: participant.name,
            avatarUrl: participant.avatarUrl,
            selfDeaf: participant.selfDeaf,
            serverMute: false,
            serverDeaf: false,
          ),
      };
      final alone = session.isConnected && session.participants.length < 2;
      return Padding(
        key: const ValueKey('direct-call-bar-connected'),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: VoiceRoomTheme(
          child: Builder(
            builder: (context) {
              final c = context.tokens.colors;
              return ClipRRect(
                borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                child: VoiceRoomBackground(
                  child: !session.isConnected
                      ? Padding(
                          padding: const EdgeInsets.all(22),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                tr('Connecting…'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: c.muted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: VoiceStatusLine(
                                      text: alone
                                          ? tr('Calling…')
                                          : tr('In a call'),
                                      color: alone ? c.muted : c.successText,
                                      dotColor: alone ? c.warning : c.success,
                                      key: alone
                                          ? const ValueKey(
                                              'direct-call-waiting',
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * 0.36,
                              ),
                              child: MediaQuery.removePadding(
                                context: context,
                                removeBottom: true,
                                removeTop: true,
                                child: VoiceCallGrid(
                                  session: session,
                                  people: people,
                                  shrinkWrap: true,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                              child: VoiceCallControls(session: session),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
      );
    }

    if (call == null || call.participants.isEmpty) {
      return const SizedBox.shrink();
    }

    final c = context.tokens.colors;
    final count = call.participants.length;
    final shown = call.participants.take(3).toList();
    return Padding(
      key: const ValueKey('direct-call-bar-join'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: c.successSoft,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          children: [
            Icon(Icons.call_rounded, size: 20, color: c.successText),
            const SizedBox(width: 10),
            SizedBox(
              width: 30 + (shown.length - 1) * 24,
              height: 30,
              child: Stack(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * 24,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.successSoft, width: 2),
                        ),
                        child: VoiceAvatar(
                          name: shown[i].name,
                          avatarUrl: shown[i].avatarUrl,
                          size: 26,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: count == 1
                  ? _NameInSentence(
                      key: const ValueKey('direct-call-join-text'),
                      template: tr('{name} is in a call'),
                      name: call.participants.single.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    )
                  : Text(
                      tr('{count} people are in a call', {'count': count}),
                      key: const ValueKey('direct-call-join-text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
            ),
            VoiceRoundButton(
              key: const ValueKey('direct-call-join-video'),
              tooltip: tr('Join with video'),
              icon: Icons.videocam_rounded,
              fill: c.panel,
              foreground: c.successText,
              size: 36,
              onPressed: () => startDirectCall(
                context,
                ref,
                conversationId: conversationId,
                name: title,
                video: true,
              ),
            ),
            const SizedBox(width: 4),
            VoicePillButton(
              key: const ValueKey('direct-call-join'),
              label: tr('Join'),
              icon: Icons.call_rounded,
              height: 36,
              fill: c.success,
              foreground: c.onDanger,
              onPressed: () {
                WeCordHaptics.medium();
                startDirectCall(
                  context,
                  ref,
                  conversationId: conversationId,
                  name: title,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a prompt over [child] while a call rings for the current user,
/// with Decline, Join with video and Join.
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
    final signedIn = ref.watch(authStateProvider).value != null;
    final calls = signedIn
        ? ref.watch(activeDirectCallsProvider).value ?? const []
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
    final c = context.tokens.colors;
    ConversationSummary? conversation;
    for (final candidate
        in ref.watch(conversationsProvider).value ??
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
      WeCordHaptics.medium();
      onHandled();
      await startDirectCall(
        context,
        ref,
        conversationId: call.conversationId,
        name: title,
        video: video,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        type: MaterialType.transparency,
        child: WeCordGlass(
          key: const ValueKey('incoming-call-card'),
          elevation: GlassElevation.menu,
          borderRadius: BorderRadius.circular(WeCordRadii.xxl),
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              if (isGroup)
                ThingAvatar(label: title, size: 46)
              else
                VoiceAvatar(
                  name: callerName,
                  avatarUrl: caller?.avatarUrl,
                  size: 46,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Icon(
                          Icons.call_rounded,
                          size: 13,
                          color: c.successText,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isGroup
                                ? tr('{name} started a call', {
                                    'name': callerName,
                                  })
                                : tr('Incoming call'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              VoiceRoundButton(
                key: const ValueKey('incoming-call-decline'),
                tooltip: tr('Decline'),
                icon: Icons.call_end_rounded,
                fill: c.danger,
                foreground: c.onDanger,
                size: 44,
                onPressed: () {
                  onHandled();
                  unawaited(
                    ref
                        .read(voiceRepositoryProvider)
                        .declineDirectCall(call.callId)
                        .catchError((Object _) {}),
                  );
                },
              ),
              VoiceRoundButton(
                key: const ValueKey('incoming-call-join-video'),
                tooltip: tr('Join with video'),
                icon: Icons.videocam_rounded,
                fill: c.raised,
                foreground: c.ink,
                size: 44,
                onPressed: () => join(video: true),
              ),
              VoiceRoundButton(
                key: const ValueKey('incoming-call-join'),
                tooltip: tr('Join'),
                icon: Icons.call_rounded,
                fill: c.success,
                foreground: c.onDanger,
                size: 44,
                onPressed: () => join(video: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line sentence around a name ("{name} is in a call", already
/// translated): a long name is cut short, never the rest of the sentence.
class _NameInSentence extends StatelessWidget {
  const _NameInSentence({
    required this.template,
    required this.name,
    required this.style,
    super.key,
  });

  /// The sentence with a `{name}` placeholder.
  final String template;
  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final at = template.indexOf('{name}');
    if (at < 0) {
      return Text(
        template,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final before = template.substring(0, at);
    final after = template.substring(at + '{name}'.length);
    final sentence = '$before$name$after';
    return Semantics(
      label: sentence,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(
              text: '$before$after',
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final rest = painter.width;
          painter.dispose();
          // Too narrow for the sentence plus a bit of the name: cut the
          // whole line instead.
          if (rest + 48 > constraints.maxWidth) {
            return Text(
              sentence,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
          }
          return Row(
            children: [
              if (before.isNotEmpty) Text(before, maxLines: 1, style: style),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              if (after.isNotEmpty) Text(after, maxLines: 1, style: style),
            ],
          );
        },
      ),
    );
  }
}
