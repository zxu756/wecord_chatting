import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_polish/chat_polish_settings.dart';
import 'package:wecord/features/chats/chat_polish/voice_playback.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_view.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A voice message: a round play button, a waveform that fills as it
/// plays, and the length. [foregroundColor] is the bubble's text color;
/// [card] puts it on its own rounded card (circle channels). With a
/// [messageId] it also has a Transcribe button, and the transcript shows
/// under the waveform.
class VoiceMessagePlayer extends ConsumerStatefulWidget {
  const VoiceMessagePlayer({
    required this.attachment,
    this.foregroundColor,
    this.card = false,
    this.messageId,
    this.conversationId,
    this.autoplayNext = false,
    super.key,
  });

  final VoiceAttachment attachment;
  final Color? foregroundColor;
  final bool card;

  /// The message this voice message belongs to; null (a message still
  /// sending) leaves out transcribing.
  final String? messageId;
  final String? conversationId;

  /// When it ends, the next voice message in the chat that has not been
  /// played is asked to start (A10). Only chats do this.
  final bool autoplayNext;

  /// How many audio players bubbles have made, for tests: none until a
  /// voice message is played.
  @visibleForTesting
  static var debugPlayersCreated = 0;

  @override
  ConsumerState<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends ConsumerState<VoiceMessagePlayer> {
  /// Made on the first play: a chat can hold hundreds of voice messages and
  /// each player is a native audio object, but only the ones that are played
  /// need one. The waveform and length draw without it.
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  var _isPreparing = false;
  var _isPrepared = false;
  var _hasError = false;

  /// Who this player is to the others: the message, or the file of a voice
  /// message that has no id yet.
  String get _key => widget.messageId ?? widget.attachment.path;

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) {
      return existing;
    }
    final player = AudioPlayer();
    VoiceMessagePlayer.debugPlayersCreated++;
    _player = player;
    _playerStateSubscription = player.playerStateStream.listen((state) {
      if (state.processingState != ProcessingState.completed) {
        return;
      }
      unawaited(player.seek(Duration.zero));
      unawaited(player.pause());
      _finished();
    });
    return player;
  }

  /// Played to the end: heard, and the next one may follow.
  void _finished() {
    if (!mounted) {
      return;
    }
    final playback = ref.read(voicePlaybackProvider.notifier);
    playback.finished(_key);
    final messageId = widget.messageId;
    final conversationId = widget.conversationId;
    if (!widget.autoplayNext ||
        messageId == null ||
        conversationId == null ||
        !ref.read(voiceAutoplayProvider)) {
      return;
    }
    final thread = chatThreadProvider(conversationId);
    if (!ref.exists(thread)) {
      return;
    }
    final next = nextUnheardVoiceMessageId(
      ref.read(thread).value?.messages ?? const [],
      messageId,
      ref.read(voicePlaybackProvider).heard,
      currentUserId: ref.read(authRepositoryProvider).currentUser?.id,
    );
    if (next != null) {
      playback.requestPlay(next);
    }
  }

  /// Another message started: this one stops.
  void _otherStarted(String? playingId) {
    final player = _player;
    if (player == null || playingId == _key || !player.playing) {
      return;
    }
    ref.read(voicePlaybackProvider.notifier).paused(_key, player.position);
    unawaited(player.pause());
  }

  /// The message before this one ended and asks this one to go on.
  void _requested(VoiceAutoplayRequest? request) {
    if (request == null || request.messageId != widget.messageId) {
      return;
    }
    ref.read(voicePlaybackProvider.notifier).clearRequest();
    if (_player?.playing ?? false) {
      return;
    }
    unawaited(_togglePlayback(false));
  }

  @override
  void didUpdateWidget(covariant VoiceMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.bucket != widget.attachment.bucket ||
        oldWidget.attachment.path != widget.attachment.path) {
      _isPrepared = false;
      _hasError = false;
      unawaited(_player?.stop());
    }
  }

  @override
  void dispose() {
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback(bool isPlaying) async {
    if (_isPreparing || _hasError) {
      return;
    }

    final playback = ref.read(voicePlaybackProvider.notifier);
    if (isPlaying) {
      final player = _player;
      if (player != null) {
        playback.paused(_key, player.position);
      }
      await player?.pause();
      return;
    }

    setState(() {
      _isPreparing = true;
    });

    try {
      final player = _ensurePlayer();
      if (!_isPrepared) {
        final url = await ref
            .read(chatsRepositoryProvider)
            .createVoiceUrl(widget.attachment);
        await player.setUrl(url);
        _isPrepared = true;
        // Where it was left, if this message was heard in part before.
        final left = ref.read(voicePlaybackProvider).positions[_key];
        if (left != null) {
          await player.seek(left);
        }
      }
      await player.setSpeed(ref.read(voicePlaybackSpeedProvider));
      playback.started(_key);
      await player.play();
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
    ref.listen(
      voicePlaybackProvider.select((state) => state.playingId),
      (previous, next) => _otherStarted(next),
    );
    ref.listen(
      voicePlaybackProvider.select((state) => state.request),
      (previous, next) => _requested(next),
    );
    ref.listen(
      voicePlaybackSpeedProvider,
      (previous, speed) =>
          unawaited(_player?.setSpeed(speed) ?? Future.value()),
    );
    final speed = ref.watch(voicePlaybackSpeedProvider);
    // Left in the middle: the wave shows where.
    final hasLeftOff = ref.watch(
      voicePlaybackProvider.select((state) => state.positions[_key] != null),
    );
    final messageId = widget.messageId;
    final request = messageId == null
        ? null
        : TranscribeRequest.forMessage(
            messageId: messageId,
            conversationId: widget.conversationId,
            attachment: widget.attachment,
          );

    return StreamBuilder<PlayerState>(
      stream: _player?.playerStateStream,
      initialData: _player?.playerState ?? _idle,
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
              child: isPlaying || hasLeftOff
                  ? StreamBuilder<Duration>(
                      stream: _player?.positionStream,
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
            if (isPlaying || speed != 1) ...[
              const SizedBox(width: 6),
              _SpeedChip(
                speed: speed,
                color: foreground,
                onPressed: () =>
                    ref.read(voicePlaybackSpeedProvider.notifier).cycle(),
              ),
            ],
            if (request != null) ...[
              const SizedBox(width: 2),
              TranscribeButton(request: request, color: foreground),
            ] else
              const SizedBox(width: 4),
          ],
        );
        final Widget content = request == null
            ? player
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  player,
                  TranscriptView(request: request, color: foreground),
                ],
              );
        if (!widget.card) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: content,
          );
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: content,
        );
      },
    );
  }
}

/// What a bubble shows before its player exists.
final _idle = PlayerState(false, ProcessingState.idle);

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

/// The speed button of a playing voice message: "1×", "1.5×", "2×".
class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.speed,
    required this.color,
    required this.onPressed,
  });

  final double speed;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = voiceSpeedLabel(speed);
    return WeCordPressable(
      key: const ValueKey('voice-speed-chip'),
      onPressed: onPressed,
      semanticLabel: tr('Playback speed {speed}', {'speed': label}),
      tooltip: tr('Playback speed'),
      shape: const StadiumBorder(),
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WeCordRadii.pill),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
