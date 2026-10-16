import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Where an action sits in the phone's long-press menu: the three big
/// tiles on top, or the list under them.
enum MessageActionSlot { reply, copy, forward, list }

/// Something to do with a message, from its long-press or context menu.
class MessageAction {
  const MessageAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.slot = MessageActionSlot.list,
    this.destructive = false,
    this.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final MessageActionSlot slot;
  final bool destructive;
  final Key? key;

  GlassMenuEntry toEntry() => GlassMenuEntry(
    key: key,
    icon: icon,
    label: label,
    destructive: destructive,
    onSelected: onSelected,
  );
}

/// The phone's long-press menu (design C-menu): the chat blurs, the
/// message lifts in place, quick reactions float above it and the actions
/// below it in glass, Reply / Copy / Forward as tiles and the rest as a
/// list.
Future<void> showMessageActionMenu(
  BuildContext context, {
  required Rect messageRect,
  required bool alignEnd,
  required Widget preview,
  required List<MessageAction> actions,
  Widget? reactions,
}) {
  WeCordHaptics.light();
  final navigator = Navigator.of(context);
  return navigator.push(
    _MessageMenuRoute(
      messageRect: messageRect,
      alignEnd: alignEnd,
      preview: preview,
      reactions: reactions,
      actions: actions,
      reduceMotion: WeCordMotion.reduceMotion(context),
      glass: WeCordAppearance.glassOf(context),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// Opens [actions] as a glass context menu at [position] (global), with
/// [reactions] on top: right-clicks and the hover toolbar's More.
Future<void> showMessageContextMenu(
  BuildContext context, {
  required Rect anchor,
  required List<MessageAction> actions,
  Widget? reactions,
}) {
  final ordered = [
    for (final slot in MessageActionSlot.values)
      for (final action in actions)
        if (action.slot == slot && !action.destructive) action,
    for (final action in actions)
      if (action.destructive) action,
  ];
  return showGlassMenu(
    context,
    anchor: anchor,
    header: reactions,
    entries: [for (final action in ordered) action.toEntry()],
  );
}

class _MessageMenuRoute extends PopupRoute<void> {
  _MessageMenuRoute({
    required this.messageRect,
    required this.alignEnd,
    required this.preview,
    required this.reactions,
    required this.actions,
    required this.reduceMotion,
    required this.glass,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Rect messageRect;
  final bool alignEnd;
  final Widget preview;
  final Widget? reactions;
  final List<MessageAction> actions;
  final bool reduceMotion;
  final bool glass;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : WeCordMotion.bouncy.duration;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : WeCordMotion.base;

  static const _reactionsHeight = 56.0;
  static const _gap = 10.0;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final padding = MediaQuery.paddingOf(context);
    final pop = Navigator.of(context).pop;
    final menu = _MessageMenuCard(
      actions: [
        for (final action in actions)
          MessageAction(
            key: action.key,
            icon: action.icon,
            label: action.label,
            slot: action.slot,
            destructive: action.destructive,
            onSelected: () {
              pop();
              action.onSelected();
            },
          ),
      ],
    );
    final lift = CurvedAnimation(
      parent: animation,
      curve: WeCordMotion.bouncy.curve,
      reverseCurve: Curves.easeInCubic,
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (reactions case final reactions?) ...[
          SizedBox(height: _reactionsHeight, child: reactions),
          const SizedBox(height: _gap),
        ],
        Flexible(
          child: ScaleTransition(
            scale: Tween<double>(begin: 1, end: 1.03).animate(lift),
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: SizedBox(
              width: messageRect.width,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: IgnorePointer(child: preview),
              ),
            ),
          ),
        ),
        const SizedBox(height: _gap),
        menu,
      ],
    );
    return capturedThemes.wrap(
      Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: animation,
                child: _Backdrop(glass: glass),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _MessageMenuLayout(
                messageRect: messageRect,
                alignEnd: alignEnd,
                padding: padding,
                lead: reactions == null ? 0 : _reactionsHeight + _gap,
              ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0, 0.5),
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(lift),
                  alignment: alignEnd
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: content,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// The blurred, tinted chat behind the menu.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.glass});

  final bool glass;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tint = tokens.isDark
        ? tokens.colors.paper.withValues(alpha: 0.55)
        : tokens.colors.rail.withValues(alpha: 0.5);
    if (!glass) {
      return ColoredBox(color: tokens.colors.scrim);
    }
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: ColoredBox(color: tint),
    );
  }
}

class _MessageMenuLayout extends SingleChildLayoutDelegate {
  _MessageMenuLayout({
    required this.messageRect,
    required this.alignEnd,
    required this.padding,
    required this.lead,
  });

  final Rect messageRect;
  final bool alignEnd;
  final EdgeInsets padding;

  /// Height above the message (the reactions and their gap).
  final double lead;

  static const _margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0, constraints.maxWidth - _margin * 2),
      maxHeight: math.max(
        0,
        constraints.maxHeight - padding.vertical - _margin * 2,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = alignEnd ? messageRect.right - childSize.width : messageRect.left;
    x = x.clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    );
    final top = padding.top + _margin;
    final bottom = size.height - padding.bottom - _margin;
    final y = (messageRect.top - lead).clamp(
      top,
      math.max(top, bottom - childSize.height),
    );
    return Offset(x, y.toDouble());
  }

  @override
  bool shouldRelayout(_MessageMenuLayout oldDelegate) =>
      messageRect != oldDelegate.messageRect ||
      alignEnd != oldDelegate.alignEnd ||
      padding != oldDelegate.padding ||
      lead != oldDelegate.lead;
}

