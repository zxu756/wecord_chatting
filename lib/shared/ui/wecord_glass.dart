import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/glass_effects_controller.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// How far a glass surface lifts off what's below it.
enum GlassElevation {
  /// No shadow: toolbars attached to an edge.
  flat,

  /// Floating bars: the user panel, the composer.
  float,

  /// Menus and popovers.
  menu,
}

/// A floating glass surface: translucent fill over a blurred, slightly
/// saturated backdrop, with a 1px light border and a soft shadow.
///
/// Glass is only for things that float over content (the floating user
/// panel, the chat composer and header, long-press menus, toolbars over
/// media). It turns into a solid surface when the Glass effects setting is
/// off, or the platform asks for reduced motion or high contrast
/// (see [WeCordAppearance.glassOf]).
class WeCordGlass extends StatelessWidget {
  const WeCordGlass({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(WeCordRadii.xl)),
    this.padding,
    this.elevation = GlassElevation.float,
    this.showBorder = true,
    this.forceSolid = false,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final GlassElevation elevation;

  /// The 1px light edge; off for surfaces glued to a screen edge.
  final bool showBorder;

  /// Draws the solid fallback whatever the settings say.
  final bool forceSolid;

  static ui.ImageFilter _filter(WeCordGlassStyle glass) {
    final s = glass.saturation;
    // Saturation matrix (Rec. 709 luminance).
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final matrix = <double>[
      r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
      r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0, //
      r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(matrix),
      inner: ui.ImageFilter.blur(
        sigmaX: glass.blur,
        sigmaY: glass.blur,
        tileMode: TileMode.mirror,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final glass = tokens.glass;
    final solid = forceSolid || !WeCordAppearance.glassOf(context);
    final shadows = switch (elevation) {
      GlassElevation.flat => const <BoxShadow>[],
      GlassElevation.float => tokens.shadows.float,
      GlassElevation.menu => tokens.shadows.menu,
    };
    final border = showBorder
        ? Border.all(color: solid ? tokens.colors.line : glass.border)
        : null;

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? glass.solidFill : glass.fill,
        borderRadius: borderRadius,
        border: border,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: solid
            ? content
            : BackdropFilter(filter: _filter(glass), child: content),
      ),
    );
  }
}
