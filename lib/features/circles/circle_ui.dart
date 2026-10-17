import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Building blocks shared by the circle screens in design language "C":
/// paper pages with a round back button and a large title, dialogs that are
/// sheets on phones and centered panels on wide screens, and action menus.

/// Whether circle screens use their wide (desktop) layout here.
bool circleWideLayout(BuildContext context) =>
    isWideLayout(MediaQuery.sizeOf(context).width);

/// The widest a settings column grows on wide screens.
const circlePageMaxWidth = 720.0;

/// A circle page on paper: round white back button, large title, optional
/// [actions], and [body] centred at [circlePageMaxWidth] on wide screens.
class CirclePageScaffold extends StatelessWidget {
  const CirclePageScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
    this.bottom,
    this.constrainBody = true,
    this.subtitle,
    super.key,
  });

  final String title;

  /// A small muted line under the title (e.g. the circle's name).
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  /// Whether [body] is limited to [circlePageMaxWidth] and centred.
  final bool constrainBody;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final wide = circleWideLayout(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final subtitle = this.subtitle;
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: wide ? 24 : 26,
        fontWeight: FontWeight.w800,
        letterSpacing: wide ? -0.4 : -0.6,
        color: c.ink,
      ),
    );
    final page = Scaffold(
      backgroundColor: c.paper,
      floatingActionButton: floatingActionButton,
      appBar: AppBar(
        backgroundColor: c.paper,
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 64 : 0,
        titleSpacing: canPop ? 4 : 20,
        leading: canPop
            ? Center(
                child: BackButton(
                  style: IconButton.styleFrom(
                    backgroundColor: tokens.isDark ? c.raised : c.panel,
                    foregroundColor: c.ink,
                    fixedSize: const Size.square(42),
                    minimumSize: const Size.square(42),
                    shape: const CircleBorder(),
                    elevation: 0,
                  ),
                ),
              )
            : null,
        title: subtitle == null
            ? titleText
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  titleText,
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
        actions: [...actions, const SizedBox(width: 8)],
        bottom: bottom,
      ),
      body: body,
    );
    if (!constrainBody || !wide) {
      return page;
    }
    // On wide screens the title and content share one centred column.
    return ColoredBox(
      color: c.paper,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: circlePageMaxWidth + 64),
          child: page,
        ),
      ),
    );
  }
}

/// A person ([thing] false, round) or circle ([thing] true, squircle)
/// avatar for a stored avatar URL: the initial on a color until the
/// picture loads, and again if it fails (the signed URL is refreshed).
/// [badge] sits bottom right on people and top right on things.
class CircleNetworkAvatar extends ConsumerStatefulWidget {
  const CircleNetworkAvatar({
    required this.name,
    required this.url,
    this.size = 46,
    this.thing = false,
    this.badge,
    super.key,
  });

  final String name;

  /// The stored avatar URL or path, resolved for display.
  final String? url;
  final double size;
  final bool thing;
  final Widget? badge;

  @override
  ConsumerState<CircleNetworkAvatar> createState() =>
      _CircleNetworkAvatarState();
}

class _CircleNetworkAvatarState extends ConsumerState<CircleNetworkAvatar> {
  String? _failedUrl;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final displayUrl = widget.url == null
        ? null
        : ref.watch(avatarDisplayUrlProvider(widget.url)).value;
    final url = displayUrl == _failedUrl ? null : displayUrl;
    final base = widget.thing
        ? ThingAvatar(label: widget.name, size: size)
        : PersonAvatar(name: widget.name, size: size);
    final radius = BorderRadius.circular(size / 3);
    final badge = widget.badge;
    return Semantics(
      label: widget.name,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            base,
            if (url != null)
              Positioned.fill(
                child: widget.thing
                    ? ClipRSuperellipse(
                        borderRadius: radius,
                        child: _image(url),
                      )
                    : ClipOval(child: _image(url)),
              ),
            if (badge != null)
              widget.thing
                  ? Positioned(right: -4, top: -4, child: badge)
                  : Positioned(right: -1, bottom: -1, child: badge),
          ],
        ),
      ),
    );
  }

  Widget _image(String url) => Image.network(
    url,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _failedUrl != url) {
          setState(() => _failedUrl = url);
          refreshAvatarDisplayUrl(ref, widget.url);
        }
      });
      return const SizedBox.shrink();
    },
  );
}

