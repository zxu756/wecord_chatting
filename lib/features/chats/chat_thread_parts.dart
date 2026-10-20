import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/wallpapers/wallpaper_backdrop.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/display_size_image.dart';
import 'package:wecord/shared/ui/ui.dart';

// Small pieces of the chat thread in design language C: avatars, day and
// unread dividers, the typing indicator, read receipts, bubble shapes and
// the glass menu used for overflow and context menus.

/// Whether the chat shows its desktop chrome: a flat header bar, hover
/// toolbars on messages and right-click menus.
bool chatUsesDesktopChrome(BuildContext context) =>
    isWideLayout(MediaQuery.sizeOf(context).width);

/// The global rectangle [context]'s render box covers.
Rect globalRectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return Rect.zero;
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

/// An avatar for a chat: a person (circle, with an optional presence dot)
/// or a thing (squircle: groups, channels, threads). Loads [avatarUrl] (an
/// http(s) URL or a stored avatar path) over the initial and keeps the
/// initial when it fails.
class ChatAvatar extends ConsumerStatefulWidget {
  const ChatAvatar({
    required this.name,
    required this.avatarUrl,
    this.size = 32,
    this.thing = false,
    this.icon,
    this.presence,
    this.presenceShape = PresenceShape.solid,
    this.presenceLabel,
    this.ringColor,
    super.key,
  });

  final String name;
  final String? avatarUrl;
  final double size;

  /// A squircle (groups, channels, threads) instead of a circle.
  final bool thing;

  /// Shown instead of the initial on a thing (a channel's #, a thread).
  final IconData? icon;

  /// Presence dot color; people only.
  final Color? presence;

  /// The dot's shape and its words, so status doesn't rest on color alone.
  final PresenceShape presenceShape;
  final String? presenceLabel;
  final Color? ringColor;

  @override
  ConsumerState<ChatAvatar> createState() => _ChatAvatarState();
}

class _ChatAvatarState extends ConsumerState<ChatAvatar> {
  String? _failedUrl;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(widget.avatarUrl))
        .value;
    final url = displayUrl == null || displayUrl == _failedUrl
        ? null
        : displayUrl;
    final c = context.tokens.colors;
    final Widget base = widget.thing
        ? ThingAvatar(
            label: widget.name,
            size: size,
            icon: widget.icon,
            color: widget.icon != null ? c.raised : null,
            foregroundColor: widget.icon != null ? c.muted : null,
          )
        : PersonAvatar(name: widget.name, size: size);
    Widget avatar = base;
    if (url != null) {
      final image = Image(
        image: avatarImageFor(
          NetworkImage(url),
          size: size,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _failedUrl != url) {
              setState(() => _failedUrl = url);
              refreshAvatarDisplayUrl(ref, widget.avatarUrl);
            }
          });
          return const SizedBox.shrink();
        },
      );
      avatar = Stack(
        children: [
          base,
          if (widget.thing)
            ClipPath(
              clipper: ShapeBorderClipper(
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(size / 3),
                ),
              ),
              child: image,
            )
          else
            ClipOval(child: image),
        ],
      );
    }
    final presence = widget.presence;
    if (presence != null && !widget.thing) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: PresenceDot(
              color: presence,
              size: (size * 0.3).clamp(10.0, 18.0),
              ringColor: widget.ringColor,
              shape: widget.presenceShape,
              semanticLabel: widget.presenceLabel,
            ),
          ),
        ],
      );
    }
    return SizedBox.square(dimension: size, child: avatar);
  }
}

/// The local day of [value] for a day separator: Today, Yesterday, or the
/// date.
String chatDayLabel(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final todayStart = DateTime(today.year, today.month, today.day);
  final days = todayStart.difference(day).inDays;
  if (days == 0) {
    return tr('Today');
  }
  if (days == 1) {
    return tr('Yesterday');
  }
  if (local.year == today.year) {
    return tr('{month}/{day}', {'month': local.month, 'day': local.day});
  }
  return tr('{year}/{month}/{day}', {
    'year': local.year,
    'month': local.month,
    'day': local.day,
  });
}

/// [value]'s local time as 9:20 or 18:05.
String chatClockTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
}

