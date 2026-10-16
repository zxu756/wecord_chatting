import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/discovery/discovery_screen.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

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
      ref.watch(conversationsProvider).value ?? const <ConversationSummary>[];
  var count = 0;
  for (final conversation in conversations) {
    if (conversation.isDirectMessage && !conversation.isMuted) {
      count += conversation.unreadCount;
    }
  }
  return count;
});

/// The app's main navigation down the left edge: Messages (direct messages
/// and friends) on top, a short divider, the user's circles as squircles,
/// then adding a circle and exploring. Messages fills with ink while open;
/// a pill on the left edge marks the open circle (30 tall), unread circles
/// (8) and the one under the pointer (20). Mentions show a red count; muted
/// circles are dimmed and lose the unread pill but keep their mentions.
///
/// Phones ([phone]) use a 68 wide rail with 46 items; desktop a 72 wide
/// rail with 44 items that keeps the macOS traffic lights clear.
class CircleRail extends ConsumerWidget {
  const CircleRail({
    this.selectedCircleId,
    this.homeSelected = false,
    this.exploreSelected = false,
    this.showVoiceIndicator = false,
    this.onOpenVoice,
    this.color,
    this.itemColor,
    this.padding,
    this.phone = false,
    super.key,
  });

  static const width = WeCordSizes.railDesktop;
  static const phoneWidth = WeCordSizes.railPhone;

  /// The rail's background; tokens.colors.rail by default.
  final Color? color;

  /// The background of the Messages, add and explore items while not
  /// selected; tokens.colors.railItem by default.
  final Color? itemColor;

  /// Space around the items, e.g. for the status bar on phones. By default
  /// room for the traffic lights in the macOS app, else a small gap.
  final EdgeInsetsGeometry? padding;

  final String? selectedCircleId;

  /// Whether Home (direct messages, friends, notifications) is open.
  final bool homeSelected;

  /// Whether Explore (public circles) is open.
  final bool exploreSelected;

  /// Shows the current call's controls at the bottom, for pages without a
  /// sidebar (which would show the voice panel instead).
  final bool showVoiceIndicator;

  /// Opens the voice channel of the current call.
  final ValueChanged<VoiceSession>? onOpenVoice;

  /// The phone rail: narrower, with bigger items.
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final circles =
        ref.watch(circleSummariesProvider).value ?? const <CircleSummary>[];
    final directUnread = ref.watch(directUnreadCountProvider);
    final background = color ?? c.rail;
    final itemFill = itemColor ?? c.railItem;
    final itemSize = phone ? 46.0 : 44.0;
    final railWidth = phone ? phoneWidth : width;

    CircleRailItem item({
      required Key key,
      required String tooltip,
      required VoidCallback onTap,
      required Widget avatar,
      bool selected = false,
      bool unread = false,
      int mentionCount = 0,
      bool muted = false,
      bool showPill = true,
    }) => CircleRailItem(
      key: key,
      tooltip: tooltip,
      onTap: onTap,
      selected: selected,
      unread: unread,
      mentionCount: mentionCount,
      muted: muted,
      size: itemSize,
      railWidth: railWidth,
      badgeBorderColor: background,
      badgeOnTop: phone,
      showPill: showPill,
      child: avatar,
    );

