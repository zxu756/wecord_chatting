import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/voice/stage_repository.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/voice.dart';

/// The live stage in [channelId], if any; null while loading too.
StageInstance? watchStage(WidgetRef ref, String circleId, String channelId) {
  return ref.watch(stageInstancesProvider(circleId)).valueOrNull?[channelId];
}

/// Runs stage actions and keeps the voice server and lists in step.
class StageActions {
  StageActions(this.ref, {required this.circleId, required this.channelId});

  final WidgetRef ref;
  final String circleId;
  final String channelId;

  String? get _currentUserId => ref.read(authStateProvider).valueOrNull?.id;

  StageRepository get _stages => ref.read(stageRepositoryProvider);

  /// Runs [action], says so when it fails, and refreshes what it changed.
  /// [action] returns the people whose voice room should follow the
  /// database.
  Future<void> _run(
    BuildContext context,
    Future<List<String>> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final List<String> changed;
    try {
      changed = await action();
    } on StageNotLiveException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not change the stage. Try again.'))),
      );
      return;
    }
    ref.invalidate(voiceStatesProvider(circleId));
    ref.invalidate(stageInstancesProvider(circleId));
    final self = _currentUserId;
    final voice = ref.read(voiceRepositoryProvider);
    for (final userId in changed) {
      if (userId == self) {
        continue;
      }
      // Best effort: their own client asks the voice server too.
      unawaited(
        voice
            .enforceVoiceState(channelId: channelId, userId: userId)
            .catchError((Object _) {}),
      );
    }
    if (ref.read(voiceSessionProvider)?.channelId == channelId) {
      await ref.read(voiceSessionProvider.notifier).syncOwnState();
    }
  }

  Future<void> start(BuildContext context, String topic) {
    return _run(context, () async {
      await _stages.startStage(channelId: channelId, topic: topic);
      return const [];
    });
  }

  Future<void> end(BuildContext context) {
    return _run(context, () => _stages.endStage(channelId));
  }

  Future<void> setHandRaised(BuildContext context, bool raised) {
    return _run(context, () async {
      await _stages.setHandRaised(channelId: channelId, raised: raised);
      return const [];
    });
  }

  Future<void> invite(BuildContext context, String userId) {
    return _run(context, () async {
      final speaking = await _stages.inviteToSpeak(
        channelId: channelId,
        userId: userId,
      );
      return speaking ? [userId] : const [];
    });
  }

  Future<void> respond(BuildContext context, {required bool accept}) {
    return _run(context, () async {
      await _stages.respondToInvite(channelId: channelId, accept: accept);
      return const [];
    });
  }

  Future<void> moveToAudience(BuildContext context, String userId) {
    return _run(context, () async {
      await _stages.moveToAudience(channelId: channelId, userId: userId);
      return [userId];
    });
  }
}

/// Asks for a stage's topic; null when cancelled.
Future<String?> showStageTopicDialog(
  BuildContext context, {
  String? initialTopic,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _StageTopicDialog(initialTopic: initialTopic),
  );
}

class _StageTopicDialog extends StatefulWidget {
  const _StageTopicDialog({this.initialTopic});

  final String? initialTopic;

  @override
  State<_StageTopicDialog> createState() => _StageTopicDialogState();
}

class _StageTopicDialogState extends State<_StageTopicDialog> {
  late final _controller = TextEditingController(text: widget.initialTopic);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final topic = _controller.text.trim();
    if (topic.isNotEmpty) {
      Navigator.of(context).pop(topic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialTopic != null;
    return AlertDialog(
      key: const ValueKey('stage-topic-dialog'),
      scrollable: true,
      title: Text(editing ? tr('Edit topic') : tr('Start stage')),
      content: TextField(
        key: const ValueKey('stage-topic-field'),
        controller: _controller,
        autofocus: true,
        maxLength: StageInstance.maxTopicLength,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: tr('Topic'),
          hintText: tr('What is the stage about?'),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            key: const ValueKey('stage-topic-submit'),
            onPressed: _controller.text.trim().isEmpty ? null : _submit,
            child: Text(editing ? tr('Save') : tr('Start stage')),
          ),
        ),
      ],
    );
  }
}

/// The topic, or that no stage is live; moderators start, edit and end it.
class _StageHeader extends ConsumerWidget {
  const _StageHeader({
    required this.stage,
    required this.moderator,
    required this.actions,
  });

