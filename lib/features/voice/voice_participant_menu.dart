import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_menu.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Someone a participant menu is about.
@immutable
class VoiceMenuPerson {
  const VoiceMenuPerson({
    required this.userId,
    required this.name,
    this.isLocal = false,
    this.channelId,
    this.serverMute = false,
    this.serverDeaf = false,
  });

  final String userId;
  final String name;
  final bool isLocal;

  /// The voice channel they are in, for moderation; null in a call.
  final String? channelId;
  final bool serverMute;
  final bool serverDeaf;
}

enum VoiceModerationAction { mute, deafen, move }

/// What the current user may do to people in a circle's voice channels.
@immutable
class VoiceModeration {
  const VoiceModeration({
    required this.circleId,
    required this.allows,
    this.moveTargets = const [],
  });

  /// From the circle's permissions and role hierarchy.
  factory VoiceModeration.forCircle(CircleDetail detail) {
    return VoiceModeration(
      circleId: detail.circle.id,
      allows: (userId, action) =>
          detail.canModerateVoice(userId, switch (action) {
            VoiceModerationAction.mute => CirclePermission.muteMembers,
            VoiceModerationAction.deafen => CirclePermission.deafenMembers,
            VoiceModerationAction.move => CirclePermission.moveMembers,
          }),
      moveTargets: [
        for (final channel in detail.channels)
          if (channel.isVoice &&
              detail.canInChannel(channel, CirclePermission.connectVoice))
            (id: channel.id, name: channel.name),
      ],
    );
  }

  final String circleId;
  final bool Function(String userId, VoiceModerationAction action) allows;

  /// Voice channels people can be moved to.
  final List<({String id, String name})> moveTargets;
}

enum _MenuAction { mute, deafen, disconnect, move }

/// Opens [person]'s menu at [globalPosition] (a sheet on phones): their
/// volume for the current user (not for themselves), and with [moderation]
/// server mute, server deafen, move and disconnect.
Future<void> showVoiceParticipantMenu(
  BuildContext context, {
  required Offset globalPosition,
  required VoiceMenuPerson person,
  VoiceModeration? moderation,
}) async {
  final channelId = person.channelId;
  bool allows(VoiceModerationAction action) =>
      moderation != null &&
      channelId != null &&
      moderation.allows(person.userId, action);
  final moveTargets = <({String id, String name})>[
    for (final target
        in moderation?.moveTargets ?? const <({String id, String name})>[])
      if (target.id != channelId) target,
  ];
  final canMute = allows(VoiceModerationAction.mute);
  final canDeafen = allows(VoiceModerationAction.deafen);
  final canMove = allows(VoiceModerationAction.move);

  final action = await showVoiceMenu<_MenuAction>(
    context,
    position: globalPosition,
    title: person.name,
    leading: PersonAvatar(name: person.name, size: 30),
    items: [
      if (!person.isLocal) ...[
        const VoiceMenuDivider(),
        VoiceMenuCustom(
          (context) => VoiceUserVolumeSlider(userId: person.userId),
        ),
      ],
      if (canMute || canDeafen || canMove) const VoiceMenuDivider(),
      if (canMute)
        VoiceMenuAction(
          key: const ValueKey('voice-menu-server-mute'),
          value: _MenuAction.mute,
          icon: Icons.mic_off_rounded,
          checked: person.serverMute,
          label: tr('Server mute'),
        ),
      if (canDeafen)
        VoiceMenuAction(
          key: const ValueKey('voice-menu-server-deafen'),
          value: _MenuAction.deafen,
          icon: Icons.headset_off_rounded,
          checked: person.serverDeaf,
          label: tr('Server deafen'),
        ),
      if (canMove && moveTargets.isNotEmpty)
        VoiceMenuAction(
          key: const ValueKey('voice-menu-move'),
          value: _MenuAction.move,
          icon: Icons.move_up_rounded,
          label: tr('Move to…'),
        ),
      if (canMove)
        VoiceMenuAction(
          key: const ValueKey('voice-menu-disconnect'),
          value: _MenuAction.disconnect,
          icon: Icons.call_end_rounded,
          destructive: true,
          label: tr('Disconnect'),
        ),
    ],
  );
  if (action == null || moderation == null || channelId == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repository = container.read(voiceRepositoryProvider);
  final circleId = moderation.circleId;
  try {
    String? room = channelId;
    switch (action) {
      case _MenuAction.mute:
        await repository.setServerMute(
          circleId: circleId,
          userId: person.userId,
          muted: !person.serverMute,
        );
      case _MenuAction.deafen:
        await repository.setServerDeaf(
          circleId: circleId,
          userId: person.userId,
          deafened: !person.serverDeaf,
        );
      case _MenuAction.disconnect:
        room =
            await repository.disconnectMember(
              circleId: circleId,
              userId: person.userId,
            ) ??
            channelId;
      case _MenuAction.move:
        final target = await _pickMoveTarget(context, person, moveTargets);
        if (target == null) {
          return;
        }
        room =
            await repository.moveMember(
              circleId: circleId,
              userId: person.userId,
              channelId: target,
            ) ??
            channelId;
    }
    container.invalidate(voiceStatesProvider(circleId));
    // Best effort: the member's own client follows the change too.
    unawaited(
      repository
          .enforceVoiceState(channelId: room, userId: person.userId)
          .catchError((Object _) {}),
    );
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr("Could not change their voice state."))),
    );
  }
}

