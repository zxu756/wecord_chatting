import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The look shared by the voice screens (design language C): voice and
/// stage rooms are always dark, with soft color glows behind people's
/// tiles and a floating glass control bar.

/// The dark theme voice rooms use, keeping the platform of [context] so
/// touch and desktop behavior stay the same inside.
ThemeData voiceRoomTheme(BuildContext context) {
  return WeCordTheme.dark().copyWith(platform: Theme.of(context).platform);
}

/// Wraps [child] in the voice room's dark theme.
class VoiceRoomTheme extends StatelessWidget {
  const VoiceRoomTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: voiceRoomTheme(context), child: child);
  }
}

/// The room's backdrop: dark paper with two soft color glows (warm top
/// left, cool on the right) behind [child].
class VoiceRoomBackground extends StatelessWidget {
  const VoiceRoomBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget glow(Color color) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.26),
              color.withValues(alpha: 0.10),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      );
    }

    return ColoredBox(
      color: c.paper,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            left: -140,
            top: -170,
            width: 520,
            height: 520,
            child: IgnorePointer(child: glow(WeCordAvatarColors.all[0])),
          ),
          Positioned(
            right: -170,
            top: 40,
            width: 480,
            height: 480,
            child: IgnorePointer(child: glow(WeCordAvatarColors.all[5])),
          ),
          child,
        ],
      ),
    );
  }
}

/// A person in a voice room: their picture over their initial (which
/// stays when the picture can't load), ringed in green while [speaking].
class VoiceAvatar extends ConsumerWidget {
  const VoiceAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
    this.speaking = false,
    this.badge,
    super.key,
  });

  final String name;
  final String? avatarUrl;
  final double size;
  final bool speaking;

  /// Sits on the bottom-right corner (muted, deafened).
  final Widget? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final url = ref.watch(avatarDisplayUrlProvider(avatarUrl)).value;
    Widget avatar = PersonAvatar(name: name, size: size);
    if (url != null) {
      avatar = Stack(
        children: [
          avatar,
          ClipOval(
            child: Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    final ring = (size * 0.06).clamp(2.0, 4.0);
    avatar = AnimatedContainer(
      duration: WeCordMotion.durationOf(context, WeCordMotion.base),
      curve: WeCordMotion.standard,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: speaking ? c.success : c.success.withValues(alpha: 0),
            spreadRadius: ring,
          ),
          if (speaking)
            BoxShadow(
              color: c.success.withValues(alpha: 0.35),
              spreadRadius: ring * 2.2,
            ),
        ],
      ),
      child: avatar,
    );
    if (badge != null) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(right: -2, bottom: -2, child: badge!),
        ],
      );
    }
    return Semantics(
      label: name,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: avatar),
    );
  }
}

/// A small round badge with an icon, for an avatar's corner (muted,
/// deafened, hand raised).
class VoiceAvatarBadge extends StatelessWidget {
  const VoiceAvatarBadge({
    required this.icon,
    required this.label,
    this.color,
    this.fill,
    this.size = 26,
    this.iconKey,
    super.key,
  });

  final IconData icon;
  final String label;

  /// The icon color; muted by default.
  final Color? color;

  /// The badge fill; the raised color by default.
  final Color? fill;
  final double size;
  final Key? iconKey;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill ?? c.raisedStrong,
        shape: BoxShape.circle,
        border: Border.all(color: c.paper, width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        key: iconKey,
        size: size * 0.52,
        color: color ?? c.muted,
        semanticLabel: label,
      ),
    );
  }
}

