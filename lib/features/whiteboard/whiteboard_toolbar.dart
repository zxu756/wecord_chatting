import 'package:flutter/material.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_describe.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

String whiteboardToolName(WhiteboardTool tool) {
  return switch (tool) {
    WhiteboardTool.select => tr('Select'),
    WhiteboardTool.pen => tr('Pen'),
    WhiteboardTool.highlighter => tr('Highlighter'),
    WhiteboardTool.eraser => tr('Eraser'),
    WhiteboardTool.shape => tr('Shapes'),
    WhiteboardTool.sticky => tr('Sticky note'),
    WhiteboardTool.text => tr('Text'),
    WhiteboardTool.image => tr('Picture'),
    WhiteboardTool.hand => tr('Move the view'),
  };
}

IconData whiteboardToolIcon(WhiteboardTool tool) {
  return switch (tool) {
    WhiteboardTool.select => Icons.near_me_outlined,
    WhiteboardTool.pen => Icons.edit_outlined,
    WhiteboardTool.highlighter => Icons.border_color_outlined,
    WhiteboardTool.eraser => Icons.cleaning_services_outlined,
    WhiteboardTool.shape => Icons.category_outlined,
    WhiteboardTool.sticky => Icons.sticky_note_2_outlined,
    WhiteboardTool.text => Icons.text_fields_rounded,
    WhiteboardTool.image => Icons.image_outlined,
    WhiteboardTool.hand => Icons.pan_tool_alt_outlined,
  };
}

IconData whiteboardShapeIcon(WhiteboardShape shape) {
  return switch (shape) {
    WhiteboardShape.rect => Icons.crop_square_rounded,
    WhiteboardShape.ellipse => Icons.circle_outlined,
    WhiteboardShape.triangle => Icons.change_history_rounded,
    WhiteboardShape.diamond => Icons.diamond_outlined,
    WhiteboardShape.line => Icons.horizontal_rule_rounded,
    WhiteboardShape.arrow => Icons.arrow_right_alt_rounded,
  };
}

/// The tools along the bottom, and above them the options of the tool in
/// use (colors, widths, shapes) or, with something selected, what can be
/// done to it. Both rows scroll sideways so nothing is cut off on a small
/// screen or at a large text size.
class WhiteboardToolbar extends StatelessWidget {
  const WhiteboardToolbar({
    required this.controller,
    required this.onPickPicture,
    super.key,
  });

  final WhiteboardController controller;
  final VoidCallback onPickPicture;