Future<String?> _pickMoveTarget(
  BuildContext context,
  VoiceMenuPerson person,
  List<({String id, String name})> targets,
) {
  if (!context.mounted) {
    return Future.value();
  }
  return showDialog<String>(
    context: context,
    builder: (context) {
      final c = context.tokens.colors;
      return Dialog(
        key: const ValueKey('voice-move-dialog'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: Text(
                    tr('Move {name} to', {'name': person.name}),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: c.ink,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final target in targets)
                          SettingsRow(
                            key: ValueKey('voice-move-target-${target.id}'),
                            icon: Icons.volume_up_rounded,
                            tone: SettingsTone.success,
                            title: target.name,
                            showChevron: false,
                            onTap: () => Navigator.of(context).pop(target.id),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: WeCordButton(
                    label: tr('Cancel'),
                    variant: WeCordButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Opens the participant menu on right click, and on long press on touch
/// screens.
class VoiceParticipantMenuRegion extends StatelessWidget {
  const VoiceParticipantMenuRegion({
    required this.person,
    required this.child,
    this.moderation,
    super.key,
  });

  final VoiceMenuPerson person;
  final VoiceModeration? moderation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void open(Offset position) => showVoiceParticipantMenu(
      context,
      globalPosition: position,
      person: person,
      moderation: moderation,
    );
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: tr('More options')): () {
          final box = context.findRenderObject()! as RenderBox;
          open(box.localToGlobal(box.size.center(Offset.zero)));
        },
      },
      child: GestureDetector(
        key: ValueKey('voice-participant-menu-region-${person.userId}'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onSecondaryTapUp: (details) => open(details.globalPosition),
        onLongPressStart: (details) => open(details.globalPosition),
        child: child,
      ),
    );
  }
}

/// "User volume" with a 0–200% slider, saved per person on this device.
class VoiceUserVolumeSlider extends ConsumerWidget {
  const VoiceUserVolumeSlider({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final volume = ref.watch(
      voiceSettingsProvider.select((settings) => settings.volumeFor(userId)),
    );
    final percent = (volume * 100).round();
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  volume <= 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  size: 18,
                  color: c.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('User volume'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  key: const ValueKey('voice-user-volume-value'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Slider(
              key: ValueKey('voice-user-volume-$userId'),
              value: volume,
              min: minUserVolume,
              max: maxUserVolume,
              divisions: 40,
              label: '$percent%',
              semanticFormatterCallback: (value) => '${(value * 100).round()}%',
              onChanged: (value) => ref
                  .read(voiceSettingsProvider.notifier)
                  .setUserVolume(userId, value),
            ),
          ],
        ),
      ),
    );
  }
}
