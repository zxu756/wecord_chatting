import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/friend_tags/friend_tags_screen.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Who can see a Moment: everyone, only the person, or lists of friends and
/// tags to share with or hide from. Resolves to the choice, or null when
/// dismissed.
Future<MomentAudience?> showMomentAudienceSheet(
  BuildContext context, {
  required MomentAudience current,
}) {
  return showWeCordSheet<MomentAudience>(
    context,
    title: tr('Who can see this'),
    detents: const [0.62, 0.94],
    initialDetent: 0.94,
    builder: (context, scrollController) =>
        MomentAudienceSheet(current: current, scroll: scrollController),
  );
}

class MomentAudienceSheet extends ConsumerStatefulWidget {
  const MomentAudienceSheet({required this.current, this.scroll, super.key});

  final MomentAudience current;
  final ScrollController? scroll;

  @override
  ConsumerState<MomentAudienceSheet> createState() =>
      _MomentAudienceSheetState();
}

class _MomentAudienceSheetState extends ConsumerState<MomentAudienceSheet> {
  late MomentVisibility _visibility;
  late Set<String> _friendIds;
  late Set<String> _tagIds;

  @override
  void initState() {
    super.initState();
    _visibility = widget.current.visibility;
    _friendIds = {...widget.current.friendIds};
    _tagIds = {...widget.current.tagIds};
  }

  MomentAudience get _audience => MomentAudience(
    visibility: _visibility,
    friendIds: _friendIds,
    tagIds: _tagIds,
  );

  void _choose(MomentVisibility visibility) {
    WeCordHaptics.selection();
    setState(() => _visibility = visibility);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final tags = ref.watch(friendTagsProvider).value ?? const FriendTagsData();
    final listMode = _audience.usesLists;
    final verb = _visibility == MomentVisibility.only
        ? tr('Only share with')
        : tr("Don't share with");

    Widget option(
      MomentVisibility value,
      IconData icon,
      String title,
      String subtitle,
    ) {
      final selected = _visibility == value;
      return Semantics(
        selected: selected,
        child: SettingsRow(
          key: ValueKey('audience-${value.name}'),
          icon: icon,
          tone: selected ? SettingsTone.accent : SettingsTone.neutral,
          title: title,
          subtitle: subtitle,
          trailing: CheckCircle(checked: selected),
          onTap: () => _choose(value),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                SettingsGroup(
                  color: c.well,
                  separatorIndent: 58,
                  children: [
                    option(
                      MomentVisibility.friends,
                      Icons.group_outlined,
                      tr('Friends'),
                      tr('All your friends'),
                    ),
                    option(
                      MomentVisibility.private,
                      Icons.lock_outline_rounded,
                      tr('Only me'),
                      tr('Private, nobody else sees it'),
                    ),
                    option(
                      MomentVisibility.only,
                      Icons.person_add_alt_1_outlined,
                      tr('Only share with'),
                      tr('Choose friends and tags'),
                    ),
                    option(
                      MomentVisibility.except,
                      Icons.person_off_outlined,
                      tr("Don't share with"),
                      tr('Everyone but the friends and tags you choose'),
                    ),
                  ],
                ),
                if (listMode) ...[
                  SettingsSectionHeader(tr('Tags')),
                  if (tags.tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                      child: Text(
                        tr(
                          'You have no tags yet. Make some from the Friends page.',
                        ),
                        style: TextStyle(fontSize: 13.5, color: c.muted),
                      ),
                    )
                  else
                    SettingsGroup(
                      color: c.well,
                      separatorIndent: 14,
                      children: [
                        for (final tag in tags.tags)
                          Semantics(
                            checked: _tagIds.contains(tag.id),
                            child: SettingsRow(
                              key: ValueKey('audience-tag-${tag.id}'),
                              icon: Icons.sell_outlined,
                              tone: SettingsTone.accent,
                              title: tag.name,
                              value: friendCountLabel(
                                tags.membersOf(tag.id).length,
                              ),
                              trailing: CheckCircle(
                                checked: _tagIds.contains(tag.id),
                              ),
                              onTap: () => setState(() {
                                WeCordHaptics.selection();
                                if (!_tagIds.remove(tag.id)) {
                                  _tagIds.add(tag.id);
                                }
                              }),
                            ),
                          ),
                      ],
                    ),
                  SettingsSectionHeader(tr('Friends')),
                  FriendCheckList(
                    friends: friends,
                    selected: _friendIds,
                    keyPrefix: 'audience-friend',
                    onToggle: (friend) => setState(() {
                      if (!_friendIds.remove(friend.id)) {
                        _friendIds.add(friend.id);
                      }
                    }),
                  ),
                ],
              ],
            ),
          ),
          // The button stays in reach however long the list is.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (listMode && !_audience.isComplete)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    child: Text(
                      tr('{action}: choose at least one friend or tag.', {
                        'action': verb,
                      }),
                      key: const ValueKey('audience-incomplete'),
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                WeCordButton(
                  key: const ValueKey('audience-done'),
                  label: tr('Done'),
                  size: WeCordButtonSize.large,
                  expand: true,
                  onPressed: _audience.isComplete
                      ? () => Navigator.of(context).pop(_audience)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The names for an audience's summary line, from the person's tags and
/// friends.
String audienceSummary(
  MomentAudience audience, {
  required FriendTagsData tags,
  required List<Profile> friends,
}) {
  return momentAudienceLabel(
    audience,
    tagNames: [
      for (final id in audience.tagIds)
        if (tags.tagById(id) case final tag?) tag.name,
    ],
    friendNames: [
      for (final friend in friends)
        if (audience.friendIds.contains(friend.id)) friend.displayLabel,
    ],
  );
}