/// The padding of a scrolling column of [SettingsGroup]s on a circle page.
EdgeInsets circlePagePadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom);

/// A white rounded card on a paper page, for content that is not rows.
class CircleCard extends StatelessWidget {
  const CircleCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.tokens.colors.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: child,
    );
  }
}

/// A centred message on an empty circle page (no bans, no events).
class CircleEmptyState extends StatelessWidget {
  const CircleEmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final message = this.message;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThingAvatar(
              icon: icon,
              size: 64,
              color: c.raised,
              foregroundColor: c.muted,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: c.ink,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// A small rounded tag (role, "BOT", "Today").
class CircleTag extends StatelessWidget {
  const CircleTag({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(WeCordRadii.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: foreground,
          height: 1.3,
        ),
      ),
    );
  }
}

/// Shows [builder]'s [CircleDialog] as a sheet on phones and as a centred
/// rounded panel on wide screens.
Future<T?> showCircleDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  if (circleWideLayout(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }
  return showWeCordSheet<T>(
    context,
    isDismissible: barrierDismissible,
    builder: (context, _) =>
        _CircleSheetScope(child: Builder(builder: builder)),
  );
}

class _CircleSheetScope extends InheritedWidget {
  const _CircleSheetScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CircleSheetScope>() != null;

  @override
  bool updateShouldNotify(_CircleSheetScope oldWidget) => false;
}

/// One action of a [CircleDialog].
class CircleDialogAction {
  const CircleDialogAction({
    required this.label,
    required this.onPressed,
    this.variant = WeCordButtonVariant.secondary,
    this.key,
  });

  /// The main action: ink fill.
  const CircleDialogAction.primary({
    required this.label,
    required this.onPressed,
    this.key,
  }) : variant = WeCordButtonVariant.primary;

  /// A destructive main action: red fill.
  const CircleDialogAction.danger({
    required this.label,
    required this.onPressed,
    this.key,
  }) : variant = WeCordButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final WeCordButtonVariant variant;
  final Key? key;
}

/// A dialog's content: title, optional message, [content] and [actions].
/// Inside [showCircleDialog] it lays out as a sheet (full-width buttons,
/// main action first) on phones and as a centred panel (buttons on the
/// right, main action last) on wide screens.
class CircleDialog extends StatelessWidget {
  const CircleDialog({
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.maxWidth = 440,
    super.key,
  });

  final String title;
  final String? message;
  final Widget? content;

  /// In reading order, the main action last.
  final List<CircleDialogAction> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final inSheet = _CircleSheetScope.of(context);
    final message = this.message;
    final header = <Widget>[
      Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: c.ink,
          ),
        ),
      ),
      if (message != null) ...[
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(fontSize: 14.5, color: c.muted, height: 1.45),
        ),
      ],
      if (content != null) ...[const SizedBox(height: 16), content!],
    ];

    Widget button(CircleDialogAction action, {bool expand = false}) =>
        WeCordButton(
          key: action.key,
          label: action.label,
          onPressed: action.onPressed,
          variant: action.variant,
          expand: expand,
          // Roomy pills for confirmations; compact ones next to a field,
          // so they stay above the keyboard.
          size: expand && content == null
              ? WeCordButtonSize.large
              : WeCordButtonSize.medium,
        );

    if (inSheet) {
      final bottom =
          MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.paddingOf(context).bottom;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...header,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              // Side by side, the main action on the right, so the
              // buttons stay above the keyboard.
              Row(
                children: [
                  for (final (index, action) in actions.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: button(action, expand: true)),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xxl),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(WeCordRadii.xxl),
          boxShadow: tokens.shadows.dialog,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...header,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final action in actions) button(action)],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks to confirm [title]; true when [confirmLabel] was pressed.
