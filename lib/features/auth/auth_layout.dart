import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The paper page the signed-out screens sit on (sign in, create account,
/// a new password, the two-step code): one column, at most 420 wide, with
/// [footer] pinned to the bottom when there is room. Centred in a window
/// on desktop.
class AuthPage extends StatelessWidget {
  const AuthPage({required this.children, this.footer, super.key});

  final List<Widget> children;

  /// A line at the bottom, e.g. "New here? Create account".
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final column = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, wide ? 24 : 36, 24, 24),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                if (footer != null) ...[
                  const Spacer(),
                  const SizedBox(height: 24),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: WeCordTheme.overlayStyleFor(context.tokens.brightness),
      child: Scaffold(
        backgroundColor: c.paper,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 468,
                maxHeight: wide ? 820 : double.infinity,
              ),
              child: column,
            ),
          ),
        ),
      ),
    );
  }
}

/// The big title (32/800) and the line under it.
class AuthHeading extends StatelessWidget {
  const AuthHeading({
    required this.title,
    this.subtitle,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// 28 instead of 32, for longer titles.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style:
                (compact
                        ? theme.textTheme.displaySmall
                        : theme.textTheme.displayMedium)
                    ?.copyWith(color: c.ink, height: 1.15),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(
            subtitle!,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              color: c.muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// A small accent text link (13–14/700), e.g. "Forgot password?".
class AuthLink extends StatelessWidget {
  const AuthLink({
    required this.label,
    required this.onPressed,
    this.fontSize = 13,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      pressedScale: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: c.accentText,
              decoration: hovered ? TextDecoration.underline : null,
              decorationColor: c.accentText,
            ),
          ),
        );
      },
    );
  }
}

/// An error under a form, in the danger color.
class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.dangerSoft,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: c.dangerText,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.dangerText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A big squircle with an icon above a title, for the screens after
/// signing in (a new password, the two-step code).
class AuthIconTile extends StatelessWidget {
  const AuthIconTile(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ThingAvatar(
        icon: icon,
        size: 64,
        radius: 22,
        color: c.accentSoft,
        foregroundColor: c.accentText,
      ),
    );
  }
}

/// The friendly cluster of people (circles) and circles (squircles) above
/// the sign-in title. Decorative only.
class AuthAvatarCluster extends StatelessWidget {
  const AuthAvatarCluster({super.key});

  static const _width = 334.0;
  static const height = 150.0;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    const colors = WeCordAvatarColors.all;
    Widget at(double left, double top, Widget child, {double turns = 0}) =>
        Positioned(
          left: left,
          top: top,
          child: Transform.rotate(angle: turns * 2 * math.pi, child: child),
        );
    // Short windows (small phones, large text) keep the form in view.
    final screen = MediaQuery.sizeOf(context).height;
    final shown = screen >= 780
        ? height
        : screen >= 680
        ? 96.0
        : 0.0;
    if (shown == 0) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: SizedBox(
        height: shown,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: _width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                at(
                  0,
                  30,
                  ThingAvatar(
                    label: 'W',
                    size: 84,
                    radius: 26,
                    color: colors[4],
                  ),
                  turns: -8 / 360,
                ),
                at(96, 0, PersonAvatar(name: 'L', size: 64, color: colors[0])),
                at(
                  150,
                  62,
                  ThingAvatar(
                    label: 'C',
                    size: 76,
                    radius: 24,
                    color: colors[5],
                  ),
                  turns: 6 / 360,
                ),
                at(
                  238,
                  14,
                  PersonAvatar(name: 'A', size: 56, color: colors[1]),
                ),
                at(
                  276,
                  86,
                  PersonAvatar(name: 'M', size: 58, color: c.warning),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
