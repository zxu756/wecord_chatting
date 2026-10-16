import 'package:flutter/material.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A row in a voice menu ([showVoiceMenu]).
sealed class VoiceMenuItem<T> {
  const VoiceMenuItem();
}

/// A row that closes the menu with [value].
class VoiceMenuAction<T> extends VoiceMenuItem<T> {
  const VoiceMenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.checked,
    this.destructive = false,
    this.key,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// For on/off choices (server mute): a check mark while true.
  final bool? checked;
  final bool destructive;
  final Key? key;
}

/// Any widget in the menu, such as a volume slider.
class VoiceMenuCustom<T> extends VoiceMenuItem<T> {
  const VoiceMenuCustom(this.builder);

  final WidgetBuilder builder;
}

/// A hairline between groups of rows.
class VoiceMenuDivider<T> extends VoiceMenuItem<T> {
  const VoiceMenuDivider();
}

/// Opens a menu of [items] under a [title] (with an optional [leading]
/// avatar): a glass context menu at [position] on wide screens, a sheet on
/// phones. Completes with the chosen action's value, or null.
Future<T?> showVoiceMenu<T>(
  BuildContext context, {
  required Offset position,
  required List<VoiceMenuItem<T>> items,
  String? title,
  Widget? leading,
}) {
  final wide = isWideLayout(MediaQuery.sizeOf(context).width);
  if (!wide) {
    return showWeCordSheet<T>(
      context,
      builder: (context, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: _VoiceMenuBody<T>(
          title: title,
          leading: leading,
          items: items,
          inSheet: true,
        ),
      ),
    );
  }
  return Navigator.of(context).push(
    _VoiceMenuRoute<T>(
      position: position,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      barrierLabel: tr('Close'),
      child: _VoiceMenuBody<T>(title: title, leading: leading, items: items),
    ),
  );
}

class _VoiceMenuBody<T> extends StatelessWidget {
  const _VoiceMenuBody({
    required this.items,
    this.title,
    this.leading,
    this.inSheet = false,
  });

  final List<VoiceMenuItem<T>> items;
  final String? title;
  final Widget? leading;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              inSheet ? 8 : 10,
              inSheet ? 4 : 6,
              10,
              inSheet ? 10 : 6,
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: inSheet ? 18 : 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: inSheet ? -0.3 : 0,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        for (final item in items)
          switch (item) {
            VoiceMenuAction<T>() => _VoiceMenuRow<T>(
              action: item,
              large: inSheet,
            ),
            VoiceMenuCustom<T>() => item.builder(context),
            VoiceMenuDivider<T>() => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Container(height: 1, color: c.lineSoft),
            ),
          },
      ],
    );
  }
}

class _VoiceMenuRow<T> extends StatelessWidget {
  const _VoiceMenuRow({required this.action, required this.large});

  final VoiceMenuAction<T> action;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final color = action.destructive ? c.dangerText : c.ink;
    final checked = action.checked;
    return WeCordPressable(
      key: action.key,
      onPressed: () => Navigator.of(context).pop(action.value),
      pressedScale: 0.98,
      selected: checked ?? false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          constraints: BoxConstraints(minHeight: large ? 52 : 40),
          padding: EdgeInsets.symmetric(horizontal: large ? 10 : 10),
          decoration: BoxDecoration(
            color: hovered
                ? (action.destructive
                      ? c.dangerSoft
                      : c.ink.withValues(alpha: 0.06))
                : c.ink.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          child: Row(
            children: [
              if (action.icon != null) ...[
                if (large)
                  SettingsIconTile(
                    icon: action.icon!,
                    tone: action.destructive
                        ? SettingsTone.danger
                        : SettingsTone.neutral,
                    size: 34,
                  )
                else
                  Icon(action.icon, size: 18, color: color),
                SizedBox(width: large ? 12 : 10),
              ],
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 15.5 : 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              if (checked != null)
                AnimatedSwitcher(
                  duration: WeCordMotion.quick,
                  child: checked
                      ? Icon(
                          Icons.check_rounded,
                          key: const ValueKey('checked'),
                          size: 20,
                          color: c.accent,
                        )
                      : const SizedBox(key: ValueKey('unchecked'), width: 20),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceMenuRoute<T> extends PopupRoute<T> {
  _VoiceMenuRoute({
    required this.position,
    required this.child,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Offset position;
  final Widget child;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => WeCordMotion.bouncy.duration;

  @override
  Duration get reverseTransitionDuration => WeCordMotion.quick;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final reduceMotion = WeCordMotion.reduceMotion(context);
    final menu = capturedThemes.wrap(
      Builder(
        builder: (context) => ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
          child: IntrinsicWidth(
            child: WeCordGlass(
              elevation: GlassElevation.menu,
              padding: const EdgeInsets.all(6),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      ),
    );
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: CustomSingleChildLayout(
        delegate: _MenuLayout(position),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            if (reduceMotion) {
              return child!;
            }
            final scale = WeCordMotion.bouncy.curve.transform(animation.value);
            return Opacity(
              opacity: Curves.easeOut.transform(animation.value),
              child: Transform.scale(
                scale: 0.92 + 0.08 * scale,
                alignment: Alignment.topLeft,
                child: child,
              ),
            );
          },
          child: menu,
        ),
      ),
    );
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.position);

  final Offset position;

  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    return BoxConstraints.loose(
      Size(
        (size.width - _margin * 2).clamp(0, double.infinity),
        (size.height - _margin * 2).clamp(0, double.infinity),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = position.dx;
    var y = position.dy;
    if (x + childSize.width > size.width - _margin) {
      x = position.dx - childSize.width;
    }
    if (y + childSize.height > size.height - _margin) {
      y = size.height - _margin - childSize.height;
    }
    return Offset(
      x.clamp(_margin, size.width - _margin - childSize.width),
      y.clamp(_margin, size.height - _margin - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      position != oldDelegate.position;
}
