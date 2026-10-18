part of '../chat_thread_screen.dart';

// The dialog that names a new thread, and its chip under a message.

/// Asks for a thread title. Returns the trimmed title, or null when
/// cancelled.
class _ThreadTitleDialog extends StatefulWidget {
  const _ThreadTitleDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_ThreadTitleDialog> createState() => _ThreadTitleDialogState();
}

class _ThreadTitleDialogState extends State<_ThreadTitleDialog> {
  late final _controller = TextEditingController(text: widget.initialTitle);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = tr('Thread title is required.'));
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Create thread')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: ConversationThread.maxTitleLength,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: tr('Thread title'),
          errorText: _errorText,
        ),
        onSubmitted: (_) => _create(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _create, child: Text(tr('Create'))),
      ],
    );
  }
}

/// "n replies · time" under a thread's root message; opens the thread.
class _ThreadChip extends StatelessWidget {
  const _ThreadChip({
    required this.messageId,
    required this.summary,
    required this.onTap,
  });

  final String messageId;
  final MessageThreadSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = summary.unreadCount > 0;
    final replies = switch (summary.replyCount) {
      0 => tr('No replies yet'),
      1 => tr('1 reply'),
      final count => tr('{count} replies', {'count': count}),
    };
    final lastReplyAt = summary.lastReplyAt;
    final detail = summary.replyCount > 0 && lastReplyAt != null
        ? '$replies · ${formatThreadActivity(lastReplyAt)}'
        : replies;
    final c = context.tokens.colors;
    return WeCordPressable(
      key: ValueKey('thread-chip-$messageId'),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      pressedScale: 0.98,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: hovered ? c.raised : c.well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 15, color: c.subtle),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  summary.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: unread || summary.replyCount > 0
                        ? c.accentText
                        : c.subtle,
                  ),
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('thread-chip-unread'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
