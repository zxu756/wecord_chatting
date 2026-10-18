import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "3 mutual friends" for a request card: how many friends the person asking
/// and I have in common. Nothing while loading, when there are none, or when
/// their profile keeps it from me.
class MutualCountLine extends ConsumerWidget {
  const MutualCountLine({
    required this.userId,
    this.style,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String userId;
  final TextStyle? style;

  /// Space around the line when it shows.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(mutualFriendCountProvider(userId)).value ?? 0;
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    return Padding(
      padding: padding,
      child: Text(
        mutualFriendsLabel(count),
        key: ValueKey('mutual-count-$userId'),
        style: style ?? TextStyle(fontSize: 13, color: c.muted),
      ),
    );
  }
}

/// "1 mutual friend" / "3 mutual friends".
String mutualFriendsLabel(int count) => count == 1
    ? tr('1 mutual friend')
    : tr('{count} mutual friends', {'count': count});

/// "1 mutual group" / "2 mutual groups".
String mutualGroupsLabel(int count) => count == 1
    ? tr('1 mutual group')
    : tr('{count} mutual groups', {'count': count});

/// "1 mutual circle" / "2 mutual circles".
String mutualCirclesLabel(int count) => count == 1
    ? tr('1 mutual circle')
    : tr('{count} mutual circles', {'count': count});

/// What the profile card shows beyond the profile summary: the numbers of
/// mutual friends, groups and circles (and the groups' names for a friend),
/// how the two became friends, the birthday and the support links. Each part
/// is left out when there is nothing to show; the support links are hidden on
/// iPhone ([supportLinksAvailable]).
class ProfileInsightsBlocks extends ConsumerWidget {
  const ProfileInsightsBlocks({
    required this.userId,
    this.onOpenGroup,
    this.linksAvailable,
    super.key,
  });

  final String userId;

  /// Opens a mutual group chat.
  final ValueChanged<MutualItem>? onOpenGroup;

  /// Overrides [supportLinksAvailable] (tests).
  final bool? linksAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights =
        ref.watch(profileInsightsProvider(userId)).value ??
        ProfileInsights.empty;
    final mutuals = insights.mutuals;
    final showLinks =
        (linksAvailable ?? supportLinksAvailable()) &&
        insights.links.isNotEmpty;
    final birthday = insights.birthday;
    final source = insights.source;
    if (mutuals.isEmpty && birthday == null && source == null && !showLinks) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final counts = [
      if (mutuals.friendCount > 0) mutualFriendsLabel(mutuals.friendCount),
      if (mutuals.groupCount > 0) mutualGroupsLabel(mutuals.groupCount),
      if (mutuals.circleCount > 0) mutualCirclesLabel(mutuals.circleCount),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: const ValueKey('profile-insights'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: c.well,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (counts.isNotEmpty)
              _InfoRow(
                key: const ValueKey('profile-mutual-counts'),
                label: tr('In common'),
                value: counts.join(' · '),
              ),
            for (final group in mutuals.groups)
              _InfoRow(
                key: ValueKey('profile-mutual-group-${group.id}'),
                label: tr('Group chat'),
                value: group.title.isEmpty ? tr('Group') : group.title,
                onTap: onOpenGroup == null ? null : () => onOpenGroup!(group),
              ),
            if (source != null)
              _InfoRow(
                key: const ValueKey('profile-source'),
                label: tr('Source'),
                value: source.label,
              ),
            if (birthday != null)
              _InfoRow(
                key: const ValueKey('profile-birthday'),
                label: tr('Birthday'),
                value: birthday.label,
              ),
            if (showLinks) SupportLinksList(links: insights.links),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return WeCordPressable(
      onPressed: onTap,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) => row,
    );
  }
}

/// A profile's support links as rows: the platform's icon and name (or the
/// owner's label), tapping asks "You are leaving WeCord" and opens the page.
class SupportLinksList extends StatelessWidget {
  const SupportLinksList({required this.links, super.key});

  final List<SupportLink> links;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      key: const ValueKey('profile-support-links'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Semantics(
            header: true,
            child: Text(
              trIn('support-links', 'Support'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.subtle,
              ),
            ),
          ),
        ),
        for (final (index, link) in links.indexed)
          WeCordPressable(
            key: ValueKey('support-link-$index'),
            onPressed: () => openSupportLink(context, link.url),
            semanticLabel: tr('{name}, opens a page outside WeCord', {
              'name': link.title,
            }),
            excludeSemantics: true,
            pressedScale: 0.99,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            builder: (context, states) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Icon(link.icon, size: 20, color: c.ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      link.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.open_in_new_rounded, size: 16, color: c.faint),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
