import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/wecord_glass.dart';
import 'package:wecord/shared/ui/wecord_pressable.dart';

/// The floating glass pill with the signed-in user at the bottom of the
/// rail and sidebar (phone home, desktop sidebars). Layout only: the
/// caller passes the avatar, name, status line and actions.
///
/// It spans the rail and the sidebar: place it in a Stack with
/// `left: -(railWidth - 10)` relative to the sidebar, or simply at the
/// bottom of a Stack covering both.
class FloatingUserPanel extends StatelessWidget {
  const FloatingUserPanel({
    required this.avatar,
    required this.title,
    this.subtitle,
    this.onTap,
    this.actions = const [],
    this.compact = false,
    this.semanticLabel,
    super.key,
  });

  /// Usually a PersonAvatar (46 on phones, 42 on desktop) with presence.
  final Widget avatar;

  final String title;

  /// Presence and custom status ("Online · Planning the weekend").
  final String? subtitle;

  /// Opens the status / account switcher.
  final VoidCallback? onTap;

  /// Round buttons on the right: notifications on phones; mic, headphones
  /// and settings on desktop.
  final List<Widget> actions;

  /// 58 tall (desktop) instead of 64 (phones).
  final bool compact;

  final String? semanticLabel;

  static const phoneHeight = 64.0;
  static const desktopHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final height = compact ? desktopHeight : phoneHeight;
    return WeCordGlass(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: WeCordPressable(
                  onPressed: onTap,
                  pressedScale: 0.98,
                  semanticLabel: semanticLabel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                  builder: (context, states) => Row(
                    children: [
                      avatar,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 14 : 15,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink,
                                    ),
                                  ),
                                ),
                                if (onTap != null && !compact)
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 16,
                                    color: c.ink,
                                  ),
                              ],
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 11.5 : 12,
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
