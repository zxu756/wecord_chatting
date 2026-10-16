import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// The white content panel that sits beside the rail, with one big
/// rounded corner where it meets the rail (top left, 28 on phones, 22 for
/// the desktop sidebar). Clips its child to that corner.
class PanelSurface extends StatelessWidget {
  const PanelSurface({
    required this.child,
    this.color,
    this.topLeftRadius = WeCordRadii.xxl,
    this.topRightRadius = 0,
    this.border,
    super.key,
  });

  final Widget child;

  /// The panel color by default; the sidebar color for desktop sidebars.
  final Color? color;
  final double topLeftRadius;
  final double topRightRadius;

  /// E.g. a hairline on the left where the content meets a sidebar.
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(topLeftRadius),
      topRight: Radius.circular(topRightRadius),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? context.tokens.colors.panel,
        borderRadius: border == null ? radius : null,
        border: border,
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