  static ValueKey<String> toolKey(WhiteboardTool tool) =>
      ValueKey('whiteboard-tool-${tool.name}');

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final options = _options(context);
        return Material(
          color: c.panel,
          elevation: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.lineSoft)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?options,
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        for (final tool in WhiteboardTool.values)
                          if (controller.canEdit ||
                              tool == WhiteboardTool.select ||
                              tool == WhiteboardTool.hand)
                            _ToolButton(
                              key: toolKey(tool),
                              tool: tool,
                              selected: controller.tool == tool,
                              onPressed: () {
                                if (tool == WhiteboardTool.image) {
                                  onPickPicture();
                                } else {
                                  controller.setTool(tool);
                                }
                              },
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _options(BuildContext context) {
    if (!controller.canEdit) {
      return null;
    }
    final selected = controller.selectedElements;
    final tool = controller.tool;
    final rows = <Widget>[];
    final anyStroke = selected.any((e) => e.kind == WhiteboardKind.stroke);
    final anyShape = selected.any((e) => e.kind == WhiteboardKind.shape);
    final anySticky = selected.any((e) => e.kind == WhiteboardKind.sticky);
    final anyText = selected.any((e) => e.kind == WhiteboardKind.text);

    if (tool == WhiteboardTool.select && selected.isNotEmpty) {
      rows.add(
        _OptionRow(
          children: [
            _ActionChip(
              key: const ValueKey('whiteboard-action-duplicate'),
              icon: Icons.copy_rounded,
              label: tr('Duplicate'),
              onPressed: controller.duplicateSelection,
            ),
            _ActionChip(
              key: const ValueKey('whiteboard-action-front'),
              icon: Icons.flip_to_front_rounded,
              label: tr('Bring to front'),
              onPressed: controller.bringToFront,
            ),
            _ActionChip(
              key: const ValueKey('whiteboard-action-back'),
              icon: Icons.flip_to_back_rounded,
              label: tr('Send to back'),
              onPressed: controller.sendToBack,
            ),
            _ActionChip(
              key: const ValueKey('whiteboard-action-delete'),
              icon: Icons.delete_outline_rounded,
              label: tr('Delete'),
              danger: true,
              onPressed: controller.deleteSelection,
            ),
          ],
        ),
      );
    }

    final showInk =
        tool == WhiteboardTool.pen ||
        tool == WhiteboardTool.highlighter ||
        tool == WhiteboardTool.shape ||
        tool == WhiteboardTool.text ||
        (tool == WhiteboardTool.select &&
            (anyStroke || anyShape || anyText));
    final showWidths =
        tool == WhiteboardTool.pen ||
        tool == WhiteboardTool.highlighter ||
        tool == WhiteboardTool.shape ||
        (tool == WhiteboardTool.select && (anyStroke || anyShape));
    final showNotes =
        tool == WhiteboardTool.sticky ||
        (tool == WhiteboardTool.select && anySticky);

    if (tool == WhiteboardTool.shape) {
      rows.add(
        _OptionRow(
          children: [
            for (final shape in WhiteboardShape.values)
              _IconChoice(
                key: ValueKey('whiteboard-shape-${shape.value}'),
                icon: whiteboardShapeIcon(shape),
                label: whiteboardShapeName(shape),
                selected: controller.shapeKind == shape,
                onPressed: () => controller.setShapeKind(shape),
              ),
            const SizedBox(width: 8),
            _IconChoice(
              key: const ValueKey('whiteboard-shape-fill'),
              icon: Icons.format_color_fill_rounded,
              label: tr('Filled'),
              selected: controller.shapeFilled,
              onPressed: () =>
                  controller.setShapeFilled(!controller.shapeFilled),
            ),
          ],
        ),
      );
    }
    if (showInk) {
      rows.add(
        _OptionRow(
          children: [
            for (final color in whiteboardInkColors)
              _Swatch(
                key: ValueKey('whiteboard-color-${color.toRadixString(16)}'),
                color: color,
                selected: controller.inkColor == color,
                onPressed: () => controller.setInkColor(color),
              ),
          ],
        ),
      );
    }
    if (showNotes) {
      rows.add(
        _OptionRow(
          children: [
            for (final color in whiteboardNoteColors)
              _Swatch(
                key: ValueKey('whiteboard-note-${color.toRadixString(16)}'),
                color: color,
                selected: controller.noteColor == color,
                onPressed: () => controller.setNoteColor(color),
              ),
          ],
        ),
      );
    }
    if (showWidths) {
      rows.add(
        _OptionRow(
          children: [
            for (final width in whiteboardWidths)
              _WidthChoice(
                key: ValueKey('whiteboard-width-${width.round()}'),
                width: width,
                selected: controller.inkWidth == width,
                onPressed: () => controller.setInkWidth(width),
              ),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      return null;
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(children: children),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final WhiteboardTool tool;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final name = whiteboardToolName(tool);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: name,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              whiteboardToolIcon(tool),
              size: 24,
              color: selected ? c.accentText : c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final int color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final value = Color(color);
    return Semantics(
      button: true,
      selected: selected,
      label: whiteboardColorName(color),
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: value,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? c.accent : c.line,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthChoice extends StatelessWidget {
  const _WidthChoice({
    required this.width,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final double width;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: tr('Line width {width}', {'width': width.round()}),
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 28,
            height: width.clamp(2, 14),
            decoration: BoxDecoration(
              color: selected ? c.accentText : c.muted,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: selected ? c.accentText : c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final color = danger ? c.dangerText : c.ink;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: danger ? c.dangerSoft : c.well,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
