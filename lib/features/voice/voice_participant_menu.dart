import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Someone a participant menu is about.
typedef VoiceMenuPerson = ({String userId, String name, bool isLocal});

/// Opens [person]'s menu at [globalPosition]: their volume for the
/// current user (not for themselves).
Future<void> showVoiceParticipantMenu(
  BuildContext context, {
  required Offset globalPosition,
  required VoiceMenuPerson person,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final items = <PopupMenuEntry<void>>[
    _MenuHeader(person.name),
    if (!person.isLocal) ...[
      const PopupMenuDivider(),
      VoiceVolumeMenuEntry(userId: person.userId),
    ],
  ];
  await showMenu<void>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// Opens the participant menu on right click, and on long press on touch
/// screens.
class VoiceParticipantMenuRegion extends StatelessWidget {
  const VoiceParticipantMenuRegion({
    required this.person,
    required this.child,
    super.key,
  });

  final VoiceMenuPerson person;
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
      ),
      onLongPressStart: (details) => showVoiceParticipantMenu(
        context,
        globalPosition: details.globalPosition,
        person: person,
      ),
      child: child,
    );
  }
}

class _MenuHeader extends PopupMenuEntry<void> {
  const _MenuHeader(this.name);

  final String name;

  @override
  double get height => 36;

  @override
  bool represents(void value) => false;

  @override
  State<_MenuHeader> createState() => _MenuHeaderState();
}

class _MenuHeaderState extends State<_MenuHeader> {
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
class VoiceVolumeMenuEntry extends PopupMenuEntry<void> {
  const VoiceVolumeMenuEntry({required this.userId, super.key});

  final String userId;

  @override
  double get height => 72;

  @override
  bool represents(void value) => false;

  @override
  State<VoiceVolumeMenuEntry> createState() => _VoiceVolumeMenuEntryState();
}

class _VoiceVolumeMenuEntryState extends State<VoiceVolumeMenuEntry> {
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