/// A round control in a voice room's control bar: a soft light fill on
/// the dark room, filled light (or [activeColor]) while [on].
class VoiceControlButton extends StatelessWidget {
  const VoiceControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.on = false,
    this.activeColor,
    this.badgeCount,
    this.badgeKey,
    this.size = 54,
    this.packed = false,
    super.key,
  });

  /// One of several buttons sharing a narrow bar: the touch target stays 44
  /// there instead of growing to the platform's (48 on Android).
  final bool packed;

  final IconData icon;

  /// Also its accessible label.
  final String tooltip;
  final VoidCallback? onPressed;

  /// Switched on (muted, camera on, hand raised).
  final bool on;

  /// The fill while [on]; the ink color by default.
  final Color? activeColor;

  /// A count on the corner (unread chat).
  final int? badgeCount;
  final Key? badgeKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final activeFill = activeColor ?? c.ink;
    return WeCordPressable(
      minTapSize: packed ? const Size.square(WeCordSizes.touchTarget) : null,
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: on,
      pressedScale: 0.92,
      shape: const CircleBorder(),
      builder: (context, states) {
        final hovered =
            onPressed != null &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        final fill = on
            ? (hovered
                  ? Color.alphaBlend(
                      c.onInk.withValues(alpha: 0.08),
                      activeFill,
                    )
                  : activeFill)
            : c.ink.withValues(alpha: hovered ? 0.17 : 0.10);
        Widget circle = AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          width: size,
          height: size,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Icon(
            icon,
            size: (size * 0.42).clamp(18.0, 24.0),
            color: on ? c.onInk : c.ink,
          ),
        );
        final count = badgeCount ?? 0;
        if (count > 0) {
          circle = Stack(
            clipBehavior: Clip.none,
            children: [
              circle,
              Positioned(
                top: -3,
                right: -3,
                child: CountBadge(
                  key: badgeKey,
                  count: count,
                  size: 20,
                  ringColor: c.paper,
                ),
              ),
            ],
          );
        }
        return AnimatedOpacity(
          opacity: onPressed == null ? 0.4 : 1,
          duration: WeCordMotion.quick,
          child: SizedBox.square(
            dimension: size < WeCordSizes.touchTarget
                ? WeCordSizes.touchTarget
                : size,
            child: Center(child: circle),
          ),
        );
      },
    );
  }
}