/// The glass card under the lifted message.
class _MessageMenuCard extends StatelessWidget {
  const _MessageMenuCard({required this.actions});

  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final glass = WeCordAppearance.glassOf(context);
    final inner = glass
        ? tokens.colors.panel.withValues(alpha: tokens.isDark ? 0.35 : 0.7)
        : tokens.colors.raised;
    final tiles = [
      for (final slot in const [
        MessageActionSlot.reply,
        MessageActionSlot.copy,
        MessageActionSlot.forward,
      ])
        ...actions.where((action) => action.slot == slot),
    ];
    final rows = [
      for (final action in actions)
        if (action.slot == MessageActionSlot.list) action,
    ];
    return SizedBox(
      width: 282,
      child: WeCordGlass(
        key: const ValueKey('message-action-menu'),
        elevation: GlassElevation.menu,
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.all(10),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tiles.isNotEmpty)
                Row(
                  children: [
                    for (final (index, action) in tiles.indexed) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _ActionTile(action: action, fill: inner),
                      ),
                    ],
                  ],
                ),
              if (tiles.isNotEmpty && rows.isNotEmpty)
                const SizedBox(height: 8),
              if (rows.isNotEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: inner,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final action in rows)
                          GlassMenuRow(height: 46, entry: action.toEntry()),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.fill});

  final MessageAction action;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: action.key,
      onPressed: action.onSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (context, states) {
        final active =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          height: 72,
          decoration: BoxDecoration(
            color: active
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.06), fill)
                : fill,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, size: 21, color: c.ink),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The small glass toolbar a message shows while hovered on desktop:
/// react, reply and more.
class MessageHoverToolbar extends StatelessWidget {
  const MessageHoverToolbar({
    required this.onReact,
    required this.onMore,
    this.onReply,
    super.key,
  });

  final VoidCallback onReact;
  final VoidCallback? onReply;

  /// Gets the More button's context to anchor the menu.
  final ValueChanged<BuildContext> onMore;

  @override
  Widget build(BuildContext context) {
    return WeCordGlass(
      key: const ValueKey('message-hover-toolbar'),
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarButton(
            icon: Icons.add_reaction_outlined,
            tooltip: tr('Add reaction'),
            onPressed: onReact,
          ),
          if (onReply case final onReply?)
            _ToolbarButton(
              icon: Icons.reply_rounded,
              tooltip: tr('Reply'),
              onPressed: onReply,
            ),
          Builder(
            builder: (context) => _ToolbarButton(
              icon: Icons.more_horiz_rounded,
              tooltip: tr('More actions'),
              onPressed: () => onMore(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      pressedScale: 0.9,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: hovered
                ? c.ink.withValues(alpha: 0.07)
                : c.ink.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: c.ink),
        );
      },
    );
  }
}
