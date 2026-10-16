import 'package:flutter/material.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A row in a picker or list sheet: [leading] (an avatar), a title, an
/// optional subtitle (or [subtitleWidget]) and [trailing]. Tappable rows
/// tint on hover and press, like the other WeCord rows.
class SheetListRow extends StatelessWidget {
  const SheetListRow({
    required this.leading,
    required this.title,
    this.titleTrailing,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    this.enabled = true,
    super.key,
  });

  final Widget leading;
  final String title;

  /// Right after the title, such as a bot tag.
  final Widget? titleTrailing;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final subtitle = this.subtitle;
    return WeCordPressable(
      onPressed: enabled ? onTap : null,
      pressedScale: onTap == null ? 1 : 0.98,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final highlighted =
            onTap != null &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        return AnimatedOpacity(
          duration: WeCordMotion.quick,
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: WeCordMotion.quick,
            constraints: const BoxConstraints(
              minHeight: WeCordSizes.touchTarget + 12,
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: highlighted ? c.raised : c.raised.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
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
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                          ),
                          if (titleTrailing case final extra?) ...[
                            const SizedBox(width: 6),
                            extra,
                          ],
                        ],
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.3,
                            color: c.muted,
                          ),
                        ),
                      ?subtitleWidget,
                    ],
                  ),
                ),
                if (trailing case final trailing?) ...[
                  const SizedBox(width: 6),
                  trailing,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A quiet centered note in a sheet: loading, empty or failed.
class SheetNote extends StatelessWidget {
  const SheetNote({required this.text, this.error = false, super.key});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14.5, color: error ? c.dangerText : c.muted),
      ),
    );
  }
}

/// The spinner a sheet shows while its list loads.
class SheetSpinner extends StatelessWidget {
  const SheetSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}
