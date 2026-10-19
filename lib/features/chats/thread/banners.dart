part of '../chat_thread_screen.dart';

// Small strips and pills around the message list.

/// A group's announcement, as a soft card under the header.
class _AnnouncementStrip extends StatelessWidget {
  const _AnnouncementStrip({
    required this.conversationId,
    required this.announcement,
  });

  final String conversationId;
  final String announcement;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: double.infinity,
      margin: chatUsesDesktopChrome(context)
          ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
          : EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.campaign_outlined, size: 18, color: c.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  announcement,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
                ),
                // "Confirmed 12/30" and the Confirm button, when the owner
                // asked for confirmations (A7).
                AnnouncementAckBar(conversationId: conversationId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The search field that opens under the header (phones and narrow panes).
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.onOpenFullSearch,
    this.resultLabel,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// Opens message search (filters, other scopes) for this conversation.
  final VoidCallback? onOpenFullSearch;
  final String? resultLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final desktop = chatUsesDesktopChrome(context);
    final field = Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: desktop ? c.raised : context.tokens.glass.solidFill,
        borderRadius: BorderRadius.circular(22),
        border: desktop ? null : Border.all(color: c.lineSoft),
        boxShadow: desktop ? null : context.tokens.shadows.hairline,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: c.subtle),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              textInputAction: onOpenFullSearch == null
                  ? null
                  : TextInputAction.search,
              onSubmitted: onOpenFullSearch == null
                  ? null
                  : (_) => onOpenFullSearch!(),
              style: TextStyle(fontSize: 15, color: c.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: tr('Search messages'),
                hintStyle: TextStyle(fontSize: 15, color: c.subtle),
              ),
            ),
          ),
          if (resultLabel case final label?)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
          if (onOpenFullSearch case final open?)
            WeCordIconButton(
              key: const ValueKey('chat-search-open-full'),
              tooltip: tr('Search with filters'),
              icon: Icons.manage_search_rounded,
              size: 32,
              iconSize: 19,
              variant: WeCordButtonVariant.ghost,
              onPressed: open,
            ),
          WeCordIconButton(
            tooltip: tr('Close search'),
            icon: Icons.close_rounded,
            size: 32,
            iconSize: 18,
            variant: WeCordButtonVariant.ghost,
            onPressed: onClose,
          ),
        ],
      ),
    );
    return desktop
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: field,
          )
        : field;
  }
}

/// "3 new messages" floating over the bottom of the list.
class _JumpPill extends StatelessWidget {
  const _JumpPill({
    required this.tooltip,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: label,
      builder: (context, states) => WeCordGlass(
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward_rounded, size: 17, color: c.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
