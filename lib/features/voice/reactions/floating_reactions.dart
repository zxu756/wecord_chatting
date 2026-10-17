import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/reactions/reaction_message.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How long a reaction floats; with reduced motion it just shows (and
/// fades) for [reducedMotionDuration] where it appeared.
const reactionFloatDuration = Duration(milliseconds: 2400);
const reducedMotionDuration = Duration(milliseconds: 1800);

/// Most reactions shown on one tile at a time; more are dropped.
const maxFloatingReactions = 8;

/// Floats the emoji [userId] sends over [child] (their tile): up from the
/// bottom, drifting a little, fading out. With reduced motion the emoji
/// appears where it would start, without moving, and fades. Reactions
/// aren't read out one by one; the sender is announced to screen readers.
class FloatingReactions extends ConsumerStatefulWidget {
  const FloatingReactions({
    required this.userId,
    required this.name,
    required this.child,
    super.key,
  });

  final String userId;

  /// Who this is, for the screen reader announcement.
  final String name;
  final Widget child;

  @override
  ConsumerState<FloatingReactions> createState() => _FloatingReactionsState();
}

class _Floating {
  _Floating(this.id, this.emoji, this.lane);

  final int id;
  final String emoji;

  /// Where across the tile it rises, -1 (left) to 1 (right).
  final double lane;
}

class _FloatingReactionsState extends ConsumerState<FloatingReactions> {
  final _floating = <_Floating>[];
  StreamSubscription<VoiceReaction>? _subscription;
  var _next = 0;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _subscription = ref
        .read(voiceSessionProvider.notifier)
        .reactions
        .listen(_onReaction);
  }

  void _onReaction(VoiceReaction reaction) {
    if (reaction.userId != widget.userId || !mounted) {
      return;
    }
    if (_floating.length >= maxFloatingReactions) {
      return;
    }
    final id = _next++;
    setState(() {
      _floating.add(
        _Floating(id, reaction.emoji, _random.nextDouble() * 1.6 - 0.8),
      );
    });
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        tr('{name} reacted {emoji}', {
          'name': widget.name,
          'emoji': reaction.emoji,
        }),
        Directionality.of(context),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_floating.isNotEmpty)
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final floating in _floating)
                        _FloatingEmoji(
                          key: ValueKey('voice-reaction-${floating.id}'),
                          emoji: floating.emoji,
                          lane: floating.lane,
                          area: constraints.biggest,
                          onDone: () {
                            if (mounted) {
                              setState(() => _floating.remove(floating));
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({
    required this.emoji,
    required this.lane,
    required this.area,
    required this.onDone,
    super.key,
  });

  final String emoji;
  final double lane;
  final Size area;
  final VoidCallback onDone;

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final reduced = WeCordMotion.reduceMotion(context);
    _controller =
        AnimationController(
          vsync: this,
          duration: reduced ? reducedMotionDuration : reactionFloatDuration,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.onDone();
          }
        });
    unawaited(_controller!.forward());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    final reduced = WeCordMotion.reduceMotion(context);
    final size = (widget.area.shortestSide * 0.26).clamp(22.0, 44.0);
    final rise = widget.area.height * 0.7;
    final sway = widget.area.width * 0.06;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final opacity = reduced
            ? (t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25)
            : (t < 0.65 ? 1.0 : 1 - (t - 0.65) / 0.35);
        // Pops in with a little overshoot, then settles.
        final scale = reduced
            ? 1.0
            : t < 0.14
            ? Curves.easeOutBack.transform(t / 0.14)
            : 1.0;
        final dy = reduced ? 0.0 : -rise * Curves.easeOutCubic.transform(t);
        final dx = reduced ? 0.0 : math.sin(t * math.pi * 2.4) * sway;
        return Align(
          alignment: Alignment(widget.lane * 0.7, reduced ? 0.15 : 0.7),
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      },
      child: Text(widget.emoji, style: TextStyle(fontSize: size, height: 1)),
    );
  }
}
