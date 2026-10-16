import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';

/// Builds a sheet's content. [scrollController] is set for sheets with
/// detents and must drive the content's main scroll view so dragging it
/// moves the sheet.
typedef WeCordSheetBuilder =
    Widget Function(BuildContext context, ScrollController? scrollController);

/// Shows a bottom sheet in the WeCord style: a panel with 28 corners and a
/// grabber over a dimmed page.
///
/// Without [detents] the sheet fits its content (up to the screen). With
/// [detents] (fractions of the screen height, e.g. `[0.5, 0.92]`) it is a
/// draggable sheet that snaps between them, starting at [initialDetent]
/// (the first by default).
Future<T?> showWeCordSheet<T>(
  BuildContext context, {
  required WeCordSheetBuilder builder,
  List<double>? detents,
  double? initialDetent,
  String? title,
  bool isDismissible = true,
  bool useRootNavigator = false,
}) {
  final tokens = context.tokens;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: tokens.colors.scrim,
    showDragHandle: false,
    sheetAnimationStyle: AnimationStyle(
      duration: WeCordMotion.smooth.duration,
      curve: WeCordMotion.smooth.curve,
      reverseDuration: WeCordMotion.base,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (context) {
      if (detents == null || detents.isEmpty) {
        return WeCordSheet(
          title: title,
          child: Flexible(child: builder(context, null)),
        );
      }
      final sorted = [...detents]..sort();
      final initial = initialDetent ?? sorted.first;
      return DraggableScrollableSheet(
        expand: false,
        snap: true,
        snapSizes: sorted.length > 2
            ? sorted.sublist(1, sorted.length - 1)
            : null,
        initialChildSize: initial,
        minChildSize: sorted.first,
        maxChildSize: sorted.last,
        builder: (context, scrollController) => WeCordSheet(
          title: title,
          expand: true,
          child: Expanded(child: builder(context, scrollController)),
        ),
      );
    },
  );
}

/// The sheet's frame: panel color, 28 top corners, a grabber and an
/// optional title. [child] must be a Flexible or Expanded (it sits in a
/// Column).
class WeCordSheet extends StatelessWidget {
  const WeCordSheet({
    required this.child,
    this.title,
    this.expand = false,
    super.key,
  });

  final Widget child;
  final String? title;

  /// Whether the frame fills the height it gets (detent sheets).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(WeCordRadii.xxl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: c.track,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
