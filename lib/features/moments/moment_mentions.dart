import 'package:flutter/material.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The friends a Moment with [audience] can remind to read it: the ones who
/// can see it. (The server decides again when the Moment is posted, with the
/// real rules: "Don't let them see my Moments", the visible range, blocks.)
List<Profile> momentMentionCandidates({
  required List<Profile> friends,
  required FriendTagsData tags,
  required MomentAudience audience,
}) {
  switch (audience.visibility) {
    case MomentVisibility.private:
      return const [];
    case MomentVisibility.friends:
    case MomentVisibility.close:
      return friends;
    case MomentVisibility.only:
    case MomentVisibility.except:
      final inTags = <String>{
        for (final tagId in audience.tagIds) ...tags.membersOf(tagId),
      };
      bool listed(Profile friend) =>
          audience.friendIds.contains(friend.id) || inTags.contains(friend.id);
      final only = audience.visibility == MomentVisibility.only;
      return [
        for (final friend in friends)
          if (listed(friend) == only) friend,
      ];
  }
}

/// [selected] without the people [candidates] no longer holds (the audience
/// changed and they cannot see the Moment now).
Set<String> keepMentionable(Set<String> selected, List<Profile> candidates) {
  final ids = {for (final friend in candidates) friend.id};
  return {
    for (final id in selected)
      if (ids.contains(id)) id,
  };
}

/// The line under "Remind who to read": the names, or how many.
String momentMentionSummary(Set<String> selected, List<Profile> friends) {
  if (selected.isEmpty) {
    return '';
  }
  final names = [
    for (final friend in friends)
      if (selected.contains(friend.id)) friend.displayLabel,
  ];
  if (names.length <= 2) {
    return names.join(', ');
  }
  return tr('{first}, {second} and {count} more', {
    'first': names[0],
    'second': names[1],
    'count': names.length - 2,
  });
}

/// Asks whom to remind. Resolves to the choice, or null when dismissed.
Future<Set<String>?> showMomentMentionSheet(
  BuildContext context, {
  required List<Profile> candidates,
  required Set<String> selected,
}) {
  return showWeCordSheet<Set<String>>(
    context,
    title: tr('Remind who to read'),
    detents: const [0.62, 0.94],
    initialDetent: 0.94,
    builder: (context, scrollController) => MomentMentionSheet(
      candidates: candidates,
      selected: selected,
      scroll: scrollController,
    ),
  );
}

class MomentMentionSheet extends StatefulWidget {
  const MomentMentionSheet({
    required this.candidates,
    required this.selected,
    this.scroll,
    super.key,
  });

  final List<Profile> candidates;
  final Set<String> selected;
  final ScrollController? scroll;

  static const doneKey = ValueKey('mention-done');
  static const limitKey = ValueKey('mention-limit');

  @override
  State<MomentMentionSheet> createState() => _MomentMentionSheetState();
}

class _MomentMentionSheetState extends State<MomentMentionSheet> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final full = _selected.length >= maxMomentMentions;
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                  child: Text(
                    tr(
                      'They get a notification. Only friends who can see this Moment are listed.',
                    ),
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                ),
                FriendCheckList(
                  friends: widget.candidates,
                  selected: _selected,
                  keyPrefix: 'mention-friend',
                  emptyText: tr('Nobody can see this Moment.'),
                  onToggle: (friend) => setState(() {
                    if (!_selected.remove(friend.id) && !full) {
                      _selected.add(friend.id);
                    }
                  }),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (full)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    child: Text(
                      tr('You can remind up to {count} friends.', {
                        'count': maxMomentMentions,
                      }),
                      key: MomentMentionSheet.limitKey,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                WeCordButton(
                  key: MomentMentionSheet.doneKey,
                  label: tr('Done'),
                  size: WeCordButtonSize.large,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(_selected),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
