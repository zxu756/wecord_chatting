import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A settings page in design language C: the paper background, a white
/// round back button and a large title above [children] (usually
/// [SettingsGroup]s), which scroll under the title.
///
/// Inside the desktop settings window ([SettingsWindowScope]) the header
/// is the window's: a 24px title and, at the root, the close button.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.title,
    required this.children,
    this.actions = const [],
    this.onBack,
    this.maxWidth = 640,
    this.padding,
    super.key,
  });

  final String title;
  final List<Widget> children;

  /// Buttons after the title.
  final List<Widget> actions;

  /// Overrides what the back button does (pops the page by default; goes
  /// Home on phones when there is nothing to pop).
  final VoidCallback? onBack;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final window = SettingsWindowScope.maybeOf(context);
    final back = settingsBackAction(context, onBack: onBack);
    final header = window != null
        ? _WindowHeader(
            title: title,
            onBack: back,
            onClose: window.onClose,
            actions: actions,
          )
        : _PhoneHeader(title: title, onBack: back, actions: actions);
    final gutter = window != null ? 34.0 : WeCordSpace.gutter;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        top: window == null,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                window != null ? 26 : 12,
                gutter,
                window != null ? 8 : 4,
              ),
              child: header,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: window != null ? double.infinity : maxWidth,
                  ),
                  child: ListView(
                    key: const ValueKey('settings-page-list'),
                    padding:
                        padding ??
                        EdgeInsets.fromLTRB(
                          gutter,
                          0,
                          gutter,
                          32 + MediaQuery.paddingOf(context).bottom,
                        ),
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a settings page's back button does: pop the page, or on phones go
/// Home when the page was opened directly; null when there is no way back
/// (the desktop window's first page).
VoidCallback? settingsBackAction(BuildContext context, {VoidCallback? onBack}) {
  if (onBack != null) {
    return onBack;
  }
  final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
  if (canPop) {
    return () => Navigator.of(context).maybePop();
  }
  final router = GoRouter.maybeOf(context);
  if (router == null ||
      SettingsWindowScope.maybeOf(context) != null ||
      isWideLayout(MediaQuery.sizeOf(context).width)) {
    return null;
  }
  return () => router.go(HomeScreen.path);
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({
    required this.title,
    required this.onBack,
    required this.actions,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          if (onBack != null) ...[
            WeCordIconButton(
              key: const ValueKey('settings-back'),
              icon: Icons.chevron_left_rounded,
              tooltip: tr('Back'),
              variant: WeCordButtonVariant.onPaper,
              size: 42,
              iconSize: 24,
              onPressed: onBack,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Semantics(
              header: true,
              // Shrinks to the row at large text sizes instead of clipping.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _WindowHeader extends StatelessWidget {
  const _WindowHeader({
    required this.title,
    required this.onBack,
    required this.onClose,
    required this.actions,
  });

  final String title;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      children: [
        if (onBack != null) ...[
          WeCordIconButton(
            key: const ValueKey('settings-back'),
            icon: Icons.chevron_left_rounded,
            tooltip: tr('Back'),
            variant: WeCordButtonVariant.onPaper,
            size: 36,
            iconSize: 22,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: c.ink,
              ),
            ),
          ),
        ),
        ...actions,
        const SizedBox(width: 8),
        WeCordIconButton(
          key: const ValueKey('settings-window-close'),
          icon: Icons.close_rounded,
          tooltip: tr('Close settings'),
          variant: WeCordButtonVariant.onPaper,
          size: 36,
          iconSize: 18,
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// Marks pages shown inside the desktop settings window, and closes it.
class SettingsWindowScope extends InheritedWidget {
  const SettingsWindowScope({
    required this.onClose,
    required super.child,
    super.key,
  });

  final VoidCallback onClose;

  static SettingsWindowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsWindowScope>();

  @override
  bool updateShouldNotify(SettingsWindowScope oldWidget) =>
      onClose != oldWidget.onClose;
}