Future<bool> confirmCircleAction(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  bool destructive = true,
}) async {
  final confirmed = await showCircleDialog<bool>(
    context,
    builder: (context) => CircleDialog(
      title: title,
      message: message,
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        destructive
            ? CircleDialogAction.danger(
                label: confirmLabel,
                onPressed: () => Navigator.of(context).pop(true),
              )
            : CircleDialogAction.primary(
                label: confirmLabel,
                onPressed: () => Navigator.of(context).pop(true),
              ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// One entry of [showCircleActionMenu].
class CircleMenuItem<T> {
  const CircleMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
    this.tone = SettingsTone.neutral,
    this.badge = 0,
  });

  final T value;
  final IconData icon;
  final String label;
  final bool destructive;
  final SettingsTone tone;

  /// A count shown at the end of the entry (items waiting); nothing at 0.
  final int badge;
}

/// A menu of [items]: a sheet of grouped rows on phones; on wide screens a
/// popup at [position] (global) when given, otherwise a centred panel.
/// [groups] split [items] into cards at the given lengths.
Future<T?> showCircleActionMenu<T>(
  BuildContext context, {
  required List<CircleMenuItem<T>> items,
  String? title,
  Widget? header,
  Offset? position,
  List<int>? groups,
}) {
  final wide = circleWideLayout(context);
  if (wide && position != null) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final c = context.tokens.colors;
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            height: 40,
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: item.destructive ? c.dangerText : c.muted,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: item.destructive ? c.dangerText : c.ink,
                    ),
                  ),
                ),
                if (item.badge > 0) ...[
                  const SizedBox(width: 8),
                  CountBadge(count: item.badge, size: 18),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget menu(BuildContext menuContext) {
    final cards = <List<CircleMenuItem<T>>>[];
    var start = 0;
    for (final length in groups ?? [items.length]) {
      final end = (start + length).clamp(0, items.length);
      if (end > start) {
        cards.add(items.sublist(start, end));
      }
      start = end;
    }
    if (start < items.length) {
      cards.add(items.sublist(start));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?header,
        for (final (index, card) in cards.indexed) ...[
          if (index > 0 || header != null) const SizedBox(height: 12),
          SettingsGroup(
            color: context.tokens.colors.well,
            children: [
              for (final item in card)
                SettingsRow(
                  icon: item.icon,
                  tone: item.tone,
                  title: item.label,
                  destructive: item.destructive,
                  showChevron: false,
                  trailing: item.badge > 0
                      ? CountBadge(
                          count: item.badge,
                          semanticLabel: tr('{count} waiting', {
                            'count': item.badge,
                          }),
                        )
                      : null,
                  onTap: () => Navigator.of(menuContext).pop(item.value),
                ),
            ],
          ),
        ],
      ],
    );
  }

  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: context.tokens.colors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.xxl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: context.tokens.colors.ink,
                      ),
                    ),
                  ),
                menu(dialogContext),
              ],
            ),
          ),
        ),
      ),
    );
  }
  return showWeCordSheet<T>(
    context,
    title: title,
    builder: (sheetContext, _) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        12,
        title == null ? 4 : 0,
        12,
        16 + MediaQuery.paddingOf(sheetContext).bottom,
      ),
      child: menu(sheetContext),
    ),
  );
}

/// A friend to invite: avatar, name and username, and a round check.
class CircleFriendPickRow extends StatelessWidget {
  const CircleFriendPickRow({
    required this.friend,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Profile friend;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final onChanged = this.onChanged;
    return WeCordPressable(
      onPressed: onChanged == null ? null : () => onChanged(!selected),
      toggled: selected,
      pressedScale: 1,
      shape: const RoundedRectangleBorder(),
      builder: (context, states) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleNetworkAvatar(
              name: friend.displayLabel,
              url: friend.avatarUrl,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    '@${friend.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: WeCordMotion.quick,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.accent : c.panel,
                border: selected ? null : Border.all(color: c.track, width: 2),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 16, color: c.onAccent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
