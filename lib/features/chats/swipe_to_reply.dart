import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Swipe a message sideways to reply to it, on touch screens: right for
/// other people's messages, left for the user's own ([towardsStart] false).
/// A reply icon grows in behind the message as it is dragged; past
/// [threshold] it fills in with a tick of haptics, and letting go there
/// starts the reply. The message springs back either way.
///
/// The drag only claims clearly sideways moves in the reply direction, so
/// scrolling the list, horizontal scrollers inside the message (code
/// blocks, galleries), long presses and the iOS back swipe from the screen
/// edge keep working.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    required this.child,
    required this.onReply,
    this.towardsEnd = true,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onReply;

  /// Drag towards the end (right in left-to-right text) to reply; false
  /// drags towards the start, for the user's own messages.
  final bool towardsEnd;
  final bool enabled;

  /// How far the message has to travel to reply.
  static const threshold = 64.0;

  /// How far it can travel at most (with resistance past [threshold]).
  static const maxOffset = 96.0;

  /// Touches this close to the screen's left edge belong to the back swipe.
  static const edgeGuard = 24.0;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  var _armed = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  /// +1 when replying drags right on screen, −1 when it drags left.
  double get _sign {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return (widget.towardsEnd != rtl) ? 1 : -1;
  }

  void _onStart() {
    _offset.stop();
    _armed = _offset.value.abs() >= SwipeToReply.threshold;
  }

  void _onUpdate(double dx) {
    // Distance travelled in the reply direction, with rubber banding past
    // the threshold.
    final raw = math.max(0.0, _offset.value * _sign + dx * _sign);
    final travelled = raw <= SwipeToReply.threshold
        ? raw
        : SwipeToReply.threshold + (raw - SwipeToReply.threshold) * 0.45;
    final clamped = math.min(travelled, SwipeToReply.maxOffset);
    _offset.value = clamped * _sign;
    final armed = clamped >= SwipeToReply.threshold;
    if (armed != _armed) {
      _armed = armed;
      if (armed) {
        WeCordHaptics.selection();
      }
    }
  }

  void _onEnd(double velocity) {
    final reply = _armed;
    _armed = false;
    _springBack(velocity);
    if (reply) {
      widget.onReply();
    }
  }

  void _springBack([double velocity = 0]) {
    if (WeCordMotion.reduceMotion(context)) {
      _offset.value = 0;
      return;
    }
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: 520,
      ratio: 0.86,
    );
    _offset
        .animateWith(
          SpringSimulation(spring, _offset.value, 0, velocity)
            ..tolerance = const Tolerance(distance: 0.5, velocity: 5),
        )
        // Settled within the tolerance: rest exactly in place. (A drag
        // that interrupts the spring cancels it instead.)
        .then((_) {
          if (mounted) {
            _offset.value = 0;
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final c = context.tokens.colors;
    final sign = _sign;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _ReplySwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_ReplySwipeRecognizer>(
              () => _ReplySwipeRecognizer(debugOwner: this),
              (recognizer) {
                recognizer
                  ..direction = sign
                  ..onStart = _onStart
                  ..onUpdate = _onUpdate
                  ..onEnd = _onEnd
                  ..onCancel = _springBack;
              },
            ),
      },
      child: AnimatedBuilder(
        animation: _offset,
        child: widget.child,
        builder: (context, child) {
          final offset = _offset.value;
          final progress = (offset.abs() / SwipeToReply.threshold).clamp(
            0.0,
            1.0,
          );
          final armed = offset.abs() >= SwipeToReply.threshold;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (progress > 0)
                Positioned.fill(
                  child: Align(
                    alignment: sign > 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Opacity(
                        key: const ValueKey('swipe-reply-icon'),
                        opacity: progress,
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * progress,
                          child: AnimatedContainer(
                            duration: WeCordMotion.quick,
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: armed ? c.accent : c.raised,
                            ),
                            child: Icon(
                              Icons.reply_rounded,
                              size: 19,
                              semanticLabel: tr('Reply'),
                              color: armed ? c.onAccent : c.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                key: const ValueKey('swipe-reply-message'),
                offset: Offset(offset, 0),
                child: child,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Claims a touch drag once it moves clearly sideways in [direction]
/// (+1 right, −1 left); gives up on vertical moves, moves the other way and
/// touches at the screen's left edge.
class _ReplySwipeRecognizer extends OneSequenceGestureRecognizer {
  _ReplySwipeRecognizer({super.debugOwner})
    : super(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      );

  double direction = 1;
  VoidCallback? onStart;
  ValueChanged<double>? onUpdate;
  ValueChanged<double>? onEnd;
  VoidCallback? onCancel;

  int? _pointer;
  Offset _travel = Offset.zero;
  var _accepted = false;
  VelocityTracker? _velocity;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (_pointer != null) {
      return false;
    }
    if (event.position.dx < SwipeToReply.edgeGuard) {
      return false;
    }
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _travel = Offset.zero;
    _accepted = false;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    if (event is PointerMoveEvent) {
      _velocity?.addPosition(event.timeStamp, event.position);
      if (_accepted) {
        onUpdate?.call(event.delta.dx);
        return;
      }
      _travel += event.delta;
      final slop = computeHitSlop(event.kind, gestureSettings);
      if (_travel.distance < slop) {
        return;
      }
      final sideways = _travel.dx * direction;
      if (sideways > 0 && sideways.abs() > _travel.dy.abs() * 1.6) {
        _accepted = true;
        resolve(GestureDisposition.accepted);
      } else {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
      }
    } else if (event is PointerUpEvent) {
      if (_accepted) {
        final velocity = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0;
        onEnd?.call(velocity);
      } else {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_accepted) {
        onCancel?.call();
      } else {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _pointer && _accepted) {
      onStart?.call();
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer && _accepted) {
      onCancel?.call();
    }
    _accepted = false;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
    _velocity = null;
  }

  @override
  String get debugDescription => 'reply swipe';
}
