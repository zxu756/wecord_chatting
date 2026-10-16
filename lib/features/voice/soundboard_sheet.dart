import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/soundboard_player.dart';
import 'package:wecord/features/voice/soundboard_repository.dart';
import 'package:wecord/features/voice/voice_menu.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_sound.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Who may do what with a circle's soundboard from a voice channel.
typedef SoundboardAccess = ({String circleId, bool canManage});

/// Whether [session] may play sounds into [channelId]: connected there,
/// not server muted or deafened, and speaking if it is a stage.
bool canPlaySoundsIn(VoiceSession? session, String? channelId) {
  return session != null &&
      channelId != null &&
      session.channelId == channelId &&
      session.isConnected &&
      !session.serverMute &&
      !session.serverDeaf &&
      !session.stageListener;
}

/// Opens the soundboard of [access]'s circle for [channelId].
Future<void> showSoundboard(
  BuildContext context, {
  required SoundboardAccess access,
  required String channelId,
}) {
  return showWeCordSheet<void>(
    context,
    builder: (context, _) => SoundboardPanel(
      circleId: access.circleId,
      channelId: channelId,
      canManage: access.canManage,
    ),
  );
}

/// The circle's sounds: tapping one plays it for everyone in the channel.
/// Long-press (or right-click) previews it for yourself, or deletes it
/// for members who manage expressions; they can add sounds too.
class SoundboardPanel extends ConsumerStatefulWidget {
  const SoundboardPanel({
    required this.circleId,
    required this.channelId,
    required this.canManage,
    super.key,
  });

  final String circleId;
  final String channelId;
  final bool canManage;

  @override
  ConsumerState<SoundboardPanel> createState() => _SoundboardPanelState();
}

class _SoundboardPanelState extends ConsumerState<SoundboardPanel> {
  Timer? _cooldown;
  var _busy = false;

