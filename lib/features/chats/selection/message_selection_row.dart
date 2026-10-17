import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Wraps one message of the chat list. Outside selection mode it is its
/// child and nothing more. In selection mode the message cannot be used
/// any more (no menu, reply swipe, links or buttons): a tap ticks or
/// unticks it (Shift-click ticks everything from the last one ticked), and
/// a check box sits beside it. The whole row reads to a screen reader as
/// one check box with the message in its label.
class MessageSelectionRow extends ConsumerWidget {
  const MessageSelectionRow({
    required this.conversationId,
    required this.message,
    required this.label,
    required this.entries,
    required this.child,
    super.key,
  });

  final String conversationId;

  /// The list entry (an album is one entry).
  final ChatMessage message;

  /// What a screen reader says for the message ("Ada, 9:20: hello").
  final String Function() label;

  /// The chat's list entries in display order, for Shift-click ranges.
  final List<ChatMessage> Function() entries;

  final Widget child;

  void _toggle(BuildContext context, WidgetRef ref) {
    final controller = ref.read(chatSelectionProvider(conversationId).notifier);
    if (HardwareKeyboard.instance.isShiftPressed) {
      final state = ref.read(chatSelectionProvider(conversationId));
      final all = entries();
      final from = all.indexWhere((entry) => entry.id == state.anchorId);
      final to = all.indexWhere((entry) => entry.id == message.id);
      if (from >= 0 && to >= 0) {
        final low = from < to ? from : to;
        final high = from < to ? to : from;
        final complete = controller.selectAll(
          all.sublist(low, high + 1),
          anchorId: message.id,
        );
        if (!complete) {
          _tooMany(context);
        }
        return;
      }
    }
    if (!controller.toggle(message)) {
      _tooMany(context);
    }
  }

  void _tooMany(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          tr('You can select up to {count} messages.', {
            'count': maxSelectedMessages,
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      chatSelectionProvider(conversationId).select((state) => state.active),
    );
    final selected =
        active &&
        ref.watch(
          chatSelectionProvider(
            conversationId,
          ).select((state) => state.isEntrySelected(message)),
        );
    final selectable = active && isSelectable(message);
    final c = context.tokens.colors;
    final reduceMotion = WeCordMotion.reduceMotion(context);
    final duration = reduceMotion ? Duration.zero : WeCordMotion.quick;
    // The same widgets with selection mode on or off, so the message keeps
    // its state (a voice message that plays, a picture that loaded).
    return Semantics(
      key: ValueKey('selection-row-${message.id}'),
      container: selectable,
      checked: selectable ? selected : null,
      label: selectable
          ? tr('Select message: {message}', {'message': label()})
          : null,
      onTap: selectable ? () => _toggle(context, ref) : null,
      child: ExcludeSemantics(
        excluding: selectable,
        child: MouseRegion(
          cursor: selectable ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: active
                ? HitTestBehavior.opaque
                : HitTestBehavior.deferToChild,
            onTap: selectable ? () => _toggle(context, ref) : null,
            child: AnimatedContainer(
              duration: duration,
              color: selected
                  ? c.accentSoft
                  : c.accentSoft.withValues(alpha: 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: duration,
                    width: active ? 44 : 0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: selectable
                        ? Center(child: SelectionCheck(selected: selected))
                        : null,
                  ),
                  Expanded(
                    child: AbsorbPointer(absorbing: active, child: child),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round check box of a message in selection mode: an empty ring, or
/// the accent filled with a check.
class SelectionCheck extends StatelessWidget {
  const SelectionCheck({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final reduceMotion = WeCordMotion.reduceMotion(context);
    return AnimatedContainer(
      key: ValueKey('selection-check-${selected ? 'on' : 'off'}'),
      duration: reduceMotion ? Duration.zero : WeCordMotion.quick,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.accent : c.panel,
        border: Border.all(color: selected ? c.accent : c.faint, width: 1.6),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 15, color: c.onAccent)
          : null,
    );
  }
}
