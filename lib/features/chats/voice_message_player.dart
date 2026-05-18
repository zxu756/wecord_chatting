import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/message.dart';

class VoiceMessagePlayer extends ConsumerStatefulWidget {
  const VoiceMessagePlayer({required this.attachment, super.key});

  final VoiceAttachment attachment;

  @override
  ConsumerState<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends ConsumerState<VoiceMessagePlayer> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  var _isPreparing = false;
  var _isPrepared = false;
  var _hasError = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState != ProcessingState.completed) {
        return;
      }
      unawaited(_player.seek(Duration.zero));
      unawaited(_player.pause());
    });
  }

  @override
  void didUpdateWidget(covariant VoiceMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.bucket != widget.attachment.bucket ||
        oldWidget.attachment.path != widget.attachment.path) {
      _isPrepared = false;
      _hasError = false;
      unawaited(_player.stop());
    }
  }

  @override
  void dispose() {
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback(bool isPlaying) async {
    if (_isPreparing || _hasError) {
      return;
    }

    if (isPlaying) {
      await _player.pause();
      return;
    }

    setState(() {
      _isPreparing = true;
    });

    try {
      if (!_isPrepared) {
        final url = await ref
            .read(chatsRepositoryProvider)
            .createVoiceUrl(widget.attachment);
        await _player.setUrl(url);
        _isPrepared = true;
      }
      await _player.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPreparing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      initialData: _player.playerState,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        final tooltip = isPlaying
            ? 'Pause voice message'
            : 'Play voice message';
        final icon = _hasError
            ? Icons.error_outline
            : isPlaying
            ? Icons.pause
            : Icons.play_arrow;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              tooltip: tooltip,
              onPressed: _hasError
                  ? null
                  : () => unawaited(_togglePlayback(isPlaying)),
              icon: _isPreparing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(widget.attachment.durationMs),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

String _formatDuration(int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
