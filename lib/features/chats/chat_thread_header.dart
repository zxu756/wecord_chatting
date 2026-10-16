import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The chat thread's header. On phones it floats as glass over the
/// messages with a 24 bottom radius (back, avatar, name and status, a
/// couple of actions and More); on desktop it is a flat 58 bar with a
/// hairline under it, every action as a 36 icon button and, when there is
/// room, a search field.
class ChatThreadHeader extends StatelessWidget {
  const ChatThreadHeader({
    required this.desktop,
    required this.compact,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.primaryAction,
    this.onSubtitleTap,
    this.subtitleHint,
    this.onBack,
    this.channelIcon,
    this.searchField,
    super.key,
  });

  /// The flat desktop bar instead of the floating glass header.
  final bool desktop;

  /// Little room: phones keep the first action (search) and [primaryAction]
  /// and move the rest into More.
  final bool compact;

  final VoidCallback? onBack;

  /// Left out for desktop channels, which lead with [channelIcon].
  final Widget? avatar;
  final String title;

  /// Status or topic under (desktop channels: beside) the title.
  final Widget subtitle;

  /// Taps on the title and subtitle (a channel's topic opens in full).
  final VoidCallback? onSubtitleTap;

  /// What a tap on the title says it does, when not "Shows the topic".
  final String? subtitleHint;
  final List<ChatThreadAction> actions;
  final ChatThreadAction primaryAction;

  /// Desktop channels: the # before the name, the topic beside it.
  final IconData? channelIcon;

  /// Desktop: the conversation's search field at the end of the bar.
  final Widget? searchField;

  List<Widget> _buttons(BuildContext context, double size) {
    Widget button(ChatThreadAction action) {
      final selected = action.isSelected == true;
      return WeCordIconButton(
        tooltip: action.tooltip,
        icon: selected ? action.selectedIcon ?? action.icon : action.icon,
        selected: selected,
        size: size,
        iconSize: desktop ? 19 : 21,
        variant: WeCordButtonVariant.ghost,
        onPressed: action.onPressed,
      );
    }

    if (!compact || actions.length <= 2) {
      return [
        for (final action in actions)
          if (compact || !action.menuOnly) button(action),
      ];
    }
    final search = actions.first;
    final overflow = [
      for (final action in actions)
        if (!identical(action, search) && !identical(action, primaryAction))
          action,
    ];
    return [
      button(search),
      button(primaryAction),
      Builder(
        builder: (buttonContext) => WeCordIconButton(
          tooltip: tr('More'),
          icon: Icons.more_horiz_rounded,
          size: size,
          iconSize: desktop ? 19 : 22,
          variant: WeCordButtonVariant.ghost,
          onPressed: () => showGlassMenu(
            buttonContext,
            anchor: globalRectOf(buttonContext),
            entries: [
              for (final action in overflow)
                GlassMenuEntry(
                  icon: action.isSelected == true
                      ? action.selectedIcon ?? action.icon
                      : action.icon,
                  label: action.tooltip,
                  onSelected: action.onPressed,
                ),
            ],
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return desktop ? _buildDesktop(context) : _buildPhone(context);
  }

  /// [child] as a button that shows the topic, when there is one; a tap
  /// target as tall as the header's row so it stays easy to hit.
  Widget _topicButton(Widget child, {required bool alignStart}) {
    final onTap = onSubtitleTap;
    if (onTap == null) {
      return child;
    }
    return WeCordPressable(
      key: const ValueKey('chat-thread-topic'),
      onPressed: onTap,
      hint: subtitleHint ?? tr('Shows the topic'),
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
      ),
      builder: (context, states) => Align(
        alignment: alignStart ? Alignment.centerLeft : Alignment.center,
        widthFactor: 1,
        child: child,
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    final c = context.tokens.colors;
    final top = MediaQuery.paddingOf(context).top;
    return WeCordGlass(
      key: const ValueKey('chat-thread-header'),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      padding: EdgeInsets.fromLTRB(0, top + 6, 2, 8),
      child: Row(
        children: [
          if (onBack != null)
            WeCordIconButton(
              tooltip: tr('Back'),
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 20,
              variant: WeCordButtonVariant.ghost,
              onPressed: onBack,
            )
          else
            const SizedBox(width: 6),
          if (avatar case final avatar?) ...[avatar, const SizedBox(width: 10)],
          Expanded(
            child: _topicButton(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 12, color: c.muted),
                    child: subtitle,
                  ),
                ],
              ),
              alignStart: true,
            ),
          ),
          ..._buttons(context, 40),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final c = context.tokens.colors;
    final channel = channelIcon;
    return Container(
      key: const ValueKey('chat-thread-header'),
      constraints: const BoxConstraints(minHeight: 58),
      padding: EdgeInsets.fromLTRB(onBack != null ? 10 : 20, 0, 14, 0),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            WeCordIconButton(
              tooltip: tr('Back'),
              icon: Icons.arrow_back_ios_new_rounded,
              size: 36,
              iconSize: 17,
              variant: WeCordButtonVariant.ghost,
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
          ],
          if (channel != null) ...[
            // Titles that already start with their # skip the icon.
            if (!title.startsWith('#')) ...[
              Icon(channel, size: 20, color: c.subtle),
              const SizedBox(width: 8),
            ],
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 18, color: c.line),
            const SizedBox(width: 10),
            Expanded(
              child: _topicButton(
                DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 13, color: c.muted),
                  child: subtitle,
                ),
                alignStart: true,
              ),
            ),
          ] else ...[
            if (avatar case final avatar?) ...[
              avatar,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _topicButton(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 12, color: c.muted),
                      child: subtitle,
                    ),
                  ],
                ),
                alignStart: true,
              ),
            ),
          ],
          const SizedBox(width: 8),
          ..._buttons(context, 36),
          if (searchField case final field?) ...[
            const SizedBox(width: 6),
            field,
          ],
        ],
      ),
    );
  }
}

/// The desktop header's search field: a raised 200 wide field that
/// filters the conversation as you type.
class ChatHeaderSearchField extends StatelessWidget {
  const ChatHeaderSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.resultLabel,
    this.onOpenFullSearch,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  /// Opens message search (filters, other scopes); Enter does too.
  final VoidCallback? onOpenFullSearch;

  /// "3 results" while searching.
  final String? resultLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('chat-header-search'),
      width: 240,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: c.subtle),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onOpenFullSearch == null
                  ? null
                  : (_) => onOpenFullSearch!(),
              style: TextStyle(fontSize: 13, color: c.ink),
              cursorHeight: 16,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: c.subtle),
              ),
            ),
          ),
          if (resultLabel case final label?) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ],
          if (onOpenFullSearch case final open?)
            WeCordPressable(
              key: const ValueKey('chat-header-search-open-full'),
              onPressed: open,
              tooltip: tr('Search with filters'),
              semanticLabel: tr('Search with filters'),
              shape: const CircleBorder(),
              builder: (context, states) => Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.manage_search_rounded,
                  size: 18,
                  color: states.contains(WidgetState.hovered)
                      ? c.ink
                      : c.subtle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
