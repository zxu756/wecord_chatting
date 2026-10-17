import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/soundboard_sheet.dart';
import 'package:wecord/features/voice/stage_repository.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_menu.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/voice.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The live stage in [channelId], if any; null while loading too.
StageInstance? watchStage(WidgetRef ref, String circleId, String channelId) {
  return ref.watch(stageInstancesProvider(circleId)).value?[channelId];
}

/// Runs stage actions and keeps the voice server and lists in step.
class StageActions {
  StageActions(this.ref, {required this.circleId, required this.channelId});

  final WidgetRef ref;
  final String circleId;
  final String channelId;

  String? get _currentUserId => ref.read(authStateProvider).value?.id;

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
      content: SizedBox(
        width: 360,
        child: WeCordTextField(
          fieldKey: const ValueKey('stage-topic-field'),
          controller: _controller,
          autofocus: true,
          maxLength: StageInstance.maxTopicLength,
          label: tr('Topic'),
          hint: tr('What is the stage about?'),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => WeCordButton(
            key: const ValueKey('stage-topic-submit'),
            label: editing ? tr('Save') : tr('Start stage'),
            onPressed: _controller.text.trim().isEmpty ? null : _submit,
          ),
        ),
      ],
    );
  }
}

/// The topic as the room's big title, or that no stage is live;
/// moderators start, edit and end it.
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
    final c = context.tokens.colors;
    final stage = this.stage;
    return Column(
      key: const ValueKey('stage-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.liveSoft,
              borderRadius: BorderRadius.circular(WeCordRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.podcasts, size: 13, color: c.liveText),
                const SizedBox(width: 4),
                Text(
                  tr('Live'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: c.liveText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          stage?.topic ?? tr('No stage is live right now.'),
          key: const ValueKey('stage-topic'),
          style: stage == null
              ? TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                )
              : TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.2,
                  color: c.ink,
                ),
        ),
        if (moderator) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (stage == null)
                WeCordButton(
                  key: const ValueKey('stage-start-button'),
                  label: tr('Start stage'),
                  icon: Icons.podcasts,
                  variant: WeCordButtonVariant.accent,
                  size: WeCordButtonSize.small,
                  onPressed: () async {
                    final topic = await showStageTopicDialog(context);
                    if (topic != null && context.mounted) {
                      await actions.start(context, topic);
                    }
                  },
                )
              else ...[
                WeCordButton(
                  key: const ValueKey('stage-edit-topic-button'),
                  label: tr('Edit topic'),
                  icon: Icons.edit_outlined,
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  onPressed: () async {
                    final topic = await showStageTopicDialog(
                      context,
                      initialTopic: stage.topic,
                    );
                    if (topic != null && context.mounted) {
                      await actions.start(context, topic);
                    }
                  },
                ),
                WeCordButton(
                  key: const ValueKey('stage-end-button'),
                  label: tr('End stage'),
                  icon: Icons.stop_circle_outlined,
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  onPressed: () => actions.end(context),
                ),
              ],
            ],
          ),
        ],
      ],
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