  bool get _coolingDown => _cooldown?.isActive ?? false;

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _cooldown = Timer(soundboardCooldown, () {
      if (mounted) {
        setState(() {});
      }
    });
    setState(() {});
  }

  Future<void> _play(CircleSound sound) async {
    if (_coolingDown) {
      return;
    }
    _startCooldown();
    try {
      await ref
          .read(soundboardRepositoryProvider)
          .play(channelId: widget.channelId, soundId: sound.id);
    } on SoundboardException catch (error) {
      _show(error.message);
    } catch (_) {
      _show(tr('Could not play the sound. Try again.'));
    }
  }

  Future<void> _preview(CircleSound sound) async {
    try {
      final url = await ref
          .read(soundboardRepositoryProvider)
          .createSoundUrl(sound.storagePath);
      final volume = ref.read(voiceSettingsProvider).soundboardVolume;
      await ref
          .read(soundboardPlayerProvider)
          .play(url, volume: volume <= 0 ? defaultSoundboardVolume : volume);
    } catch (_) {
      _show(tr('Could not play the sound. Try again.'));
    }
  }

  Future<void> _delete(CircleSound sound) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete sound')),
        content: Text(
          tr('Delete {name} from the soundboard?', {'name': sound.name}),
        ),
        actions: [
          WeCordButton(
            label: tr('Cancel'),
            variant: WeCordButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WeCordButton(
            key: const ValueKey('soundboard-delete-confirm'),
            label: tr('Delete'),
            variant: WeCordButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(soundboardRepositoryProvider).deleteSound(sound.id);
      ref.invalidate(circleSoundsProvider(widget.circleId));
    } catch (_) {
      _show(tr('Could not delete the sound. Try again.'));
    }
  }

  Future<void> _add() async {
    if (_busy) {
      return;
    }
    final PickedSoundFile? file;
    try {
      file = await ref.read(soundFilePickerProvider)();
    } on SoundboardException catch (error) {
      _show(error.message);
      return;
    } catch (_) {
      _show(tr('Could not open the file.'));
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    final details = await showDialog<({String name, String? emoji})>(
      context: context,
      builder: (context) => _AddSoundDialog(fileName: file!.name),
    );
    if (details == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(soundboardRepositoryProvider)
          .addSound(
            circleId: widget.circleId,
            name: details.name,
            emoji: details.emoji,
            bytes: file.bytes,
          );
      ref.invalidate(circleSoundsProvider(widget.circleId));
    } on SoundboardException catch (error) {
      _show(error.message);
    } catch (_) {
      _show(tr('Could not add the sound. Try again.'));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openMenu(CircleSound sound, Offset position) async {
    final choice = await showVoiceMenu<String>(
      context,
      position: position,
      title: sound.name,
      leading: Text(sound.emoji ?? '🔊', style: const TextStyle(fontSize: 22)),
      items: [
        VoiceMenuAction(
          key: const ValueKey('soundboard-menu-preview'),
          value: 'preview',
          icon: Icons.headphones_outlined,
          label: tr('Preview'),
        ),
        if (widget.canManage)
          VoiceMenuAction(
            key: const ValueKey('soundboard-menu-delete'),
            value: 'delete',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            label: tr('Delete'),
          ),
      ],
    );
    switch (choice) {
      case 'preview':
        await _preview(sound);
      case 'delete':
        await _delete(sound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final sounds = ref.watch(circleSoundsProvider(widget.circleId));
    final session = ref.watch(voiceSessionProvider);
    final canPlay = canPlaySoundsIn(session, widget.channelId);
    final list = sounds.value ?? const <CircleSound>[];
    final full = list.length >= maxCircleSounds;

    return SafeArea(
      top: false,
      child: Padding(
        key: const ValueKey('soundboard-panel'),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        tr('Soundboard'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  if (widget.canManage)
                    WeCordButton(
                      key: const ValueKey('soundboard-add'),
                      label: tr('Add sound'),
                      icon: Icons.add_rounded,
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.small,
                      loading: _busy,
                      onPressed: _busy || full ? null : _add,
                    ),
                ],
              ),
            ),
            if (!canPlay)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text(
                  tr("You can't play sounds here right now."),
                  key: const ValueKey('soundboard-cannot-play'),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
            const SizedBox(height: 12),
            Flexible(
              child: sounds.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, stackTrace) => Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    tr('Could not load the soundboard.'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                ),
                data: (sounds) => sounds.isEmpty
                    ? Container(
                        key: const ValueKey('soundboard-empty'),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: c.well,
                          borderRadius: BorderRadius.circular(WeCordRadii.lg),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.music_note_rounded,
                              size: 28,
                              color: c.subtle,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.canManage
                                  ? tr(
                                      'No sounds yet. Add short clips (MP3, '
                                      'Ogg or WAV, up to 5 seconds) for '
                                      'everyone to play.',
                                    )
                                  : tr('No sounds yet.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: c.muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = 8.0;
                            final columns = (constraints.maxWidth / 96)
                                .floor()
                                .clamp(3, 8);
                            final width =
                                (constraints.maxWidth - gap * (columns - 1)) /
                                columns;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final sound in sounds)
                                  SizedBox(
                                    width: width,
                                    child: SoundboardTile(
                                      key: ValueKey(
                                        'soundboard-sound-${sound.id}',
                                      ),
                                      sound: sound,
                                      onPressed: canPlay && !_coolingDown
                                          ? () => _play(sound)
                                          : null,
                                      onMenu: (position) =>
                                          _openMenu(sound, position),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sound on the soundboard: its emoji over its name in a rounded tile.
/// Tapping plays it ([onPressed]; null while it can't play); long-press or
/// right-click opens [onMenu].
class SoundboardTile extends StatelessWidget {
  const SoundboardTile({
    required this.sound,
    required this.onPressed,
    required this.onMenu,
    super.key,
  });

  final CircleSound sound;
  final VoidCallback? onPressed;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return GestureDetector(
      onLongPressStart: (details) => onMenu(details.globalPosition),
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: WeCordPressable(
        onPressed: onPressed,
        semanticLabel: sound.name,
        excludeSemantics: true,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg + 2),
        ),
        builder: (context, states) {
          final hovered =
              onPressed != null &&
              (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed));
          return AnimatedOpacity(
            opacity: onPressed == null ? 0.45 : 1,
            duration: WeCordMotion.quick,
            child: AnimatedContainer(
              duration: WeCordMotion.quick,
              height: 84,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: ShapeDecoration(
                color: hovered
                    ? Color.alphaBlend(c.ink.withValues(alpha: 0.05), c.raised)
                    : c.raised,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg + 2),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    sound.emoji ?? '🔊',
                    style: const TextStyle(fontSize: 28, height: 1.1),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sound.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AddSoundDialog extends StatefulWidget {
  const _AddSoundDialog({required this.fileName});

  final String fileName;

  @override
  State<_AddSoundDialog> createState() => _AddSoundDialogState();
}

class _AddSoundDialogState extends State<_AddSoundDialog> {
  late final _name = TextEditingController(text: _suggestedName());
  final _emoji = TextEditingController();

  String _suggestedName() {
    final dot = widget.fileName.lastIndexOf('.');
    final base = (dot > 0 ? widget.fileName.substring(0, dot) : widget.fileName)
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    return base.length > maxCircleSoundNameLength
        ? base.substring(0, maxCircleSoundNameLength).trim()
        : base;
  }

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    super.dispose();
  }

  void _submit() {
    if (!isValidSoundName(_name.text)) {
      return;
    }
    final emoji = _emoji.text.trim();
    Navigator.of(
      context,
    ).pop((name: _name.text.trim(), emoji: emoji.isEmpty ? null : emoji));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return AlertDialog(
      key: const ValueKey('soundboard-add-dialog'),
      scrollable: true,
      title: Text(tr('Add sound')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.audio_file_outlined, size: 20, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            WeCordTextField(
              fieldKey: const ValueKey('soundboard-name-field'),
              controller: _name,
              autofocus: true,
              maxLength: maxCircleSoundNameLength,
              label: tr('Name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            WeCordTextField(
              fieldKey: const ValueKey('soundboard-emoji-field'),
              controller: _emoji,
              maxLength: 16,
              label: tr('Emoji (optional)'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => WeCordButton(
            key: const ValueKey('soundboard-upload'),
            label: tr('Upload'),
            onPressed: isValidSoundName(_name.text) ? _submit : null,
          ),
        ),
      ],
    );
  }
}
