import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Motion in WeCord is spring based: things settle rather than stop on a
/// fixed curve. Each [WeCordSpring] turns a spring into a [curve] and the
/// [duration] it takes to settle, for the implicit animations
/// (AnimatedContainer, AnimatedAlign, AnimatedScale…).
///
/// Everything goes still when the platform asks for reduced motion: use
/// [WeCordSpring.durationOf] (or [WeCordMotion.durationOf]) with a context.
abstract final class WeCordMotion {
  /// Hover and press color changes.
  static const quick = Duration(milliseconds: 120);

  /// Toggles, chips, small moves.
  static const base = Duration(milliseconds: 220);

  /// Panels, sheets, page-level moves.
  static const slow = Duration(milliseconds: 320);

  /// For fades and color changes that shouldn't overshoot.
  static const Curve standard = Curves.easeOutCubic;

  /// Presses, switches, segmented thumbs: fast, barely any overshoot.
  static final snappy = WeCordSpring(stiffness: 520, dampingRatio: 0.86);

  /// Sheets, panels, the floating bars: no overshoot.
  static final smooth = WeCordSpring(stiffness: 300, dampingRatio: 1);

  /// Badges popping in, reactions, the long-press menu: a little bounce.
  static final bouncy = WeCordSpring(stiffness: 420, dampingRatio: 0.68);

  /// Whether the platform asks for reduced motion here.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when motion is reduced.
  static Duration durationOf(BuildContext context, Duration duration) =>
      reduceMotion(context) ? Duration.zero : duration;
}

/// A spring (unit mass) as a curve plus its settling time.
class WeCordSpring {
  WeCordSpring({required double stiffness, required double dampingRatio})
    : description = SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: stiffness,
        ratio: dampingRatio,
      ) {
    duration = _settleTime(description);
    curve = SpringCurve(description, duration);
  }

  final SpringDescription description;

  /// How long the spring takes to settle from 0 to 1.
  late final Duration duration;

  /// The spring's position over [duration], as a curve.
  late final Curve curve;

  /// [duration], or zero when the platform asks for reduced motion.
  Duration durationOf(BuildContext context) =>
      WeCordMotion.durationOf(context, duration);

  static Duration _settleTime(SpringDescription spring) {
    final simulation = SpringSimulation(
      spring,
      0,
      1,
      0,
      tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
    );
    var t = 0.0;
    while (t < 2 && !simulation.isDone(t)) {
      t += 0.004;
    }
    return Duration(milliseconds: (t * 1000).round().clamp(80, 2000));
  }
}

/// A [Curve] that follows [spring] from 0 to 1 over [duration].
class SpringCurve extends Curve {
  SpringCurve(this.spring, this.duration)
    : _simulation = SpringSimulation(spring, 0, 1, 0);

  final SpringDescription spring;
  final Duration duration;
  final SpringSimulation _simulation;

  @override
  double transformInternal(double t) => _simulation.x(
    t * duration.inMicroseconds / Duration.microsecondsPerSecond,
  );
}

/// Haptics, by meaning. They do nothing where the device has none.
abstract final class WeCordHaptics {
  /// A switch flipped, a segment or chip picked, a detent reached.
  static void selection() => HapticFeedback.selectionClick();

  /// A long-press menu opening, a message sent.
  static void light() => HapticFeedback.lightImpact();

  /// Push to talk engaged, a call joined.
  static void medium() => HapticFeedback.mediumImpact();

  /// Something destructive confirmed.
  static void heavy() => HapticFeedback.heavyImpact();
}
