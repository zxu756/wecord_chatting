import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_creation_sheet.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/shared/models/circle.dart';

final circleSummariesProvider = FutureProvider.autoDispose<List<CircleSummary>>(
  (ref) {
    // Unread counts change whenever the conversation list does (new messages,
    // reads), so follow it instead of opening another realtime channel.
    ref.listen(conversationsProvider, (previous, next) {
      if (previous != null && previous.hasValue && next is AsyncData) {
        ref.invalidateSelf();
      }
    });
    return ref.watch(circlesRepositoryProvider).listCircles();
  },
);

/// Vertical strip of circle icons, modelled on a server switcher: icons morph
/// from a circle to a rounded square and grow a left pill when hovered or
/// selected. Circles with unread messages show a short pill and a red badge
/// for mentions; muted circles are dimmed without the pill but keep the
/// mention badge.
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
              unread: circle.unreadCount > 0,
              mentionCount: circle.mentionCount,
              muted: circle.isMuted,
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
              useSafeArea: true,
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
    this.unread = false,
    this.mentionCount = 0,
    this.muted = false,
    this.image,
    super.key,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;

  /// Shows a short pill while neither selected nor hovered.
  final bool unread;

  /// Shown as a red count badge on the icon.
  final int mentionCount;

  /// Muted items are dimmed and never show the unread pill, but still show
  /// the mention badge.
  final bool muted;
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
    final pillHeight = widget.selected
        ? 40.0
        : _hovered
        ? 20.0
        : (widget.unread && !widget.muted ? 8.0 : 0.0);
    final dimmed = widget.muted && !active;

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
                key: const ValueKey('circle-rail-pill'),
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
            Opacity(
              key: const ValueKey('circle-rail-icon'),
              opacity: dimmed ? 0.4 : 1,
              child: Tooltip(
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
            ),
            if (widget.mentionCount > 0)
              Positioned(
                right: 8,
                bottom: 0,
                child: IgnorePointer(
                  child: CircleMentionBadge(
                    count: widget.mentionCount,
                    borderColor: colorScheme.surfaceContainerHigh,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Red count of unread mentions, capped at 99+.
class CircleMentionBadge extends StatelessWidget {
  const CircleMentionBadge({required this.count, this.borderColor, super.key});

  final int count;

  /// Outline that separates the badge from the icon underneath.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = this.borderColor;
    return Container(
      key: const ValueKey('circle-mention-badge'),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: colorScheme.error,
        borderRadius: BorderRadius.circular(11),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor, width: 3),
      ),
      // Centred inside the minimum size without growing to fill the parent.
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            color: colorScheme.onError,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
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
