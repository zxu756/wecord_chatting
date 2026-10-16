import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// Fills for avatars without a picture, picked from the name so a person
/// or circle keeps its color everywhere.
abstract final class WeCordAvatarColors {
  static const all = <Color>[
    Color(0xFFE0795A),
    Color(0xFF8B6BE0),
    Color(0xFF4D8FD6),
    Color(0xFFC98A2B),
    Color(0xFF2E8F69),
    Color(0xFF3E5FC8),
    Color(0xFFB85A8A),
    Color(0xFF2F8C99),
  ];

  static Color forSeed(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return all[hash % all.length];
  }
}

/// The first character of [name] for an avatar: one Chinese character or
/// one uppercase letter.
String avatarInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}

/// A presence dot with a ring cut out of whatever it sits on.
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    required this.color,
    this.size = 12,
    this.ringColor,
    this.ringWidth,
    super.key,
  });

  final Color color;

  /// Outer size, ring included.
  final double size;

  /// The background the dot sits on; the panel color by default.
  final Color? ringColor;
  final double? ringWidth;

  @override
  Widget build(BuildContext context) {
    final ring = ringWidth ?? (size * 0.22).clamp(2.0, 4.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor ?? context.tokens.colors.panel,
          width: ring,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
    );
  }
}

/// A person: always a circle. Shows [image] or [name]'s initial on a
/// color picked from the name, with an optional [presence] dot (or any
/// [badge]) at the bottom right.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    required this.name,
    this.size = 46,
    this.image,
    this.color,
    this.presence,
    this.ringColor,
    this.badge,
    this.semanticLabel,
    this.onImageError,
    super.key,
  });

  final String name;
  final double size;
  final ImageProvider? image;

  /// Fill behind the initial; picked from [name] by default.
  final Color? color;

  /// Presence color (tokens.colors.success / warning / danger / faint).
  final Color? presence;

  /// The color around the presence dot: what the avatar sits on.
  final Color? ringColor;

  /// Replaces the presence dot, e.g. a reply or mention badge.
  final Widget? badge;

  final String? semanticLabel;

  /// Called when [image] fails to load (e.g. to fall back to the initial).
  final ImageErrorListener? onImageError;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? WeCordAvatarColors.forSeed(name);
    Widget circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        image: image == null
            ? null
            : DecorationImage(
                image: image!,
                fit: BoxFit.cover,
                onError: onImageError,
              ),
      ),
      child: image == null
          ? Text(
              avatarInitial(name),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.39,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            )
          : null,
    );

    final corner =
        badge ??
        (presence == null
            ? null
            : PresenceDot(
                color: presence!,
                size: (size * 0.27).clamp(10.0, 22.0),
                ringColor: ringColor,
              ));
    if (corner != null) {
      circle = Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          Positioned(right: -1, bottom: -1, child: corner),
        ],
      );
    }
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: circle),
    );
  }
}

/// A thing (circle, group, app, bot, channel icon): a continuous-corner
/// squircle. Shows [image] or [label]'s initial, or an [icon]; [badge]
/// (e.g. a CountBadge) sits on the top-right corner.
class ThingAvatar extends StatelessWidget {
  const ThingAvatar({
    this.label = '',
    this.size = 46,
    this.image,
    this.icon,
    this.color,
    this.foregroundColor,
    this.radius,
    this.badge,
    this.semanticLabel,
    this.onImageError,
    super.key,
  });

  final String label;
  final double size;
  final ImageProvider? image;

  /// Shown instead of the initial (Home, add, explore).
  final IconData? icon;

  /// Fill; picked from [label] by default.
  final Color? color;
  final Color? foregroundColor;

  /// Corner radius; a third of [size] by default (46 → 15).
  final double? radius;

  final Widget? badge;
  final String? semanticLabel;

  /// Called when [image] fails to load (e.g. to fall back to the initial).
  final ImageErrorListener? onImageError;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? WeCordAvatarColors.forSeed(label);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius ?? size / 3),
    );
    final foreground = foregroundColor ?? Colors.white;
    Widget tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: fill,
        shape: shape,
        image: image == null
            ? null
            : DecorationImage(
                image: image!,
                fit: BoxFit.cover,
                onError: onImageError,
              ),
      ),
      child: image != null
          ? null
          : icon != null
          ? Icon(icon, color: foreground, size: size * 0.44)
          : Text(
              avatarInitial(label),
              style: TextStyle(
                color: foreground,
                fontSize: size * 0.37,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
    );
    if (badge != null) {
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(right: -4, top: -4, child: badge!),
        ],
      );
    }
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: tile),
    );
  }
}

/// Older name for [ThingAvatar].
typedef SquircleAvatar = ThingAvatar;