/// Who is on the stage: the topic, the speakers as cards, the raised hands
/// (for moderators) and the audience grid, above [StageControls].
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
    final c = context.tokens.colors;
    final stage = watchStage(ref, circleId, channelId);
    final currentUserId = ref.watch(authStateProvider).value?.id;
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

    Widget heading(String text, Key key) {
      return Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: VoiceSectionLabel(text, key: key),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final touch = usesTouchInput(context);
        final side = constraints.maxWidth < 600 ? 16.0 : 24.0;
        final width = math.min(constraints.maxWidth - side * 2, 960.0);
        const gap = 10.0;
        final speakerColumns = (width / 150).floor().clamp(3, 6);
        final speakerWidth =
            (width - gap * (speakerColumns - 1)) / speakerColumns;
        final audienceColumns = (width / (touch ? 56 : 76)).floor().clamp(
          4,
          14,
        );
        final audienceWidth =
            (width - 6 * (audienceColumns - 1)) / audienceColumns;
        return ListView(
          key: const ValueKey('stage-view'),
          padding: EdgeInsets.fromLTRB(
            (constraints.maxWidth - width) / 2,
            12,
            (constraints.maxWidth - width) / 2,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _StageHeader(stage: stage, moderator: moderator, actions: actions),
            if (session.stageInvited) ...[
              const SizedBox(height: 16),
              _InviteBanner(actions: actions),
            ],
            heading(
              tr('Speakers ({count})', {'count': speakers.length}),
              const ValueKey('stage-speakers-heading'),
            ),
            if (speakers.isEmpty)
              Text(
                tr('No one is speaking yet.'),
                style: TextStyle(fontSize: 14, color: c.muted),
              )
            else
              Wrap(
                // A few speakers sit in the middle of a wide stage.
                alignment: speakers.length < speakerColumns
                    ? WrapAlignment.center
                    : WrapAlignment.start,
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final speaker in speakers)
                    SizedBox(
                      width: speakerWidth,
                      child: _SpeakerCard(
                        key: ValueKey('stage-speaker-${speaker.member.userId}'),
                        person: speaker,
                        isSelf: speaker.member.userId == currentUserId,
                        onMenu: (position) =>
                            openMenu(position, speaker.member, true),
                      ),
                    ),
                ],
              ),
            if (moderator && hands.isNotEmpty) ...[
              heading(
                tr('Raised hands ({count})', {'count': hands.length}),
                const ValueKey('stage-hands-heading'),
              ),
              for (final member in hands)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RaisedHand(
                    key: ValueKey('stage-hand-${member.userId}'),
                    member: member,
                    onInvite: () => actions.invite(context, member.userId),
                  ),
                ),
            ],
            heading(
              tr('Audience ({count})', {'count': audience.length}),
              const ValueKey('stage-audience-heading'),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 14,
              children: [
                for (final listener in audience)
                  SizedBox(
                    width: audienceWidth,
                    child: _ListenerTile(
                      key: ValueKey('stage-listener-${listener.member.userId}'),
                      person: listener,
                      isSelf: listener.member.userId == currentUserId,
                      onMenu: (position) =>
                          openMenu(position, listener.member, false),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.actions});

  final StageActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('stage-invite-banner'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(WeCordRadii.bubble),
      ),
      child: Row(
        children: [
          Icon(Icons.record_voice_over_rounded, size: 22, color: c.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr("You're invited to speak."),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          WeCordButton(
            key: const ValueKey('stage-invite-decline'),
            label: tr('Decline'),
            variant: WeCordButtonVariant.ghost,
            size: WeCordButtonSize.small,
            onPressed: () => actions.respond(context, accept: false),
          ),
          const SizedBox(width: 4),
          WeCordButton(
            key: const ValueKey('stage-invite-accept'),
            label: tr('Accept'),
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.small,
            onPressed: () => actions.respond(context, accept: true),
          ),
        ],
      ),
    );
  }
}

/// Someone in the audience with a raised hand, for moderators: "Invite to
/// speak" brings them on stage.
class _RaisedHand extends StatelessWidget {
  const _RaisedHand({required this.member, required this.onInvite, super.key});

  final VoiceMemberState member;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(WeCordRadii.bubble),
      ),
      child: Row(
        children: [
          VoiceAvatar(name: member.name, avatarUrl: member.avatarUrl, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.back_hand_rounded, size: 12, color: c.warning),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tr('Hand raised'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.warningText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          WeCordButton(
            key: ValueKey('stage-accept-hand-${member.userId}'),
            label: tr('Invite to speak'),
            size: WeCordButtonSize.small,
            onPressed: onInvite,
          ),
        ],
      ),
    );
  }
}

/// Opens [onMenu] at the tap (or right click) position.
class _MenuTarget extends StatelessWidget {
  const _MenuTarget({required this.onMenu, required this.child});

  final ValueChanged<Offset> onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: Builder(
        builder: (context) => WeCordPressable(
          onPressed: () {
            final box = context.findRenderObject()! as RenderBox;
            onMenu(box.localToGlobal(box.size.center(Offset.zero)));
          },
          hint: tr('Opens the menu'),
          pressedScale: 1,
          minTapSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          builder: (context, states) => child,
        ),
      ),
    );
  }
}

/// A speaker's card: a big avatar (ringed while speaking), their name and
/// whether they speak right now; tapping it opens [onMenu].
class _SpeakerCard extends StatelessWidget {
  const _SpeakerCard({
    required this.person,
    required this.isSelf,
    required this.onMenu,
    super.key,
  });