/// A round button filled with [fill]: accept (green) and decline (red)
/// on calls, and the round leave button where the bar is short of room.
class VoiceRoundButton extends StatelessWidget {
  const VoiceRoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.fill,
    required this.foreground,
    this.size = 46,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color fill;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return WeCordPressable(
      minTapSize: const Size.square(WeCordSizes.touchTarget),
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      pressedScale: 0.92,
      shape: const CircleBorder(),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedOpacity(
          opacity: onPressed == null ? 0.4 : 1,
          duration: WeCordMotion.quick,
          child: SizedBox.square(
            dimension: size < WeCordSizes.touchTarget
                ? WeCordSizes.touchTarget
                : size,
            child: Center(
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: hovered && onPressed != null
                      ? Color.alphaBlend(
                          Colors.black.withValues(alpha: 0.08),
                          fill,
                        )
                      : fill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: (size * 0.46).clamp(18.0, 24.0),
                  color: foreground,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A pill button in any [fill] (the green Join on calls, the red Leave).
class VoicePillButton extends StatelessWidget {
  const VoicePillButton({
    required this.label,
    required this.onPressed,
    required this.fill,
    required this.foreground,
    this.icon,
    this.tooltip,
    this.height = 44,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color fill;
  final Color foreground;
  final IconData? icon;

  /// Shown on hover; also the accessible label instead of [label].
  final String? tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    return WeCordPressable(
      minTapSize: const Size.square(WeCordSizes.touchTarget),
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      excludeSemantics: tooltip != null,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedOpacity(
          opacity: onPressed == null ? 0.4 : 1,
          duration: WeCordMotion.quick,
          child: AnimatedContainer(
            duration: WeCordMotion.quick,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: height >= 50 ? 22 : 16),
            decoration: ShapeDecoration(
              color: hovered && onPressed != null
                  ? Color.alphaBlend(Colors.black.withValues(alpha: 0.08), fill)
                  : fill,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: height >= 50 ? 15 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One control in a [VoiceControlBar].
@immutable
class VoiceControl {
  const VoiceControl({
    required this.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.on = false,
    this.activeColor,
    this.badgeCount,
    this.badgeKey,
  });

  final Key key;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool on;
  final Color? activeColor;
  final int? badgeCount;
  final Key? badgeKey;
}

/// The floating glass bar at the bottom of a voice room: round controls
/// and a red Leave. On phones it spans the width with the buttons spread
/// out (shrinking when there are many, with Leave turning round); on wide
/// screens it hugs its buttons in the middle.
class VoiceControlBar extends StatelessWidget {
  const VoiceControlBar({
    required this.controls,
    required this.onLeave,
    this.leaveLabel,
    this.leaveTooltip,
    this.leaveKey = const ValueKey('voice-control-leave'),
    this.above,
    super.key,
  });

  final List<VoiceControl> controls;
  final VoidCallback? onLeave;

  /// The red pill's label (Leave); without it the button is round.
  final String? leaveLabel;
  final String? leaveTooltip;
  final Key leaveKey;

  /// Shown centered just above the bar (hold to talk).
  final Widget? above;

  static const _padding = 8.0;
  static const _gap = 8.0;

  /// Room the bar takes at the bottom of its page, to keep content clear
  /// of it (without the safe area).
  static const reservedHeight = 54 + _padding * 2 + 24 + 16;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 600;
        final count = controls.length + 1;
        final inner = (wide ? 640.0 : width) - _padding * 2;
        final size = ((inner - _gap * (count - 1)) / count).clamp(40.0, 54.0);
        // A labelled Leave needs about two buttons' width.
        final labelled =
            leaveLabel != null &&
            inner - (count - 1) * (size + _gap) >= size * 2 + 24;
        final leaveSize = wide ? 50.0 : size;
        final leave = labelled
            ? VoicePillButton(
                key: leaveKey,
                label: leaveLabel!,
                tooltip: leaveTooltip,
                height: wide ? 50 : size,
                fill: c.danger,
                foreground: c.onDanger,
                onPressed: onLeave,
              )
            : VoiceRoundButton(
                key: leaveKey,
                icon: Icons.call_end_rounded,
                tooltip: leaveTooltip ?? leaveLabel ?? '',
                fill: c.danger,
                foreground: c.onDanger,
                size: leaveSize,
                onPressed: onLeave,
              );
        final buttons = [
          for (final control in controls)
            VoiceControlButton(
              key: control.key,
              icon: control.icon,
              tooltip: control.tooltip,
              onPressed: control.onPressed,
              on: control.on,
              activeColor: control.activeColor,
              badgeCount: control.badgeCount,
              badgeKey: control.badgeKey,
              size: wide ? 50 : size,
              packed: true,
            ),
          leave,
        ];
        final bar = WeCordGlass(
          borderRadius: BorderRadius.circular(WeCordRadii.pill),
          padding: const EdgeInsets.all(_padding),
          child: wide
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap + 2),
                      buttons[i],
                    ],
                  ],
                )
              : count * WeCordSizes.touchTarget > inner
              // Too many controls for one row of touch targets (a narrow
              // browser window): a second row, never overlapping buttons.
              ? Wrap(
                  alignment: WrapAlignment.center,
                  runSpacing: 4,
                  children: buttons,
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: buttons,
                ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (above != null) ...[above!, const SizedBox(height: 10)],
            if (wide) Center(child: bar) else bar,
          ],
        );
      },
    );
  }
}

/// A round icon button for a voice room's header (back, chat, settings).
class VoiceHeaderButton extends StatelessWidget {
  const VoiceHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.badgeCount,
    this.badgeKey,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final int? badgeCount;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    return VoiceControlButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      on: selected,
      badgeCount: badgeCount,
      badgeKey: badgeKey,
      size: usesTouchInput(context) ? 42 : 38,
    );
  }
}

/// A small heading in a voice room ("Audience · 41").
class VoiceSectionLabel extends StatelessWidget {
  const VoiceSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.tokens.colors.muted,
      ),
    );
  }
}

/// A status line with a colored dot ("● Voice connected · 3 people").
class VoiceStatusLine extends StatelessWidget {
  const VoiceStatusLine({
    required this.text,
    required this.color,
    this.dotColor,
    super.key,
  });

  final String text;
  final Color color;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor ?? color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
