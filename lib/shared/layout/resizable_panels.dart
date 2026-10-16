import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/panel_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What a [ResizablePanel]'s divider is called by screen readers.
String resizablePanelLabel(ResizablePanel panel) => switch (panel) {
  ResizablePanel.sidebar => tr('Sidebar width'),
  ResizablePanel.members => tr('Member list width'),
  ResizablePanel.profile => tr('Profile panel width'),
};

/// Builds with the sidebar's width in [available] (everything right of the
/// rail): the chosen or dragged width, shrunk when the content needs the
/// room. Rebuilds only [builder] while the divider is dragged.
class SidebarWidthBuilder extends ConsumerWidget {
  const SidebarWidthBuilder({
    required this.available,
    required this.builder,
    super.key,
  });

  final double available;
  final Widget Function(BuildContext context, double width) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(
      panelLayoutProvider.select((layout) => layout.sidebarWidth),
    );
    return ValueListenableBuilder<double?>(
      valueListenable: ref
          .read(panelLayoutProvider.notifier)
          .liveWidth(ResizablePanel.sidebar),
      builder: (context, live, _) =>
          builder(context, resolveSidebarWidth(live ?? chosen, available)),
    );
  }
}

/// The divider on a resizable panel's edge, wired to [panelLayoutProvider]:
/// dragging previews, releasing keeps the width (or closes a right panel
/// dragged shut), double-click resets.
class PanelResizeHandle extends ConsumerWidget {
  const PanelResizeHandle({
    required this.panel,
    required this.width,
    required this.maxWidth,
    super.key,
  });

  final ResizablePanel panel;

  /// The width the panel shows now.
  final double width;

  /// The widest it may get here, leaving the content its minimum.
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(panelLayoutProvider.notifier);
    return ResizableDivider(
      key: ValueKey('resize-${panel.name}'),
      value: width,
      min: panel.min,
      max: maxWidth,
      defaultValue: panel.initial,
      edge: panel == ResizablePanel.sidebar
          ? ResizableDividerEdge.end
          : ResizableDividerEdge.start,
      collapseBelow: panel.collapseBelow,
      semanticLabel: resizablePanelLabel(panel),
      tooltip: tr('Drag to resize · double-click to reset'),
      valueLabel: (width) => tr('{width} px', {'width': width.round()}),
      onChanged: (width) => controller.preview(panel, width),
      onChangeEnd: (width) => width == 0
          ? controller.setCollapsed(panel, true)
          : controller.setWidth(panel, width),
    );
  }
}

/// [child] laid out at least [minWidth] wide and clipped to [width], so a
/// panel squeezed past its minimum (springing back, or closing) slides
/// under its neighbour instead of reflowing.
class _ClippedColumn extends StatelessWidget {
  const _ClippedColumn({
    required this.width,
    required this.minWidth,
    required this.alignment,
    required this.child,
  });

  final double width;
  final double minWidth;
  final Alignment alignment;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final laidOut = math.max(width, minWidth);
    return SizedBox(
      width: math.max(width, 0),
      child: child == null
          ? null
          : ClipRect(
              child: OverflowBox(
                alignment: alignment,
                minWidth: laidOut,
                maxWidth: laidOut,
                child: child,
              ),
            ),
    );
  }
}

/// A desktop sidebar beside [content] with a divider on its right edge.
/// The width is shared by Home and circles and remembered on this device;
/// when the window is too narrow it shrinks toward its minimum so the
/// content keeps [WeCordSizes.contentMin].
class ResizableSidebarRow extends StatelessWidget {
  const ResizableSidebarRow({
    required this.sidebar,
    required this.content,
    super.key,
  });

  final Widget sidebar;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    const panel = ResizablePanel.sidebar;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final maxWidth = math.max(
          panel.min,
          math.min(panel.max, available - WeCordSizes.contentMin),
        );
        return SidebarWidthBuilder(
          available: available,
          builder: (context, width) => Stack(
            fit: StackFit.expand,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ClippedColumn(
                    width: width,
                    minWidth: panel.min,
                    alignment: Alignment.centerLeft,
                    child: sidebar,
                  ),
                  Expanded(child: content),
                ],
              ),
              Positioned(
                left: width - ResizableDivider.hitWidth / 2,
                top: 0,
                bottom: 0,
                width: ResizableDivider.hitWidth,
                child: PanelResizeHandle(
                  panel: panel,
                  width: width,
                  maxWidth: maxWidth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [content] with a resizable right [panel] ([side]) placed by
/// [resolveSidePanel], and a divider on the panel's left edge. Dragging the
/// panel shut closes it. [fixedSide] (a thread) takes the panel's place at
/// [fixedSideWidth], without a divider. The row keeps its shape when the
/// panel opens or closes, so [content] keeps its state.
class ResizableSidePanelRow extends ConsumerWidget {
  const ResizableSidePanelRow({
    required this.panel,
    required this.placement,
    required this.content,
    required this.side,
    this.fixedSide,
    this.fixedSideWidth = 0,
    super.key,
  });

  final ResizablePanel panel;
  final SidePanelPlacement placement;
  final Widget content;
  final Widget side;
  final Widget? fixedSide;
  final double fixedSideWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixedSide = this.fixedSide;
    return ValueListenableBuilder<double?>(
      valueListenable: ref.read(panelLayoutProvider.notifier).liveWidth(panel),
      builder: (context, live, _) {
        final resizable = fixedSide == null && placement.shown;
        final width = fixedSide != null
            ? fixedSideWidth
            : resizable
            ? live ?? placement.width
            : 0.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: content),
                _ClippedColumn(
                  width: width,
                  minWidth: fixedSide != null ? fixedSideWidth : panel.min,
                  alignment: Alignment.centerLeft,
                  child: fixedSide ?? (resizable ? side : null),
                ),
              ],
            ),
            if (resizable)
              Positioned(
                right: width - ResizableDivider.hitWidth / 2,
                top: 0,
                bottom: 0,
                width: ResizableDivider.hitWidth,
                child: PanelResizeHandle(
                  panel: panel,
                  width: width,
                  maxWidth: placement.maxWidth,
                ),
              ),
          ],
        );
      },
    );
  }
}
