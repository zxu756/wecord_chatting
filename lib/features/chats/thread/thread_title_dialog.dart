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
