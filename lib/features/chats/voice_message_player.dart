import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A voice message: a round play button, a waveform that fills as it
/// plays, and the length. [foregroundColor] is the bubble's text color;
/// [card] puts it on its own rounded card (circle channels).
class VoiceMessagePlayer extends ConsumerStatefulWidget {
  const VoiceMessagePlayer({
    required this.attachment,
    this.foregroundColor,
    this.card = false,
    super.key,
  });

  final VoiceAttachment attachment;
  final Color? foregroundColor;
  final bool card;

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
    final tokens = context.tokens;
    final c = tokens.colors;
    final foreground = widget.foregroundColor ?? c.ink;
    // The button inverts the bubble: ink on light bubbles, light on ink.
    final buttonIcon = foreground == c.ink ? c.onInk : c.ink;

    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      initialData: _player.playerState,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        final tooltip = isPlaying
            ? tr('Pause voice message')
            : tr('Play voice message');
        final icon = _hasError
            ? Icons.error_outline_rounded
            : isPlaying
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded;
        final total = Duration(milliseconds: widget.attachment.durationMs);

        Widget wave(double progress) => _Waveform(
          seed: widget.attachment.path,
          progress: progress,
          played: foreground,
          rest: foreground.withValues(alpha: 0.32),
        );

        final player = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WeCordPressable(
              onPressed: _hasError
                  ? null
                  : () => unawaited(_togglePlayback(isPlaying)),
              tooltip: tooltip,
              semanticLabel: tooltip,
              shape: const CircleBorder(),
              pressedScale: 0.9,
              builder: (context, states) => Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _hasError ? c.danger : foreground,
                  shape: BoxShape.circle,
                ),
                child: _isPreparing
                    ? SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: buttonIcon,
                        ),
                      )
                    : Icon(icon, size: 20, color: buttonIcon),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: isPlaying
                  ? StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, position) {
                        final ms = total.inMilliseconds;
                        final progress = ms <= 0
                            ? 0.0
                            : ((position.data ?? Duration.zero).inMilliseconds /
                                      ms)
                                  .clamp(0.0, 1.0);
                        return wave(progress);
                      },
                    )
                  : wave(0),
            ),
            const SizedBox(width: 10),
            Text(
              _formatDuration(widget.attachment.durationMs),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: foreground.withValues(alpha: 0.7),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
          ],
        );
        if (!widget.card) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: player,
          );
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: player,
        );
      },
    );
  }
}

/// Bars of a voice message, the first [progress] of them [played].
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.seed,
    required this.progress,
    required this.played,
    required this.rest,
  });

  /// Picks the bar heights, so a message always draws the same wave.
  final String seed;
  final double progress;
  final Color played;
  final Color rest;

  static const _maxBars = 22;

  @override
  Widget build(BuildContext context) {
    // As many bars as fit, up to [_maxBars].
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth.isFinite
            ? ((constraints.maxWidth + 2.5) / 5.5).floor()
            : _maxBars;
        return _bars(room.clamp(4, _maxBars));
      },
    );
  }

  Widget _bars(int count) {
    var hash = 17;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final heights = <double>[];
    for (var index = 0; index < count; index++) {
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      // A gentle swell through the middle with some randomness.
      final swell = 1 - ((index - count / 2).abs() / (count / 2)) * 0.5;
      heights.add(6 + (hash % 1000) / 1000 * 18 * swell);
    }
    final playedBars = (progress * count).round();
    return ExcludeSemantics(
      child: SizedBox(
        height: 26,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < count; index++) ...[
              if (index > 0) const SizedBox(width: 2.5),
              Container(
                width: 3,
                height: heights[index],
                decoration: BoxDecoration(
                  color: index < playedBars ? played : rest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
