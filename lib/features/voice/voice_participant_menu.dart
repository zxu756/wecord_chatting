import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

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

/// Opens [person]'s menu at [globalPosition]: their volume for the
/// current user (not for themselves), and with [moderation] server mute,
/// server deafen, disconnect and move.
Future<void> showVoiceParticipantMenu(
  BuildContext context, {
  required Offset globalPosition,
  required VoiceMenuPerson person,
  VoiceModeration? moderation,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
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

  final items = <PopupMenuEntry<_MenuAction>>[
    _MenuHeader<_MenuAction>(person.name),
    if (!person.isLocal) ...[
      const PopupMenuDivider(),
      VoiceVolumeMenuEntry<_MenuAction>(userId: person.userId),
    ],
    if (canMute || canDeafen || canMove) const PopupMenuDivider(),
    if (canMute)
      CheckedPopupMenuItem(
        key: const ValueKey('voice-menu-server-mute'),
        value: _MenuAction.mute,
        checked: person.serverMute,
        child: Text(tr('Server mute')),
      ),
    if (canDeafen)
      CheckedPopupMenuItem(
        key: const ValueKey('voice-menu-server-deafen'),
        value: _MenuAction.deafen,
        checked: person.serverDeaf,
        child: Text(tr('Server deafen')),
      ),
    if (canMove && moveTargets.isNotEmpty)
      PopupMenuItem(
        key: const ValueKey('voice-menu-move'),
        value: _MenuAction.move,
        child: ListTile(
          leading: const Icon(Icons.move_up),
          title: Text(tr('Move to…')),
        ),
      ),
    if (canMove)
      PopupMenuItem(
        key: const ValueKey('voice-menu-disconnect'),
        value: _MenuAction.disconnect,
        child: ListTile(
          leading: Icon(
            Icons.call_end,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            tr('Disconnect'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
  ];
  final action = await showMenu<_MenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: items,
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
    builder: (context) => SimpleDialog(
      key: const ValueKey('voice-move-dialog'),
      title: Text(tr('Move {name} to', {'name': person.name})),
      children: [
        for (final target in targets)
          SimpleDialogOption(
            key: ValueKey('voice-move-target-${target.id}'),
            onPressed: () => Navigator.of(context).pop(target.id),
            child: Row(
              children: [
                const Icon(Icons.volume_up_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    target.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
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
    return GestureDetector(
      key: ValueKey('voice-participant-menu-region-${person.userId}'),
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (details) => showVoiceParticipantMenu(
        context,
        globalPosition: details.globalPosition,
        person: person,
        moderation: moderation,
      ),
      onLongPressStart: (details) => showVoiceParticipantMenu(
        context,
        globalPosition: details.globalPosition,
        person: person,
        moderation: moderation,
      ),
      child: child,
    );
  }
}

class _MenuHeader<T> extends PopupMenuEntry<T> {
  const _MenuHeader(this.name);

  final String name;

  @override
  double get height => 36;

  @override
  bool represents(T? value) => false;

  @override
  State<_MenuHeader<T>> createState() => _MenuHeaderState<T>();
}

class _MenuHeaderState<T> extends State<_MenuHeader<T>> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        widget.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
    );
  }
}

/// "User volume" with a 0–200% slider, saved per person on this device.
class VoiceVolumeMenuEntry<T> extends PopupMenuEntry<T> {
  const VoiceVolumeMenuEntry({required this.userId, super.key});

  final String userId;

  @override
  double get height => 72;

  @override
  bool represents(T? value) => false;

  @override
  State<VoiceVolumeMenuEntry<T>> createState() =>
      _VoiceVolumeMenuEntryState<T>();
}

class _VoiceVolumeMenuEntryState<T> extends State<VoiceVolumeMenuEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final volume = ref.watch(
          voiceSettingsProvider.select(
            (settings) => settings.volumeFor(widget.userId),
          ),
        );
        final percent = (volume * 100).round();
        final theme = Theme.of(context);
        return SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('User volume'),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Text(
                      '$percent%',
                      key: const ValueKey('voice-user-volume-value'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: ValueKey('voice-user-volume-${widget.userId}'),
                  value: volume,
                  min: minUserVolume,
                  max: maxUserVolume,
                  divisions: 40,
                  label: '$percent%',
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()}%',
                  onChanged: (value) => ref
                      .read(voiceSettingsProvider.notifier)
                      .setUserVolume(widget.userId, value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
