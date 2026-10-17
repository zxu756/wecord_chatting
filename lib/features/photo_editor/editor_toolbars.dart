import 'package:flutter/material.dart';
import 'package:wecord/features/photo_editor/crop_math.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

String editorColorName(int argb) {
  for (final color in EditorPalette.colors) {
    if (color.argb == argb) {
      return tr(color.name);
    }
  }
  return tr('Color');
}

/// The four tools, each with an icon and its name.
class EditorToolSelector extends StatelessWidget {
  const EditorToolSelector({
    required this.tool,
    required this.onSelected,
    super.key,
  });

  final EditorTool tool;
  final ValueChanged<EditorTool> onSelected;

  static String label(EditorTool tool) => switch (tool) {
    EditorTool.draw => tr('Draw'),
    EditorTool.text => tr('Text'),
    EditorTool.mosaic => tr('Mosaic'),
    EditorTool.crop => tr('Crop'),
  };

  static IconData icon(EditorTool tool) => switch (tool) {
    EditorTool.draw => Icons.draw_rounded,
    EditorTool.text => Icons.text_fields_rounded,
    EditorTool.mosaic => Icons.blur_on_rounded,
    EditorTool.crop => Icons.crop_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      children: [
        for (final item in EditorTool.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: WeCordPressable(
                key: ValueKey('photo-editor-tool-${item.name}'),
                selected: item == tool,
                semanticLabel: label(item),
                tooltip: label(item),
                excludeSemantics: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                onPressed: () => onSelected(item),
                builder: (context, states) {
                  final selected = item == tool;
                  final hovered =
                      states.contains(WidgetState.hovered) && !selected;
                  return AnimatedContainer(
                    duration: WeCordMotion.quick,
                    curve: WeCordMotion.standard,
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? c.ink
                          : hovered
                          ? c.raised
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(WeCordRadii.lg),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon(item),
                          size: 22,
                          color: selected ? c.onInk : c.ink,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected ? c.onInk : c.muted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// The eight colors as round swatches.
class EditorColorRow extends StatelessWidget {
  const EditorColorRow({
    required this.selected,
    required this.onSelected,
    this.keyPrefix = 'photo-editor-color',
    this.compact = false,
    super.key,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final String keyPrefix;

  /// Narrower swatches, to fit eight beside another control.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final cell = compact ? 34.0 : 40.0;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 0,
      runSpacing: 0,
      children: [
        for (final color in EditorPalette.colors)
          WeCordPressable(
            key: ValueKey('$keyPrefix-${color.argb.toRadixString(16)}'),
            semanticLabel: tr(color.name),
            tooltip: tr(color.name),
            selected: color.argb == selected,
            excludeSemantics: true,
            shape: const CircleBorder(),
            pressedScale: 0.9,
            onPressed: () => onSelected(color.argb),
            builder: (context, states) {
              final on = color.argb == selected;
              return SizedBox.square(
                dimension: cell,
                child: Center(
                  child: AnimatedContainer(
                    duration: WeCordMotion.quick,
                    width: on ? 30 : 26,
                    height: on ? 30 : 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(color.argb),
                      border: Border.all(
                        color: on
                            ? c.accent
                            : states.contains(WidgetState.hovered)
                            ? c.ink
                            : c.line,
                        width: on ? 3 : 1.5,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Thin, medium and thick, as dots of growing size.
class EditorWidthPicker extends StatelessWidget {
  const EditorWidthPicker({
    required this.selected,
    required this.onSelected,
    this.keyPrefix = 'photo-editor-width',
    super.key,
  });

  final StrokeWidth selected;
  final ValueChanged<StrokeWidth> onSelected;
  final String keyPrefix;

  static String label(StrokeWidth width) => switch (width) {
    StrokeWidth.thin => tr('Thin'),
    StrokeWidth.medium => tr('Medium'),
    StrokeWidth.thick => tr('Thick'),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final width in StrokeWidth.values)
          WeCordPressable(
            key: ValueKey('$keyPrefix-${width.name}'),
            semanticLabel: label(width),
            tooltip: label(width),
            selected: width == selected,
            excludeSemantics: true,
            shape: const CircleBorder(),
            pressedScale: 0.9,
            onPressed: () => onSelected(width),
            builder: (context, states) {
              final on = width == selected;
              final dot = switch (width) {
                StrokeWidth.thin => 6.0,
                StrokeWidth.medium => 11.0,
                StrokeWidth.thick => 17.0,
              };
              return Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on
                      ? c.raisedStrong
                      : states.contains(WidgetState.hovered)
                      ? c.raised
                      : Colors.transparent,
                ),
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? c.accentText : c.muted,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// A small labelled icon button for the option rows.
class EditorOptionButton extends StatelessWidget {
  const EditorOptionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.showLabel = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  /// Writes the name next to the icon.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      semanticLabel: label,
      tooltip: label,
      selected: selected,
      excludeSemantics: true,
      onPressed: onPressed,
      shape: const StadiumBorder(),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        final foreground = onPressed == null
            ? c.faint
            : selected
            ? c.onInk
            : c.ink;
        return Container(
          constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 14 : 8),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: selected
                ? c.ink
                : hovered && onPressed != null
                ? c.raisedStrong
                : c.raised,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: foreground),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
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

/// The options of the pen: color and width.
class DrawOptions extends StatelessWidget {
  const DrawOptions({required this.session, super.key});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EditorColorRow(
          selected: session.penColor,
          onSelected: session.setPenColor,
        ),
        EditorWidthPicker(
          selected: session.penWidth,
          onSelected: session.setPenWidth,
        ),
      ],
    );
  }
}

/// The options of the mosaic brush: pixelate or blur, and the brush size.
class MosaicOptions extends StatelessWidget {
  const MosaicOptions({required this.session, super.key});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: WeCordSegmented<MosaicKind>(
              key: const ValueKey('photo-editor-mosaic-kind'),
              expand: true,
              semanticLabel: tr('Brush'),
              selected: session.mosaicKind,
              onChanged: session.setMosaicKind,
              segments: [
                WeCordSegment(
                  value: MosaicKind.pixelate,
                  label: tr('Pixelate'),
                  icon: Icons.grid_view_rounded,
                  key: const ValueKey('photo-editor-mosaic-pixelate'),
                ),
                WeCordSegment(
                  value: MosaicKind.blur,
                  label: tr('Blur'),
                  icon: Icons.blur_circular_rounded,
                  key: const ValueKey('photo-editor-mosaic-blur'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        EditorWidthPicker(
          keyPrefix: 'photo-editor-brush',
          selected: session.mosaicWidth,
          onSelected: session.setMosaicWidth,
        ),
      ],
    );
  }
}

/// The options of text: color, the pill behind it, and what can be done to
/// the selected text (so the keyboard reaches all of it).
class TextOptions extends StatelessWidget {
  const TextOptions({
    required this.session,
    required this.onAdd,
    required this.onEdit,
    super.key,
  });

  final EditorSession session;
  final VoidCallback onAdd;
  final ValueChanged<TextOverlay> onEdit;

  @override
  Widget build(BuildContext context) {
    final selected = session.selectedText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EditorColorRow(
          keyPrefix: 'photo-editor-text-color',
          selected: selected?.color ?? session.textColor,
          onSelected: session.setTextColor,
        ),
        const SizedBox(height: 2),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            EditorOptionButton(
              key: const ValueKey('photo-editor-text-add'),
              icon: Icons.add_rounded,
              label: tr('Add text'),
              showLabel: true,
              onPressed: onAdd,
            ),
            EditorOptionButton(
              key: const ValueKey('photo-editor-text-pill'),
              icon: Icons.rounded_corner_rounded,
              label: tr('Background'),
              showLabel: true,
              selected: selected?.pill ?? session.textPill,
              onPressed: () =>
                  session.setTextPill(!(selected?.pill ?? session.textPill)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // What can be done to the selected text; there from the start, so
        // the toolbar does not change height when a text is selected.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            EditorOptionButton(
              key: const ValueKey('photo-editor-text-edit'),
              icon: Icons.edit_outlined,
              label: tr('Edit text'),
              onPressed: selected == null ? null : () => onEdit(selected),
            ),
            EditorOptionButton(
              key: const ValueKey('photo-editor-text-smaller'),
              icon: Icons.text_decrease_rounded,
              label: tr('Smaller'),
              onPressed: selected == null
                  ? null
                  : () => session.scaleSelectedText(1 / 1.15),
            ),
            EditorOptionButton(
              key: const ValueKey('photo-editor-text-larger'),
              icon: Icons.text_increase_rounded,
              label: tr('Larger'),
              onPressed: selected == null
                  ? null
                  : () => session.scaleSelectedText(1.15),
            ),
            EditorOptionButton(
              key: const ValueKey('photo-editor-text-turn'),
              icon: Icons.rotate_right_rounded,
              label: tr('Turn text'),
              onPressed: selected == null
                  ? null
                  : () => session.rotateSelectedText(0.2618),
            ),
            EditorOptionButton(
              key: const ValueKey('photo-editor-text-delete'),
              icon: Icons.delete_outline_rounded,
              label: tr('Delete text'),
              onPressed: selected == null
                  ? null
                  : () => session.removeText(selected.id),
            ),
          ],
        ),
      ],
    );
  }
}

/// The options of cropping: ratio chips, rotate and reset.
class CropOptions extends StatelessWidget {
  const CropOptions({required this.session, super.key});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final ratio in CropRatio.values)
              WeCordChip(
                key: ValueKey('photo-editor-ratio-${ratio.name}'),
                label: ratio == CropRatio.free ? tr('Free') : ratio.label,
                selected: session.ratio == ratio,
                height: 40,
                onPressed: () => session.setRatio(ratio),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            EditorOptionButton(
              key: const ValueKey('photo-editor-rotate'),
              icon: Icons.rotate_right_rounded,
              label: tr('Rotate'),
              showLabel: true,
              onPressed: session.rotateClockwise,
            ),
            EditorOptionButton(
              key: const ValueKey('photo-editor-crop-reset'),
              icon: Icons.restart_alt_rounded,
              label: tr('Reset'),
              showLabel: true,
              onPressed: session.canResetCrop ? session.resetCrop : null,
            ),
          ],
        ),
      ],
    );
  }
}
