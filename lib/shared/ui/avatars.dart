import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';
import 'package:wecord/shared/ui/display_size_image.dart';
import 'package:wecord/shared/ui/motion_safe_image.dart';

/// Avatars at least this big get a play button over an animated picture
/// held on its first frame under reduced motion; smaller ones just stay
/// still (the button would cover the avatar).
const double avatarPlayButtonMinSize = 72;

/// An animated avatar picture (GIF) held still on its first frame, when the
/// platform asks for reduced motion; null when [image] can be drawn as it
/// is.
Widget? heldAvatarPicture(
  BuildContext context, {
  required ImageProvider? image,
  required double size,
  ImageErrorListener? onError,
}) {
  if (image == null ||
      !WeCordMotion.reduceMotion(context) ||
      !imageProviderAnimates(image)) {
    return null;
  }
  return MotionSafeImage(
    image: image,
    width: size,
    height: size,
    fit: BoxFit.cover,
    excludeFromSemantics: true,
    playButton: size >= avatarPlayButtonMinSize,
    errorBuilder: onError == null
        ? null
        : (context, error, stack) {
            onError(error, stack);
            return SizedBox.square(dimension: size);
          },
  );
}

/// Fills for avatars without a picture, picked from the name so a person
/// or circle keeps its color everywhere.
abstract final class WeCordAvatarColors {
  /// Mid tones, each dark enough for the white initial on top to clear
  /// 4.5:1 (the mockups' colors, deepened until they did).
  static const all = <Color>[
    Color(0xFFCC4D26),
    Color(0xFF825FDE),
    Color(0xFF2E78C8),
    Color(0xFF9E6D22),
    Color(0xFF2B8562),
    Color(0xFF3E5FC8),
    Color(0xFFB65586),
    Color(0xFF2B818D),
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

/// What a presence dot looks like besides its color, so that status doesn't
/// rest on color alone: a plain dot for online, a crescent for idle, a bar
/// for do not disturb and a hollow ring for offline.
enum PresenceShape { solid, crescent, bar, ring }

/// A presence dot with a ring cut out of whatever it sits on. With a
/// [shape] other than [PresenceShape.solid] a notch is cut out of the dot
/// too, in the ring's color.
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    required this.color,
    this.size = 12,
    this.ringColor,
    this.ringWidth,
    this.semanticLabel,
    this.shape = PresenceShape.solid,
    super.key,
  });

  final Color color;

  /// The notch that tells the status apart without its color.
  final PresenceShape shape;

  /// What the dot says to a screen reader ("Online"); without one the dot
  /// is skipped.
  final String? semanticLabel;

  /// Outer size, ring included.
  final double size;

  /// The background the dot sits on; the panel color by default.
  final Color? ringColor;
  final double? ringWidth;

  @override
  Widget build(BuildContext context) {
    final ring = ringWidth ?? (size * 0.22).clamp(2.0, 4.0);
    final ringTone = ringColor ?? context.tokens.colors.panel;
    final inner = size - 2 * ring;
    Widget notch(double diameter) => Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: ringTone, shape: BoxShape.circle),
    );
    final Widget? cutout = switch (shape) {
      PresenceShape.solid => null,
      // A bite out of the top left makes a crescent.
      PresenceShape.crescent => Align(
        alignment: Alignment.topLeft,
        child: notch(inner * 0.6),
      ),
      PresenceShape.bar => Center(
        child: Container(
          width: inner * 0.7,
          height: (inner * 0.25).clamp(1.5, 4),
          decoration: BoxDecoration(
            color: ringTone,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      PresenceShape.ring => Center(child: notch(inner * 0.45)),
    };
    final dot = Container(
      width: size,
      height: size,
      clipBehavior: cutout == null ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: ringTone,
          width: ring,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: cutout,
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: dot)
        : Semantics(label: semanticLabel, excludeSemantics: true, child: dot);
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
    this.presenceLabel,
    this.presenceShape = PresenceShape.solid,
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

  /// The notch in the presence dot that tells the status without its color.
  final PresenceShape presenceShape;

  /// The color around the presence dot: what the avatar sits on.
  final Color? ringColor;

  /// Replaces the presence dot, e.g. a reply or mention badge.
  final Widget? badge;

  final String? semanticLabel;

  /// The presence dot in words ("Online", "Idle"), read after
  /// [semanticLabel]; a dot without one is only a color.
  final String? presenceLabel;

  /// Called when [image] fails to load (e.g. to fall back to the initial).
  final ImageErrorListener? onImageError;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? WeCordAvatarColors.forSeed(name);
    final image = this.image == null
        ? null
        : avatarImageFor(
            this.image!,
            size: size,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
    final held = heldAvatarPicture(
      context,
      image: image,
      size: size,
      onError: onImageError,
    );
    Widget circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: held == null ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        image: image == null || held != null
            ? null
            : DecorationImage(
                image: image,
                fit: BoxFit.cover,
                onError: onImageError,
              ),
      ),
      child:
          held ??
          (image == null
              ? Text(
                  avatarInitial(name),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.39,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                )
              : null),
    );

    final corner =
        badge ??
        (presence == null
            ? null
            : PresenceDot(
                color: presence!,
                size: (size * 0.27).clamp(10.0, 22.0),
                ringColor: ringColor,
                semanticLabel: presenceLabel,
                shape: presenceShape,
              ));
    // The picture is skipped (or named by [semanticLabel]); the corner keeps
    // its own words, e.g. "Online".
    final picture = Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: circle,
    );
    return SizedBox.square(
      dimension: size,
      child: corner == null
          ? picture
          : Stack(
              clipBehavior: Clip.none,
              children: [
                picture,
                Positioned(right: -1, bottom: -1, child: corner),
              ],
            ),
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
    final image = this.image == null
        ? null
        : avatarImageFor(
            this.image!,
            size: size,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
    final held = heldAvatarPicture(
      context,
      image: image,
      size: size,
      onError: onImageError,
    );
    Widget tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: held == null ? Clip.none : Clip.antiAlias,
      decoration: ShapeDecoration(
        color: fill,
        shape: shape,
        image: image == null || held != null
            ? null
            : DecorationImage(
                image: image,
                fit: BoxFit.cover,
                onError: onImageError,
              ),
      ),
      child:
          held ??
          (image != null
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
                )),
    );
    // The squircle is skipped (or named by [semanticLabel]); a badge on its
    // corner keeps its own words ("3 unread").
    final picture = Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: tile,
    );
    return SizedBox.square(
      dimension: size,
      child: badge == null
          ? picture
          : Stack(
              clipBehavior: Clip.none,
              children: [
                picture,
                Positioned(right: -4, top: -4, child: badge!),
              ],
            ),
    );
  }
}

/// Older name for [ThingAvatar].
typedef SquircleAvatar = ThingAvatar;
