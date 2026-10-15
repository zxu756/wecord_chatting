import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

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

/// Unread messages in direct and group chats that are not muted, for the
/// rail's Home badge.
final directUnreadCountProvider = Provider.autoDispose<int>((ref) {
  final conversations =
      ref.watch(conversationsProvider).valueOrNull ??
      const <ConversationSummary>[];
  var count = 0;
  for (final conversation in conversations) {
    if (conversation.isDirectMessage && !conversation.isMuted) {
      count += conversation.unreadCount;
    }
  }
  return count;
});

/// The app's main navigation, modelled on a server switcher: Home (direct
/// messages and friends) on top, then the user's circles, then adding a
/// circle and exploring. Icons morph from a circle to a rounded square and
/// grow a left pill when hovered or selected. Circles with unread messages
/// show a short pill and a red badge for mentions; muted circles are dimmed
/// without the pill but keep the mention badge.
class CircleRail extends ConsumerWidget {
  const CircleRail({
    this.selectedCircleId,
    this.homeSelected = false,
    this.showVoiceIndicator = false,
    this.onOpenVoice,
    this.color,
    this.itemColor,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
    super.key,
  });

  static const width = 72.0;

  /// The rail's background; surfaceContainerHigh by default.
  final Color? color;

  /// The background of items that are neither selected nor hovered;
  /// surfaceContainerLowest by default.
  final Color? itemColor;

  /// Space around the items, e.g. for the status bar on phones.
  final EdgeInsetsGeometry padding;

  final String? selectedCircleId;

  /// Whether Home (direct messages, friends, notifications) is open.
  final bool homeSelected;

  /// Shows the current call's controls at the bottom, for pages without a
  /// sidebar (which would show the voice panel instead).
  final bool showVoiceIndicator;

  /// Opens the voice channel of the current call.
  final ValueChanged<VoiceSession>? onOpenVoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final circles =
        ref.watch(circleSummariesProvider).valueOrNull ??
        const <CircleSummary>[];
    final directUnread = ref.watch(directUnreadCountProvider);
    final background = color ?? colorScheme.surfaceContainerHigh;

    return Container(
      key: const ValueKey('circle-rail'),
      width: width,
      color: background,
      child: ListView(
        padding: padding,
        children: [
          CircleRailItem(
            key: const ValueKey('circle-rail-home'),
            tooltip: tr('Direct messages'),
            selected: homeSelected,
            color: itemColor,
            badgeBorderColor: background,
            mentionCount: directUnread,
            onTap: () => context.go(HomeScreen.path),
            child: const Icon(Icons.forum_outlined),
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
              color: itemColor,
              badgeBorderColor: background,
              unread: circle.unreadCount > 0,
              mentionCount: circle.mentionCount,
              muted: circle.isMuted,
              onTap: () => context.go('${CircleRoutes.path}/${circle.id}'),
              image: circle.avatarUrl == null
                  ? null
                  : NetworkImage(circle.avatarUrl!),
              child: Text(_initials(circle.name)),
            ),
          CircleRailItem(
            key: const ValueKey('circle-rail-add'),
            tooltip: tr('Add a circle'),
            color: itemColor,
            badgeBorderColor: background,
            onTap: () => showAddCircleSheet(context),
            child: const Icon(Icons.add),
          ),
          CircleRailItem(
            key: const ValueKey('circle-rail-explore'),
            tooltip: tr('Search and explore'),
            color: itemColor,
            badgeBorderColor: background,
            onTap: () => openPage(context, GlobalMessageSearchScreen.path),
            child: const Icon(Icons.explore_outlined),
          ),
          if (showVoiceIndicator)
            Center(child: VoiceRailIndicator(onOpen: onOpenVoice)),
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
    this.color,
    this.badgeBorderColor,
    super.key,
  });

  /// Background while neither selected nor hovered; surfaceContainerLowest
  /// by default.
  final Color? color;

  /// Outline of the mention badge, the rail's background.
  final Color? badgeBorderColor;

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
                            : widget.color ??
                                  colorScheme.surfaceContainerLowest,
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
                    borderColor:
                        widget.badgeBorderColor ??
                        colorScheme.surfaceContainerHigh,
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
