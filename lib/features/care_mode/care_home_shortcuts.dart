import 'package:flutter/material.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The phone home's shortcuts while Care mode's simple home is on: Friends and
/// Moments as two big tiles under the title (Messages is the page itself).
/// They take the place of the row of small shortcuts.
class CareHomeShortcuts extends StatelessWidget {
  const CareHomeShortcuts({required this.requestCount, super.key});

  /// Friend requests waiting, shown on the Friends tile.
  final int requestCount;

  static const friendsKey = ValueKey('care-home-friends');
  static const momentsKey = ValueKey('care-home-moments');

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final friends = CareHomeTile(
      key: friendsKey,
      icon: Icons.people_alt_outlined,
      label: tr('Friends'),
      semanticLabel: requestCount > 0
          ? tr('Friends · {count} requests', {'count': requestCount})
          : null,
      badge: requestCount > 0
          ? CountBadge(
              key: const ValueKey('care-home-friend-requests-badge'),
              count: requestCount,
              size: 24,
              tone: BadgeTone.mention,
              ringColor: c.raised,
            )
          : null,
      onPressed: () => openPage(context, ContactsScreen.path),
    );
    final moments = CareHomeTile(
      key: momentsKey,
      icon: Icons.auto_awesome_motion_outlined,
      label: tr('Moments'),
      badge: MomentsUnseenAvatar(ringColor: c.raised, size: 28),
      onPressed: () => openPage(context, MomentsScreen.path),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: LayoutBuilder(
        builder: (context, box) {
          // At very large text the tiles stack instead of squeezing.
          final stacked =
              MediaQuery.textScalerOf(context).scale(10) / 10 > 1.7 ||
              box.maxWidth < 300;
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [friends, const SizedBox(height: 12), moments],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: friends),
                      const SizedBox(width: 12),
                      Expanded(child: moments),
                    ],
                  ),
                );
        },
      ),
    );
  }
}

/// One big tile of the Care home: an icon, a label and an optional badge on
/// the icon's corner.
class CareHomeTile extends StatelessWidget {
  const CareHomeTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final Widget? badge;
  final String? semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) => Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: ShapeDecoration(
          color: states.contains(WidgetState.pressed)
              ? c.raisedStrong
              : c.raised,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 34, color: c.ink),
                if (badge != null)
                  Positioned(right: -12, top: -12, child: badge!),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.ink,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