  final StageInstance? stage;
  final bool moderator;
  final StageActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stage = this.stage;
    return Container(
      key: const ValueKey('stage-header'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.podcasts,
                color: stage == null
                    ? colorScheme.onSurfaceVariant
                    : voiceConnectedColor,
              ),
              const SizedBox(width: 8),
              if (stage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: voiceConnectedColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tr('Live'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  stage?.topic ?? tr('No stage is live right now.'),
                  key: const ValueKey('stage-topic'),
                  style: stage == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (moderator) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (stage == null)
                  FilledButton.icon(
                    key: const ValueKey('stage-start-button'),
                    onPressed: () async {
                      final topic = await showStageTopicDialog(context);
                      if (topic != null && context.mounted) {
                        await actions.start(context, topic);
                      }
                    },
                    icon: const Icon(Icons.podcasts),
                    label: Text(tr('Start stage')),
                  )
                else ...[
                  OutlinedButton.icon(
                    key: const ValueKey('stage-edit-topic-button'),
                    onPressed: () async {
                      final topic = await showStageTopicDialog(
                        context,
                        initialTopic: stage.topic,
                      );
                      if (topic != null && context.mounted) {
                        await actions.start(context, topic);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr('Edit topic')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('stage-end-button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    onPressed: () => actions.end(context),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(tr('End stage')),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Someone on the stage, as the server and the media connection see them.
@immutable
class _StagePerson {
  const _StagePerson({
    required this.member,
    required this.speaking,
    required this.micOff,
  });

  final VoiceMemberState member;
  final bool speaking;
  final bool micOff;
}

/// Who is on the stage: the topic, the speakers, the raised hands (for
/// moderators) and the audience, above [StageControls].
class StageView extends ConsumerWidget {
  const StageView({
    required this.session,
    required this.circleId,
    required this.channelId,
    required this.members,
    required this.moderator,
    super.key,
  });

  final VoiceSession session;
  final String circleId;
  final String channelId;
  final List<VoiceMemberState> members;

  /// The current user moderates the stage.
  final bool moderator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = watchStage(ref, circleId, channelId);
    final currentUserId = ref.watch(authStateProvider).valueOrNull?.id;
    final actions = StageActions(ref, circleId: circleId, channelId: channelId);
    final participants = {
      for (final participant in session.participants)
        participant.userId: participant,
    };
    _StagePerson person(VoiceMemberState member) {
      final participant = participants[member.userId];
      final isSelf = member.userId == currentUserId;
      return _StagePerson(
        member: member,
        speaking: participant?.isSpeaking ?? false,
        micOff:
            member.serverMute ||
            (isSelf
                ? !session.microphoneWanted
                : member.selfMute ||
                      !(participant?.microphoneEnabled ?? false)),
      );
    }

    final speakers = [
      for (final member in members)
        if (member.userId == currentUserId
            ? session.stageSpeaker
            : member.stageSpeaker)
          person(member),
    ];
    final audience = [
      for (final member in members)
        if (!(member.userId == currentUserId
            ? session.stageSpeaker
            : member.stageSpeaker))
          person(member),
    ];
    final hands = [
      for (final entry in audience)
        if (entry.member.handRaised) entry.member,
    ]..sort((a, b) => a.handRaisedAt!.compareTo(b.handRaisedAt!));

    final theme = Theme.of(context);
    Widget heading(String text, Key key) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          text,
          key: key,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    void openMenu(Offset position, VoiceMemberState member, bool isSpeaker) {
      final isSelf = member.userId == currentUserId;
      unawaited(
        _showStagePersonMenu(
          context,
          position: position,
          name: member.name,
          canInvite: moderator && !isSpeaker && stage != null,
          canMoveDown: isSpeaker && (moderator || isSelf),
          onInvite: () => actions.invite(context, member.userId),
          onMoveDown: () => actions.moveToAudience(context, member.userId),
        ),
      );
    }

    return ListView(
      key: const ValueKey('stage-view'),
      padding: const EdgeInsets.all(12),
      children: [
        _StageHeader(stage: stage, moderator: moderator, actions: actions),
        if (session.stageInvited) ...[
          const SizedBox(height: 12),
          _InviteBanner(actions: actions),
        ],
        heading(
          tr('Speakers ({count})', {'count': speakers.length}),
          const ValueKey('stage-speakers-heading'),
        ),
        if (speakers.isEmpty)
          Text(
            tr('No one is speaking yet.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final speaker in speakers)
                _StageTile(
                  key: ValueKey('stage-speaker-${speaker.member.userId}'),
                  person: speaker,
                  radius: usesTouchInput(context) ? 30 : 34,
                  isSelf: speaker.member.userId == currentUserId,
                  onMenu: (position) =>
                      openMenu(position, speaker.member, true),
                ),
            ],
          ),
        if (moderator && hands.isNotEmpty) ...[
          heading(
            tr('Raised hands ({count})', {'count': hands.length}),
            const ValueKey('stage-hands-heading'),
          ),
          for (final member in hands)
            ListTile(
              key: ValueKey('stage-hand-${member.userId}'),
              contentPadding: EdgeInsets.zero,
              leading: FallbackAvatar(
                title: member.name,
                avatarUrl: member.avatarUrl,
                radius: 16,
              ),
              title: Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: FilledButton.tonal(
                key: ValueKey('stage-accept-hand-${member.userId}'),
                onPressed: () => actions.invite(context, member.userId),
                child: Text(tr('Invite to speak')),
              ),
            ),
        ],
        heading(
          tr('Audience ({count})', {'count': audience.length}),
          const ValueKey('stage-audience-heading'),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final listener in audience)
              _StageTile(
                key: ValueKey('stage-listener-${listener.member.userId}'),
                person: listener,
                radius: 22,
                isSelf: listener.member.userId == currentUserId,
                listener: true,
                onMenu: (position) =>
                    openMenu(position, listener.member, false),
              ),
          ],
        ),
      ],
    );
  }
}

class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.actions});

  final StageActions actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('stage-invite-banner'),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            tr("You're invited to speak."),
            style: TextStyle(color: colorScheme.onPrimaryContainer),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('stage-invite-decline'),
                onPressed: () => actions.respond(context, accept: false),
                child: Text(tr('Decline')),
              ),
              FilledButton(
                key: const ValueKey('stage-invite-accept'),
                onPressed: () => actions.respond(context, accept: true),
                child: Text(tr('Accept')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An avatar (ringed while speaking) and name; tapping it opens [onMenu].
class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.person,
    required this.radius,
    required this.isSelf,
    required this.onMenu,
    this.listener = false,
    super.key,
  });

  final _StagePerson person;
  final double radius;
  final bool isSelf;
  final bool listener;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = person.member;
    final name = isSelf
        ? tr('{name} (you)', {'name': member.name})
        : member.name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => onMenu(details.globalPosition),
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: SizedBox(
        width: radius * 2 + 28,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                VoiceSpeakingRing(
                  speaking: person.speaking,
                  child: FallbackAvatar(
                    title: member.name,
                    avatarUrl: member.avatarUrl,
                    radius: radius,
                  ),
                ),
                if (listener && member.handRaised)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: CircleAvatar(
                      key: ValueKey('stage-hand-badge-${member.userId}'),
                      radius: 10,
                      backgroundColor: theme.colorScheme.tertiaryContainer,
                      child: Icon(
                        Icons.back_hand,
                        size: 12,
                        color: theme.colorScheme.onTertiaryContainer,
                        semanticLabel: tr('Hand raised'),
                      ),
                    ),
                  )
                else if (!listener && person.micOff)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.mic_off,
                        size: 12,
                        color: member.serverMute
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                        semanticLabel: tr('Muted'),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style:
                  (listener
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                        fontWeight: person.speaking ? FontWeight.w700 : null,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showStagePersonMenu(
  BuildContext context, {
  required Offset position,
  required String name,
  required bool canInvite,
  required bool canMoveDown,
  required VoidCallback onInvite,
  required VoidCallback onMoveDown,
}) async {
  if (!canInvite && !canMoveDown) {
    return;
  }
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        height: 32,
        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      if (canInvite)
        PopupMenuItem(
          key: const ValueKey('stage-menu-invite'),
          value: 'invite',
          child: ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: Text(tr('Invite to speak')),
          ),
        ),
      if (canMoveDown)
        PopupMenuItem(
          key: const ValueKey('stage-menu-audience'),
          value: 'audience',
          child: ListTile(
            leading: const Icon(Icons.voice_over_off_outlined),
            title: Text(tr('Move to audience')),
          ),
        ),
    ],
  );
  switch (choice) {
    case 'invite':
      onInvite();
    case 'audience':
      onMoveDown();
  }
}

/// Who is on a stage the current user hasn't joined: the topic, the
/// speakers and how many listen, and a Join button.
class StageLobby extends ConsumerWidget {
  const StageLobby({
    required this.circleId,
    required this.channelId,
    required this.members,
    required this.canConnect,
    required this.onJoin,
    super.key,
  });

