import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';

/// What a [CountBadge] counts.
enum BadgeTone {
  /// Mentions, notifications, friend requests: red.
  alert,

  /// Unread messages in a list row: the accent.
  unread,

  /// Muted counts: a quiet fill.
  quiet,
}

/// A pill with a count (99+ above 99), or a dot when [count] is null.
/// [ringColor] cuts it out of what it overlaps (the rail, an avatar).
/// Pops in with a little bounce.
class CountBadge extends StatelessWidget {
  const CountBadge({
    this.count,
    this.tone = BadgeTone.alert,
    this.ringColor,
    this.size = 20,
    super.key,
  });

  /// A plain dot.
  const CountBadge.dot({
    this.tone = BadgeTone.alert,
    this.ringColor,
    this.size = 10,
    super.key,
  }) : count = null;

  final int? count;
  final BadgeTone tone;
  final Color? ringColor;

  /// Height of the pill (or the dot's diameter).
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final (fill, text) = switch (tone) {
      BadgeTone.alert => (c.danger, c.onDanger),
      BadgeTone.unread => (c.accent, c.onAccent),
      BadgeTone.quiet => (c.raisedStrong, c.muted),
    };
    final count = this.count;
    final ring = ringColor == null ? 0.0 : (size * 0.13).clamp(2.0, 3.0);
    final label = count == null ? null : (count > 99 ? '99+' : '$count');
    final spring = WeCordMotion.bouncy;

    final badge = Container(
      height: size + ring * 2,
      constraints: BoxConstraints(minWidth: size + ring * 2),
      padding: EdgeInsets.symmetric(
        horizontal: label == null ? 0 : size * 0.28 + ring,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size),
        border: ringColor == null
            ? null
            : Border.all(
                color: ringColor!,
                width: ring,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
      ),
      child: label == null
          ? null
          : Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: text,
                fontSize: size * 0.55,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
    );

    return Semantics(
      label: label,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: spring.durationOf(context),
        curve: spring.curve,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: ExcludeSemantics(child: badge),
      ),
    );
  }
}
