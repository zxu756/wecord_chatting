import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The top of a page on paper (friends, notifications, search): a white
/// round back button and a large 26/800 title, with [actions] at the end.
///
/// The back button pops when the page was pushed; on phones a page opened
/// directly (from a link or a notification) goes back to Home instead. Wide
/// layouts have no back button there, the rail and sidebar stay beside it.
class PaperPageHeader extends StatelessWidget {
  const PaperPageHeader({
    required this.title,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 4),
    super.key,
  });

  final String title;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final back = _backAction(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (back != null) ...[
            WeCordIconButton(
              key: const ValueKey('paper-page-back'),
              icon: Icons.chevron_left_rounded,
              iconSize: 24,
              size: 42,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              variant: WeCordButtonVariant.onPaper,
              onPressed: back,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: c.ink,
                ),
              ),
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }

  static VoidCallback? _backAction(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    if (canPop) {
      return () => Navigator.of(context).maybePop();
    }
    final router = GoRouter.maybeOf(context);
    if (router == null || isWideLayout(MediaQuery.sizeOf(context).width)) {
      return null;
    }
    return () => router.go(HomeScreen.path);
  }
}