  final String circleId;
  final String channelId;
  final List<VoiceMemberState> members;
  final bool canConnect;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stage = watchStage(ref, circleId, channelId);
    final speakers = [
      for (final member in members)
        if (member.stageSpeaker) member,
    ];
    final listening = members.length - speakers.length;
    return Center(
      key: const ValueKey('stage-lobby'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.podcasts,
              size: 48,
              color: stage == null
                  ? theme.colorScheme.onSurfaceVariant
                  : voiceConnectedColor,
            ),
            const SizedBox(height: 12),
            Text(
              stage?.topic ?? tr('No stage is live right now.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              tr('{count} listening', {'count': listening}),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (speakers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final speaker in speakers)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FallbackAvatar(
                          title: speaker.name,
                          avatarUrl: speaker.avatarUrl,
                          radius: 22,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 72,
                          child: Text(
                            speaker.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            if (canConnect)
              FilledButton.icon(
                key: const ValueKey('stage-join-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: voiceConnectedColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: onJoin,
                icon: const Icon(Icons.headphones),
                label: Text(tr('Join stage')),
              )
            else
              Text(
                tr("You don't have permission to join this voice channel."),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}

/// A stage's controls: speakers get the microphone and can step down;
/// the audience raises a hand (moderators can step up); everyone can
/// deafen and leave.
class StageControls extends ConsumerStatefulWidget {
  const StageControls({
    required this.session,
    required this.circleId,
    required this.channelId,
    required this.moderator,
    super.key,
  });

  final VoiceSession session;
  final String circleId;
  final String channelId;
  final bool moderator;

  @override
  ConsumerState<StageControls> createState() => _StageControlsState();
}

class _StageControlsState extends ConsumerState<StageControls> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final controller = ref.read(voiceSessionProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final stage = watchStage(ref, widget.circleId, widget.channelId);
    final actions = StageActions(
      ref,
      circleId: widget.circleId,
      channelId: widget.channelId,
    );
    final currentUserId = ref.watch(authStateProvider).valueOrNull?.id;
    final hasKey = ref.watch(
      voiceSettingsProvider.select(
        (settings) => settings.pushToTalkKeyId != null,
      ),
    );
    final holdToTalk =
        session.stageSpeaker &&
        session.pushToTalk &&
        (usesTouchInput(context) || !hasKey);

    Widget toggle({
      required Key key,
      required String tooltip,
      required IconData icon,
      required bool on,
      required VoidCallback? onPressed,
    }) {
      return IconButton.filledTonal(
        key: key,
        tooltip: tooltip,
        isSelected: on,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          backgroundColor: on ? colorScheme.inverseSurface : null,
          foregroundColor: on ? colorScheme.onInverseSurface : null,
        ),
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon),
      );
    }

    return Material(
      key: const ValueKey('stage-controls'),
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (session.stageSpeaker) ...[
                if (holdToTalk)
                  VoiceHoldToTalkButton(session: session, enabled: !_busy),
                toggle(
                  key: const ValueKey('voice-control-mic'),
                  tooltip: voiceMuteTooltip(session),
                  icon: session.selfMute || session.serverMute
                      ? Icons.mic_off
                      : Icons.mic_none,
                  on: session.selfMute || session.serverMute,
                  onPressed: session.serverMute
                      ? null
                      : () => _run(
                          controller.toggleMute,
                          tr('Could not change the microphone.'),
                        ),
                ),
              ] else
                toggle(
                  key: const ValueKey('stage-control-hand'),
                  tooltip: session.handRaised
                      ? tr('Lower hand')
                      : tr('Raise hand'),
                  icon: session.handRaised
                      ? Icons.back_hand
                      : Icons.back_hand_outlined,
                  on: session.handRaised,
                  onPressed: stage == null
                      ? null
                      : () => _run(
                          () => actions.setHandRaised(
                            context,
                            !session.handRaised,
                          ),
                          tr('Could not change the stage. Try again.'),
                        ),
                ),
              toggle(
                key: const ValueKey('voice-control-deafen'),
                tooltip: voiceDeafenTooltip(session),
                icon: session.selfDeaf || session.serverDeaf
                    ? Icons.headset_off
                    : Icons.headset_outlined,
                on: session.selfDeaf || session.serverDeaf,
                onPressed: session.serverDeaf
                    ? null
                    : () => _run(
                        controller.toggleDeafen,
                        tr('Could not deafen.'),
                      ),
              ),
              if (currentUserId != null && session.stageSpeaker)
                toggle(
                  key: const ValueKey('stage-control-audience'),
                  tooltip: tr('Move to audience'),
                  icon: Icons.voice_over_off_outlined,
                  on: false,
                  onPressed: () => _run(
                    () => actions.moveToAudience(context, currentUserId),
                    tr('Could not change the stage. Try again.'),
                  ),
                )
              else if (currentUserId != null &&
                  widget.moderator &&
                  stage != null)
                toggle(
                  key: const ValueKey('stage-control-speak'),
                  tooltip: tr('Become a speaker'),
                  icon: Icons.record_voice_over_outlined,
                  on: false,
                  onPressed: () => _run(
                    () => actions.invite(context, currentUserId),
                    tr('Could not change the stage. Try again.'),
                  ),
                ),
              IconButton.filled(
                key: const ValueKey('voice-control-leave'),
                tooltip: tr('Disconnect'),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(48),
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                onPressed: controller.leave,
                icon: const Icon(Icons.call_end),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
