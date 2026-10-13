import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_creation_sheet.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/shared/models/circle.dart';

final circleSummariesProvider = FutureProvider.autoDispose<List<CircleSummary>>(
  (ref) => ref.watch(circlesRepositoryProvider).listCircles(),
);

/// Vertical strip of circle icons, modelled on a server switcher: icons morph
/// from a circle to a rounded square and grow a left pill when hovered or
/// selected.
class CircleRail extends ConsumerWidget {
  const CircleRail({required this.selectedCircleId, super.key});

  static const width = 72.0;

  final String selectedCircleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final circles =
        ref.watch(circleSummariesProvider).valueOrNull ??
        const <CircleSummary>[];

    return Container(
      width: width,
      color: colorScheme.surfaceContainerHigh,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          CircleRailItem(
            tooltip: 'Chats',
            onTap: () => context.go(ChatsScreen.path),
            child: const Icon(Icons.chat_bubble_outline),
          ),
          Center(
            child: Container(
              width: 32,
              height: 2,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          for (final circle in circles)
            CircleRailItem(
              key: ValueKey('circle-rail-${circle.id}'),
              tooltip: circle.name,
              selected: circle.id == selectedCircleId,
              onTap: () => context.go('${CirclesScreen.path}/${circle.id}'),
              image: circle.avatarUrl == null
                  ? null
                  : NetworkImage(circle.avatarUrl!),
              child: Text(_initials(circle.name)),
            ),
          CircleRailItem(
            tooltip: 'Create Circle',
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => const CircleCreationSheet(),
            ),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class CircleRailItem extends StatefulWidget {
  const CircleRailItem({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.image,
    super.key,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final ImageProvider? image;

  @override
  State<CircleRailItem> createState() => _CircleRailItemState();
}

class _CircleRailItemState extends State<CircleRailItem> {
  static const _duration = Duration(milliseconds: 150);

  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = widget.selected || _hovered;
    final pillHeight = widget.selected ? 40.0 : (_hovered ? 20.0 : 0.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              child: AnimatedContainer(
                duration: _duration,
                curve: Curves.easeOut,
                width: 4,
                height: pillHeight,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: widget.tooltip,
              preferBelow: false,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: AnimatedContainer(
                    duration: _duration,
                    curve: Curves.easeOut,
                    width: 48,
                    height: 48,
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(active ? 16 : 24),
                      image: widget.image == null
                          ? null
                          : DecorationImage(
                              image: widget.image!,
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: widget.image != null
                        ? null
                        : IconTheme.merge(
                            data: IconThemeData(
                              color: active
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                            ),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                              ),
                              child: widget.child,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}
