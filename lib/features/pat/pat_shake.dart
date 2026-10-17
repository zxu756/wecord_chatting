import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/shared/ui/motion.dart';

/// One shake asked for: whose avatar, and a counter so the same person can
/// be shaken again.
@immutable
class PatShakeEvent {
  const PatShakeEvent(this.userId, this.serial);

  final String userId;
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is PatShakeEvent &&
      other.userId == userId &&
      other.serial == serial;

  @override
  int get hashCode => Object.hash(userId, serial);
}

/// Asks the avatars of one chat to shake. The patter's own tap does it at
/// once; the receiver's chat does it when a fresh pat for them arrives.
class PatShakeNotifier extends Notifier<PatShakeEvent?> {
  PatShakeNotifier(this.conversationId);

  final String conversationId;

  @override
  PatShakeEvent? build() => null;

  void shake(String userId) {
    state = PatShakeEvent(userId, (state?.serial ?? 0) + 1);
  }
}

final patShakeProvider = NotifierProvider.autoDispose
    .family<PatShakeNotifier, PatShakeEvent?, String>(PatShakeNotifier.new);

/// A gentle shake of [child] each time [trigger] changes: a quick sway that
/// settles in about half a second. Still under reduced motion.
class PatShake extends StatefulWidget {
  const PatShake({required this.trigger, required this.child, super.key});

  final int trigger;
  final Widget child;

  @override
  State<PatShake> createState() => _PatShakeState();
}

class _PatShakeState extends State<PatShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  @override
  void didUpdateWidget(PatShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger &&
        !WeCordMotion.reduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Three swings that die away.
        final sway = math.sin(t * math.pi * 6) * (1 - t);
        return Transform.translate(
          offset: Offset(sway * 3.5, 0),
          child: Transform.rotate(angle: sway * 0.07, child: child),
        );
      },
    );
  }
}