  final _StagePerson person;
  final bool isSelf;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final member = person.member;
    final speaking = person.speaking;
    final name = isSelf
        ? tr('{name} (you)', {'name': member.name})
        : member.name;
    return _MenuTarget(
      onMenu: onMenu,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avatar = (constraints.maxWidth * 0.62).clamp(48.0, 84.0);
          return AnimatedContainer(
            duration: WeCordMotion.durationOf(context, WeCordMotion.quick),
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 12),
            decoration: BoxDecoration(
              color: speaking
                  ? c.success.withValues(alpha: 0.14)
                  : c.ink.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(WeCordRadii.xl + 2),
              border: Border.all(
                color: speaking
                    ? c.successText.withValues(alpha: 0.5)
                    : c.ink.withValues(alpha: 0),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VoiceAvatar(
                  name: member.name,
                  avatarUrl: member.avatarUrl,
                  size: avatar,
                  speaking: speaking,
                  badge: person.micOff
                      ? VoiceAvatarBadge(
                          icon: Icons.mic_off_rounded,
                          label: tr('Muted'),
                          color: member.serverMute ? c.danger : c.dangerText,
                          size: avatar * 0.34,
                        )
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  speaking ? tr('Speaking') : tr('Speaker'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: speaking ? c.successText : c.muted,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Someone in the audience: avatar and name, with a hand when raised.
class _ListenerTile extends StatelessWidget {
  const _ListenerTile({
    required this.person,
    required this.isSelf,
    required this.onMenu,
    super.key,
  });

  final _StagePerson person;
  final bool isSelf;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final member = person.member;
    return _MenuTarget(
      onMenu: onMenu,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              VoiceAvatar(
                name: member.name,
                avatarUrl: member.avatarUrl,
                size: 44,
                speaking: person.speaking,
              ),
              if (member.handRaised)
                Positioned(
                  right: -6,
                  top: -6,
                  child: VoiceAvatarBadge(
                    key: ValueKey('stage-hand-badge-${member.userId}'),
                    icon: Icons.back_hand_rounded,
                    label: tr('Hand raised'),
                    fill: c.warning,
                    color: c.onInk,
                    size: 22,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            isSelf ? tr('{name} (you)', {'name': member.name}) : member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: person.speaking ? FontWeight.w700 : FontWeight.w500,
              color: person.speaking ? c.ink : c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StageMenuAction { invite, audience }

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
  final choice = await showVoiceMenu<_StageMenuAction>(
    context,
    position: position,
    title: name,
    leading: PersonAvatar(name: name, size: 30),
    items: [
      if (canInvite)
        VoiceMenuAction(
          key: const ValueKey('stage-menu-invite'),
          value: _StageMenuAction.invite,
          icon: Icons.record_voice_over_outlined,
          label: tr('Invite to speak'),
        ),
      if (canMoveDown)
        VoiceMenuAction(
          key: const ValueKey('stage-menu-audience'),
          value: _StageMenuAction.audience,
          icon: Icons.voice_over_off_outlined,
          label: tr('Move to audience'),
        ),
    ],
  );
  switch (choice) {
    case _StageMenuAction.invite:
      onInvite();
    case _StageMenuAction.audience:
      onMoveDown();
    case null:
      break;
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
    final c = context.tokens.colors;
    final stage = watchStage(ref, circleId, channelId);
    final speakers = [
      for (final member in members)
        if (member.stageSpeaker) member,
    ];
    final listening = members.length - speakers.length;
    return Center(
      key: const ValueKey('stage-lobby'),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThingAvatar(
                size: 84,
                radius: 28,
                icon: Icons.podcasts,
                color: stage == null
                    ? c.ink.withValues(alpha: 0.08)
                    : c.success.withValues(alpha: 0.2),
                foregroundColor: stage == null ? c.ink : c.successText,
              ),
              const SizedBox(height: 18),
              Text(
                stage?.topic ?? tr('No stage is live right now.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('{count} listening', {'count': listening}),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
              if (speakers.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 12,
                  children: [
                    for (final speaker in speakers)
                      SizedBox(
                        width: 72,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VoiceAvatar(
                              name: speaker.name,
                              avatarUrl: speaker.avatarUrl,
                              size: 56,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              speaker.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              if (canConnect)
                WeCordButton(
                  key: const ValueKey('stage-join-button'),
                  label: tr('Join stage'),
                  icon: Icons.headphones_rounded,
                  variant: WeCordButtonVariant.accent,
                  size: WeCordButtonSize.large,
                  onPressed: () {
                    WeCordHaptics.medium();
                    onJoin();
                  },
                )
              else
                Text(
                  tr("You don't have permission to join this voice channel."),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A stage's controls in the floating glass bar: speakers get the
/// microphone and can step down; the audience raises a hand (moderators can
/// step up); everyone can deafen, open the chat and leave.
class StageControls extends ConsumerStatefulWidget {
  const StageControls({
    required this.session,
    required this.circleId,
    required this.channelId,
    required this.moderator,
    this.soundboard,
    this.chat,
    super.key,
  });

  final VoiceSession session;
  final String circleId;
  final String channelId;
  final bool moderator;

  /// The circle's soundboard, which speakers can play into the stage.
  final SoundboardAccess? soundboard;

  /// The chat button, when the stage has a chat to open.
  final VoiceControl? chat;

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
    final c = context.tokens.colors;
    final session = widget.session;
    final controller = ref.read(voiceSessionProvider.notifier);
    final stage = watchStage(ref, widget.circleId, widget.channelId);
    final actions = StageActions(
      ref,
      circleId: widget.circleId,
      channelId: widget.channelId,
    );
    final currentUserId = ref.watch(authStateProvider).value?.id;
    final hasKey = ref.watch(
      voiceSettingsProvider.select(
        (settings) => settings.pushToTalkKeyId != null,
      ),
    );
    final holdToTalk =
        session.stageSpeaker &&
        session.pushToTalk &&
        (usesTouchInput(context) || !hasKey);
    final muted = session.selfMute || session.serverMute;
    final deafened = session.selfDeaf || session.serverDeaf;

    VoidCallback? guard(VoidCallback? action) => _busy ? null : action;

    return KeyedSubtree(
      key: const ValueKey('stage-controls'),
      child: VoiceControlBar(
        above: holdToTalk
            ? VoiceHoldToTalkButton(session: session, enabled: !_busy)
            : null,
        controls: [
          if (session.stageSpeaker)
            VoiceControl(
              key: const ValueKey('voice-control-mic'),
              tooltip: voiceMuteTooltip(session),
              icon: muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
              on: muted,
              onPressed: guard(
                session.serverMute
                    ? null
                    : () => _run(
                        controller.toggleMute,
                        tr('Could not change the microphone.'),
                      ),
              ),
            )
          else
            VoiceControl(
              key: const ValueKey('stage-control-hand'),
              tooltip: session.handRaised ? tr('Lower hand') : tr('Raise hand'),
              icon: session.handRaised
                  ? Icons.back_hand_rounded
                  : Icons.back_hand_outlined,
              on: session.handRaised,
              activeColor: c.warning,
              onPressed: guard(
                stage == null
                    ? null
                    : () => _run(
                        () =>
                            actions.setHandRaised(context, !session.handRaised),
                        tr('Could not change the stage. Try again.'),
                      ),
              ),
            ),
          if (widget.soundboard case final soundboard?
              when session.stageSpeaker)
            VoiceControl(
              key: const ValueKey('voice-control-soundboard'),
              tooltip: tr('Soundboard'),
              icon: Icons.music_note_rounded,
              onPressed: guard(
                () => showSoundboard(
                  context,
                  access: soundboard,
                  channelId: widget.channelId,
                ),
              ),
            ),
          VoiceControl(
            key: const ValueKey('voice-control-deafen'),
            tooltip: voiceDeafenTooltip(session),
            icon: deafened ? Icons.headset_off_rounded : Icons.headset_outlined,
            on: deafened,
            onPressed: guard(
              session.serverDeaf
                  ? null
                  : () =>
                        _run(controller.toggleDeafen, tr('Could not deafen.')),
            ),
          ),
          if (currentUserId != null && session.stageSpeaker)
            VoiceControl(
              key: const ValueKey('stage-control-audience'),
              tooltip: tr('Move to audience'),
              icon: Icons.voice_over_off_outlined,
              onPressed: guard(
                () => _run(
                  () => actions.moveToAudience(context, currentUserId),
                  tr('Could not change the stage. Try again.'),
                ),
              ),
            )
          else if (currentUserId != null && widget.moderator && stage != null)
            VoiceControl(
              key: const ValueKey('stage-control-speak'),
              tooltip: tr('Become a speaker'),
              icon: Icons.record_voice_over_outlined,
              onPressed: guard(
                () => _run(
                  () => actions.invite(context, currentUserId),
                  tr('Could not change the stage. Try again.'),
                ),
              ),
            ),
          ?widget.chat,
        ],
        leaveLabel: tr('Leave'),
        leaveTooltip: tr('Disconnect'),
        onLeave: controller.leave,
      ),
    );
  }
}