/// "Today 9:20" above the first message of a day.
class ChatDaySeparator extends StatelessWidget {
  const ChatDaySeparator({required this.time, super.key});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: Center(
        child: Semantics(
          header: true,
          child: WallpaperPill(
            child: Text(
              '${chatDayLabel(time)} ${chatClockTime(time)}',
              key: const ValueKey('chat-day-separator'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The red line above the first unread message.
class ChatNewMessagesDivider extends StatelessWidget {
  const ChatNewMessagesDivider({this.inset = 0, super.key});

  final double inset;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 1, color: c.accent.withValues(alpha: 0.4)),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: tr('New messages'),
            excludeSemantics: true,
            child: WallpaperPill(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Text(
                tr('NEW'),
                style: TextStyle(
                  color: c.accentText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three bouncing dots, still when motion is reduced.
class TypingDots extends StatefulWidget {
  const TypingDots({this.color, super.key});

  final Color? color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WeCordMotion.reduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final color = widget.color ?? c.subtle;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 3; index++) ...[
              if (index > 0) const SizedBox(width: 3),
              Builder(
                builder: (context) {
                  final phase = (_controller.value - index * 0.18) % 1.0;
                  final lift = math.max(0.0, math.sin(phase * math.pi * 2));
                  return Transform.translate(
                    offset: Offset(0, -2.5 * lift),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          color.withValues(alpha: 0.45),
                          color,
                          lift,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

/// "Ada typing..." over the composer.
class ChatTypingIndicator extends StatelessWidget {
  const ChatTypingIndicator({this.name, super.key});

  /// Who is typing, when it is one known person.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final style = TextStyle(fontSize: 12, color: c.muted);
    // A live region: screen readers say who starts typing without being
    // asked, and the dots stay silent.
    return Semantics(
      liveRegion: true,
      container: true,
      child: WallpaperPill(
        child: Row(
          key: const ValueKey('chat-typing-indicator'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(child: TypingDots()),
            const SizedBox(width: 6),
            if (name case final name?) ...[
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(tr('typing...'), style: style),
          ],
        ),
      ),
    );
  }
}

/// The double check and "Read" under the latest outgoing message.
class ChatReadReceipt extends StatelessWidget {
  const ChatReadReceipt({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.done_all_rounded, size: 14, color: c.accent),
        const SizedBox(width: 4),
        Text(
          tr('Read'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
      ],
    );
  }
}

/// A bubble's corners: [WeCordRadii.bubble] outside, [WeCordRadii.bubbleTail]
/// on the sender's side where it meets the bubble before ([joinsAbove]) or
/// after it ([joinsBelow]) in a run.
BorderRadius chatBubbleRadius({
  required bool outgoing,
  required bool joinsAbove,
  required bool joinsBelow,
}) {
  const round = Radius.circular(WeCordRadii.bubble);
  const tail = Radius.circular(WeCordRadii.bubbleTail);
  final top = joinsAbove ? tail : round;
  final bottom = joinsBelow ? tail : round;
  return outgoing
      ? BorderRadius.only(
          topLeft: round,
          bottomLeft: round,
          topRight: top,
          bottomRight: bottom,
        )
      : BorderRadius.only(
          topRight: round,
          bottomRight: round,
          topLeft: top,
          bottomLeft: bottom,
        );
}

/// Reports its child's size after layout whenever it changes.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({required this.onChange, super.child, super.key});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasureSize).onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final size = this.size;
    if (_reported == size) {
      return;
    }
    _reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
  }
}

/// One row of a glass menu.
class GlassMenuEntry {
  const GlassMenuEntry({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.badge = 0,
    this.key,
  }) : isHeader = false;

  /// A small section title between groups of rows (not selectable).
  const GlassMenuEntry.section(this.label)
    : icon = Icons.circle,
      onSelected = null,
      destructive = false,
      badge = 0,
      isHeader = true,
      key = null;

  final IconData icon;
  final String label;

  /// Called after the menu closes; null shows the row disabled.
  final VoidCallback? onSelected;
  final bool destructive;

  /// A count shown at the end of the row (items waiting); nothing at 0.
  final int badge;

  /// A section title instead of a row.
  final bool isHeader;
  final Key? key;
}

/// Opens a floating glass menu next to [anchor] (global coordinates): below
/// it, or above when there is no room, lined up with its nearer edge.
/// [header] sits above the rows (quick reactions in a context menu).
Future<void> showGlassMenu(
  BuildContext context, {
  required Rect anchor,
  required List<GlassMenuEntry> entries,
  Widget? header,
  double width = 248,
}) {
  WeCordHaptics.light();
  return Navigator.of(context).push(
    _GlassMenuRoute(
      anchor: anchor,
      width: width,
      reduceMotion: WeCordMotion.reduceMotion(context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      builder: (menuContext) => GlassMenuPanel(
        header: header,
        entries: [
          for (final entry in entries)
            if (entry.isHeader)
              entry
            else
              GlassMenuEntry(
                key: entry.key,
                icon: entry.icon,
                label: entry.label,
                destructive: entry.destructive,
                badge: entry.badge,
                onSelected: entry.onSelected == null
                    ? null
                    : () {
                        Navigator.of(menuContext).pop();
                        entry.onSelected!();
                      },
              ),
        ],
      ),
    ),
  );
}

/// The glass card of a menu: an optional [header] and rows.
class GlassMenuPanel extends StatelessWidget {
  const GlassMenuPanel({required this.entries, this.header, super.key});

  final List<GlassMenuEntry> entries;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return WeCordGlass(
      elevation: GlassElevation.menu,
      borderRadius: BorderRadius.circular(WeCordRadii.xl - 4),
      padding: const EdgeInsets.all(6),
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header case final header?) ...[
                header,
                const SizedBox(height: 4),
              ],
              for (final (index, entry) in entries.indexed)
                GlassMenuRow(
                  entry: entry,
                  autofocus: index == entries.indexWhere((e) => !e.isHeader),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of a glass menu: icon and label, a soft tint on hover.
class GlassMenuRow extends StatelessWidget {
  const GlassMenuRow({
    required this.entry,
    this.height,
    this.autofocus = false,
    super.key,
  });

  final GlassMenuEntry entry;
  final double? height;

  /// Starts with keyboard focus (the first row of a menu).
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (entry.isHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Semantics(
          header: true,
          child: Text(
            entry.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.subtle,
            ),
          ),
        ),
      );
    }
    final foreground = entry.destructive ? c.dangerText : c.ink;
    final touch = usesTouchInput(context);
    return WeCordPressable(
      key: entry.key,
      autofocus: autofocus && entry.onSelected != null,
      onPressed: entry.onSelected,
      semanticLabel: entry.badge > 0
          ? '${entry.label}, ${tr('{count} waiting', {'count': entry.badge})}'
          : entry.label,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      pressedScale: 0.98,
      builder: (context, states) {
        final active =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          constraints: BoxConstraints(minHeight: height ?? (touch ? 46 : 38)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? (entry.destructive
                      ? c.dangerSoft
                      : c.ink.withValues(alpha: 0.06))
                : c.ink.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          child: Opacity(
            opacity: entry.onSelected == null ? 0.4 : 1,
            child: Row(
              children: [
                Icon(entry.icon, size: touch ? 20 : 18, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.label,
                    // Two lines once the text size is large.
                    maxLines: MediaQuery.textScalerOf(context).scale(10) > 13
                        ? 2
                        : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: touch ? 15 : 14,
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                if (entry.badge > 0) ...[
                  const SizedBox(width: 8),
                  CountBadge(
                    count: entry.badge,
                    tone: BadgeTone.mention,
                    size: 18,
                    semanticLabel: tr('{count} waiting', {
                      'count': entry.badge,
                    }),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlassMenuRoute extends PopupRoute<void> {
  _GlassMenuRoute({
    required this.anchor,
    required this.width,
    required this.reduceMotion,
    required this.builder,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Rect anchor;
  final double width;
  final bool reduceMotion;
  final WidgetBuilder builder;
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
      reduceMotion ? Duration.zero : WeCordMotion.quick;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final padding = MediaQuery.paddingOf(context);
    return capturedThemes.wrap(
      Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: tr('Menu'),
        child: CustomSingleChildLayout(
          delegate: _AnchoredMenuLayout(
            anchor: anchor,
            width: width,
            padding: padding,
          ),
          child: Builder(builder: builder),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: WeCordMotion.bouncy.curve,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class _AnchoredMenuLayout extends SingleChildLayoutDelegate {
  _AnchoredMenuLayout({
    required this.anchor,
    required this.width,
    required this.padding,
  });

  final Rect anchor;
  final double width;
  final EdgeInsets padding;

  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.min(width, constraints.maxWidth - _margin * 2),
      minWidth: math.min(width, constraints.maxWidth - _margin * 2),
      maxHeight: math.max(
        0,
        constraints.maxHeight - padding.vertical - _margin * 2,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final alignRight = anchor.center.dx > size.width / 2;
    var x = alignRight ? anchor.right - childSize.width : anchor.left;
    x = x.clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    );
    final top = padding.top + _margin;
    final bottom = size.height - padding.bottom - _margin;
    var y = anchor.bottom + 6;
    if (y + childSize.height > bottom) {
      final above = anchor.top - 6 - childSize.height;
      y = above >= top ? above : bottom - childSize.height;
    }
    y = y.clamp(top, math.max(top, bottom - childSize.height));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_AnchoredMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      width != oldDelegate.width ||
      padding != oldDelegate.padding;
}
