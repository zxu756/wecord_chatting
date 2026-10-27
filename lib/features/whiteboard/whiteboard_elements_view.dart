import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_describe.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Everything on the board as a list, in reading order: the way to read and
/// change a board without seeing or drawing it (screen readers, switch
/// control, keyboards). Sticky notes and text can be added and edited with
/// words, and anything can be removed or brought forward.
class WhiteboardElementsView extends StatelessWidget {
  const WhiteboardElementsView({required this.controller, super.key});

  final WhiteboardController controller;

  static const addStickyKey = ValueKey('whiteboard-list-add-sticky');
  static const addTextKey = ValueKey('whiteboard-list-add-text');

  Future<void> _askWords(
    BuildContext context, {
    required String title,
    String initial = '',
    required void Function(String text) onDone,
  }) async {
    final text = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('whiteboard-words-field'),
          controller: text,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          decoration: InputDecoration(hintText: tr('Write here')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('whiteboard-words-done'),
            onPressed: () => Navigator.of(context).pop(text.text),
            child: Text(tr('Done')),
          ),
        ],
      ),
    );
    text.dispose();
    if (result != null) {
      onDone(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = readingOrder(controller.engine.elements);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Semantics(
              header: true,
              child: Text(
                items.isEmpty
                    ? tr('Nothing on this whiteboard yet.')
                    : tr('{count} items on this whiteboard, top to bottom.', {
                        'count': items.length,
                      }),
                style: TextStyle(fontSize: 15, color: c.muted, height: 1.4),
              ),
            ),
            if (controller.canEdit) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WeCordButton(
                    key: addStickyKey,
                    label: tr('Add a sticky note'),
                    icon: Icons.sticky_note_2_outlined,
                    variant: WeCordButtonVariant.secondary,
                    size: WeCordButtonSize.small,
                    onPressed: () => unawaited(
                      _askWords(
                        context,
                        title: tr('Sticky note'),
                        onDone: (text) =>
                            controller.addWords(sticky: true, text: text),
                      ),
                    ),
                  ),
                  WeCordButton(
                    key: addTextKey,
                    label: tr('Add text'),
                    icon: Icons.text_fields_rounded,
                    variant: WeCordButtonVariant.secondary,
                    size: WeCordButtonSize.small,
                    onPressed: () => unawaited(
                      _askWords(
                        context,
                        title: tr('Text'),
                        onDone: (text) =>
                            controller.addWords(sticky: false, text: text),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            for (final element in items)
              _Row(
                element: element,
                canEdit: controller.canEdit,
                selected: controller.selection.contains(element.id),
                onEdit:
                    element.kind == WhiteboardKind.sticky ||
                        element.kind == WhiteboardKind.text
                    ? () => unawaited(
                        _askWords(
                          context,
                          title: whiteboardKindName(element),
                          initial: element.text,
                          onDone: (text) =>
                              controller.replaceWords(element.id, text),
                        ),
                      )
                    : null,
                onDelete: () {
                  controller
                    ..select([element.id])
                    ..deleteSelection();
                },
                onFront: () {
                  controller
                    ..select([element.id])
                    ..bringToFront();
                },
                onBack: () {
                  controller
                    ..select([element.id])
                    ..sendToBack();
                },
              ),
          ],
        );
      },
    );
  }
}

enum _RowAction { edit, front, back, delete }

class _Row extends StatelessWidget {
  const _Row({
    required this.element,
    required this.canEdit,
    required this.selected,
    required this.onEdit,
    required this.onDelete,
    required this.onFront,
    required this.onBack,
  });

  final WhiteboardElement element;
  final bool canEdit;
  final bool selected;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFront;
  final VoidCallback onBack;

  IconData get _icon => switch (element.kind) {
    WhiteboardKind.stroke => Icons.edit_outlined,
    WhiteboardKind.shape => switch (element.shape) {
      WhiteboardShape.rect => Icons.crop_square_rounded,
      WhiteboardShape.ellipse => Icons.circle_outlined,
      WhiteboardShape.triangle => Icons.change_history_rounded,
      WhiteboardShape.diamond => Icons.diamond_outlined,
      WhiteboardShape.line => Icons.horizontal_rule_rounded,
      WhiteboardShape.arrow => Icons.arrow_right_alt_rounded,
    },
    WhiteboardKind.sticky => Icons.sticky_note_2_outlined,
    WhiteboardKind.text => Icons.text_fields_rounded,
    WhiteboardKind.image => Icons.image_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? c.accentSoft : c.panel,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(_icon, color: c.muted, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        describeWhiteboardElement(element),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        describeWhiteboardPlace(element),
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
              if (canEdit)
                PopupMenuButton<_RowAction>(
                  tooltip: tr('Actions'),
                  icon: Icon(Icons.more_horiz_rounded, color: c.muted),
                  onSelected: (action) {
                    switch (action) {
                      case _RowAction.edit:
                        onEdit?.call();
                      case _RowAction.front:
                        onFront();
                      case _RowAction.back:
                        onBack();
                      case _RowAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      PopupMenuItem(
                        value: _RowAction.edit,
                        child: Text(tr('Edit words')),
                      ),
                    PopupMenuItem(
                      value: _RowAction.front,
                      child: Text(tr('Bring to front')),
                    ),
                    PopupMenuItem(
                      value: _RowAction.back,
                      child: Text(tr('Send to back')),
                    ),
                    PopupMenuItem(
                      value: _RowAction.delete,
                      child: Text(tr('Delete')),
                    ),
                  ],
                )
              else
                const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}
