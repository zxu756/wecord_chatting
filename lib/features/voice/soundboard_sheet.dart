import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/soundboard_player.dart';
import 'package:wecord/features/voice/soundboard_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_sound.dart';

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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SoundboardPanel(
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('soundboard-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
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
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          key: const ValueKey('soundboard-menu-preview'),
          value: 'preview',
          child: ListTile(
            leading: const Icon(Icons.headphones_outlined),
            title: Text(tr('Preview')),
          ),
        ),
        if (widget.canManage)
          PopupMenuItem(
            key: const ValueKey('soundboard-menu-delete'),
            value: 'delete',
            child: ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                tr('Delete'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
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
    final theme = Theme.of(context);
    final sounds = ref.watch(circleSoundsProvider(widget.circleId));
    final session = ref.watch(voiceSessionProvider);
    final canPlay = canPlaySoundsIn(session, widget.channelId);
    final list = sounds.valueOrNull ?? const <CircleSound>[];
    final full = list.length >= maxCircleSounds;

    return SafeArea(
      child: Padding(
        key: const ValueKey('soundboard-panel'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Soundboard'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (widget.canManage)
                  TextButton.icon(
                    key: const ValueKey('soundboard-add'),
                    onPressed: _busy || full ? null : _add,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(tr('Add sound')),
                  ),
              ],
            ),
            if (!canPlay)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr("You can't play sounds here right now."),
                  key: const ValueKey('soundboard-cannot-play'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                error: (error, stackTrace) => Text(
                  tr('Could not load the soundboard.'),
                  style: theme.textTheme.bodyMedium,
                ),
                data: (sounds) => sounds.isEmpty
                    ? Text(
                        widget.canManage
                            ? tr(
                                'No sounds yet. Add short clips (MP3, Ogg or '
                                'WAV, up to 5 seconds) for everyone to play.',
                              )
                            : tr('No sounds yet.'),
                        key: const ValueKey('soundboard-empty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final sound in sounds)
                              GestureDetector(
                                onLongPressStart: (details) =>
                                    _openMenu(sound, details.globalPosition),
                                onSecondaryTapUp: (details) =>
                                    _openMenu(sound, details.globalPosition),
                                child: ActionChip(
                                  key: ValueKey('soundboard-sound-${sound.id}'),
                                  avatar: Text(sound.emoji ?? '🔊'),
                                  label: Text(sound.name),
                                  onPressed: canPlay && !_coolingDown
                                      ? () => _play(sound)
                                      : null,
                                ),
                              ),
                          ],
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
    return AlertDialog(
      key: const ValueKey('soundboard-add-dialog'),
      scrollable: true,
      title: Text(tr('Add sound')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('soundboard-name-field'),
            controller: _name,
            autofocus: true,
            maxLength: maxCircleSoundNameLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Name'),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('soundboard-emoji-field'),
            controller: _emoji,
            maxLength: 16,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Emoji (optional)'),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            key: const ValueKey('soundboard-upload'),
            onPressed: isValidSoundName(_name.text) ? _submit : null,
            child: Text(tr('Upload')),
          ),
        ),
      ],
    );
  }
}
