import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/custom_status.dart';

/// Opens the sheet to set, change or clear the current user's status.
/// Resolves to true when the status was saved or cleared.
Future<bool?> showCustomStatusSheet(
  BuildContext context, {
  CustomStatus? current,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => CustomStatusSheet(current: current),
  );
}

class CustomStatusSheet extends ConsumerStatefulWidget {
  const CustomStatusSheet({this.current, super.key});

  final CustomStatus? current;

  @override
  ConsumerState<CustomStatusSheet> createState() => _CustomStatusSheetState();
}

class _CustomStatusSheetState extends ConsumerState<CustomStatusSheet> {
  late final _textController = TextEditingController(
    text: widget.current?.text,
  );
  late String? _emoji = widget.current?.emoji;
  var _duration = CustomStatusDuration.never;
  var _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _isEmpty =>
      (_emoji?.trim().isEmpty ?? true) && _textController.text.trim().isEmpty;

  Future<void> _pickEmoji() async {
    final emoji = await showEmojiReactionPicker(context, title: 'Status emoji');
    if (emoji != null && mounted) {
      setState(() => _emoji = emoji);
    }
  }

  Future<void> _save({required bool clear}) async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setCustomStatus(
            emoji: clear ? null : _emoji,
            text: clear ? null : _textController.text,
            expiresAt: clear ? null : _duration.expiresAt(DateTime.now()),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = clear
              ? 'Could not clear status. Try again.'
              : 'Could not save status. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = _emoji;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Set a status', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.outlined(
                  tooltip: emoji == null ? 'Choose emoji' : 'Change emoji',
                  onPressed: _saving ? null : _pickEmoji,
                  icon: emoji == null
                      ? const Icon(Icons.add_reaction_outlined)
                      : Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_saving,
                    maxLength: CustomStatus.maxTextLength,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: "What's happening?",
                      suffixIcon: _isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Remove emoji and text',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _emoji = null;
                                _textController.clear();
                              }),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<CustomStatusDuration>(
              initialValue: _duration,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Clear after',
              ),
              items: [
                for (final duration in CustomStatusDuration.values)
                  DropdownMenuItem(
                    value: duration,
                    child: Text(duration.label),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (duration) {
                      if (duration != null) {
                        setState(() => _duration = duration);
                      }
                    },
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.current != null)
                  TextButton.icon(
                    onPressed: _saving ? null : () => _save(clear: true),
                    icon: const Icon(Icons.backspace_outlined),
                    label: const Text('Clear status'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving || _isEmpty
                      ? null
                      : () => _save(clear: false),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