    return Container(
      key: const ValueKey('circle-rail'),
      width: railWidth,
      color: background,
      child: ListView(
        padding:
            padding ??
            EdgeInsets.only(top: drawsUnderMacosTitleBar ? 50 : 14, bottom: 96),
        children: [
          item(
            key: const ValueKey('circle-rail-home'),
            tooltip: tr('Direct messages'),
            selected: homeSelected,
            // On phones the ink fill alone marks Messages as open.
            showPill: !phone,
            mentionCount: directUnread,
            onTap: () => context.go(HomeScreen.path),
            avatar: ThingAvatar(
              size: itemSize,
              icon: Icons.chat_bubble_outline_rounded,
              color: homeSelected ? c.ink : itemFill,
              foregroundColor: homeSelected ? c.onInk : c.ink,
            ),
          ),
          Center(
            child: Container(
              width: 24,
              height: 2,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: c.track,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          for (final circle in circles)
            item(
              key: ValueKey('circle-rail-${circle.id}'),
              tooltip: circle.name,
              selected: circle.id == selectedCircleId,
              unread: circle.unreadCount > 0,
              mentionCount: circle.mentionCount,
              muted: circle.isMuted,
              onTap: () => context.go('${CircleRoutes.path}/${circle.id}'),
              avatar: ThingAvatar(
                label: circle.name,
                size: itemSize,
                image: circle.avatarUrl == null
                    ? null
                    : NetworkImage(circle.avatarUrl!),
              ),
            ),
          item(
            key: const ValueKey('circle-rail-add'),
            tooltip: tr('Add a circle'),
            onTap: () => showAddCircleSheet(context),
            avatar: ThingAvatar(
              size: itemSize,
              icon: Icons.add_rounded,
              color: itemFill,
              foregroundColor: c.successText,
            ),
          ),
          item(
            key: const ValueKey('circle-rail-explore'),
            tooltip: tr('Explore circles'),
            selected: exploreSelected,
            showPill: !phone,
            onTap: () => openPage(context, DiscoveryScreen.path),
            avatar: ThingAvatar(
              size: itemSize,
              icon: exploreSelected ? Icons.explore : Icons.explore_outlined,
              color: exploreSelected ? c.ink : itemFill,
              foregroundColor: exploreSelected ? c.onInk : c.ink,
            ),
          ),
          if (showVoiceIndicator)
            Center(child: VoiceRailIndicator(onOpen: onOpenVoice)),
        ],
      ),
    );
  }
}

/// One rail entry: [child] (usually a ThingAvatar of [size]) centred in
/// the rail, the selection pill on the rail's left edge and a red mention
/// count on a corner. Hover tints nothing but grows the pill; presses
/// scale; tooltips name it.
class CircleRailItem extends StatelessWidget {
  const CircleRailItem({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.unread = false,
    this.mentionCount = 0,
    this.muted = false,
    this.size = 44,
    this.railWidth = CircleRail.width,
    this.badgeBorderColor,
    this.badgeOnTop = false,
    this.showPill = true,
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

  final double size;
  final double railWidth;

  /// Ring cut around the mention badge: the rail's background.
  final Color? badgeBorderColor;

  /// The mention badge on the top-right corner (phones) instead of the
  /// bottom right.
  final bool badgeOnTop;

  /// Whether selection shows the pill (Messages on phones shows its fill).
  final bool showPill;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onTap,
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: selected,
      pressedScale: 0.94,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(size / 3),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        final pillHeight = selected && showPill
            ? 30.0
            : hovered && !selected
            ? 20.0
            : (unread && !muted && !selected ? 8.0 : 0.0);
        final dimmed = muted && !selected && !hovered;
        Widget avatar = Opacity(
          key: const ValueKey('circle-rail-icon'),
          opacity: dimmed ? 0.4 : 1,
          child: child,
        );
        if (mentionCount > 0) {
          final badge = IgnorePointer(
            child: KeyedSubtree(
              key: const ValueKey('circle-mention-badge'),
              child: CountBadge(
                count: mentionCount,
                size: 18,
                ringColor: badgeBorderColor ?? c.rail,
              ),
            ),
          );
          avatar = Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              if (badgeOnTop)
                Positioned(right: -6, top: -6, child: badge)
              else
                Positioned(right: -6, bottom: -6, child: badge),
            ],
          );
        }
        return SizedBox(
          width: railWidth,
          height: size + 10,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                child: AnimatedContainer(
                  key: const ValueKey('circle-rail-pill'),
                  duration: WeCordMotion.durationOf(context, WeCordMotion.base),
                  curve: WeCordMotion.standard,
                  width: 4,
                  height: pillHeight,
                  decoration: BoxDecoration(
                    color: c.ink,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              avatar,
            ],
          ),
        );
      },
    );
  }
}
