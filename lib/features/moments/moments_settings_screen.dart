import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> Moments.
void openMomentsSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => const MomentsSettingsScreen(),
    ),
  );
}

/// The "Moments" row of Settings, opening [MomentsSettingsScreen].
class MomentsSettingsRow extends ConsumerWidget {
  const MomentsSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsRow(
      key: const ValueKey('moments-settings-tile'),
      icon: Icons.auto_awesome_motion_outlined,
      title: tr('Moments'),
      subtitle: tr('Who sees your Moments and whose you see'),
      onTap: () => openMomentsSettings(context),
    );
  }
}

/// Settings -> Moments: how far back friends see older posts, and the
/// friends you hide your Moments from or whose Moments you hide.
class MomentsSettingsScreen extends ConsumerWidget {
  const MomentsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final settings = ref.watch(momentsSettingsProvider).value;
    final prefs =
        ref.watch(momentsFriendPrefsProvider).value ??
        const <MomentsFriendPref>[];
    final hiddenFromCount = prefs.where((pref) => pref.hideMine).length;
    final hiddenCount = prefs.where((pref) => pref.hideTheirs).length;
    return SettingsPage(
      key: const ValueKey('moments-settings-screen'),
      title: tr('Moments'),
      children: [
        const SizedBox(height: 12),
        SettingsGroup(
          header: tr('Your Moments'),
          children: [
            SettingsRow(
              key: const ValueKey('moments-range-row'),
              icon: Icons.history_rounded,
              title: tr('Visible range'),
              subtitle: tr('How far back friends can see your Moments'),
              value: (settings?.range ?? MomentsRange.all).label,
              onTap: () => unawaited(
                _chooseRange(context, ref, settings?.range ?? MomentsRange.all),
              ),
            ),
            SettingsRow(
              key: const ValueKey('moments-hide-mine-row'),
              icon: Icons.visibility_off_outlined,
              title: tr("Don't let them see my Moments"),
              value: hiddenFromCount == 0 ? null : '$hiddenFromCount',
              onTap: () => unawaited(
                _chooseFriends(context, ref, hideMine: true, prefs: prefs),
              ),
            ),
          ],
        ),
        SettingsGroup(
          header: tr("Friends' Moments"),
          children: [
            SettingsRow(
              key: const ValueKey('moments-hide-theirs-row'),
              icon: Icons.do_not_disturb_on_outlined,
              title: tr('Hide their Moments'),
              value: hiddenCount == 0 ? null : '$hiddenCount',
              onTap: () => unawaited(
                _chooseFriends(context, ref, hideMine: false, prefs: prefs),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
          child: Text(
            tr(
              "Friends you hide your Moments from can't see any of them, and they are not told. Hiding their Moments only removes them from your feed; you can still open their page.",
            ),
            style: TextStyle(fontSize: 12.5, height: 1.45, color: c.subtle),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseRange(
    BuildContext context,
    WidgetRef ref,
    MomentsRange current,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await showOptionPicker<MomentsRange>(
      context,
      title: tr('Visible range'),
      selected: current,
      note: tr(
        'Older Moments stay yours but friends can no longer see them. You always see all of your own.',
      ),
      options: [
        for (final range in MomentsRange.values)
          PickerOption(value: range, title: range.label),
      ],
    );
    if (picked == null || picked == current) {
      return;
    }
    try {
      await ref.read(momentsRepositoryProvider).setRange(picked);
      ref.invalidate(momentsSettingsProvider);
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(couldNotSaveText())));
    }
  }

  Future<void> _chooseFriends(
    BuildContext context,
    WidgetRef ref, {
    required bool hideMine,
    required List<MomentsFriendPref> prefs,
  }) async {
    final friends = await ref.read(friendsProvider.future);
    if (!context.mounted) {
      return;
    }
    final current = {
      for (final pref in prefs)
        if (hideMine ? pref.hideMine : pref.hideTheirs) pref.friendId,
    };
    final chosen = await showWeCordSheet<Set<String>>(
      context,
      title: hideMine
          ? tr("Don't let them see my Moments")
          : tr('Hide their Moments'),
      detents: const [0.6, 0.94],
      initialDetent: 0.94,
      builder: (context, scroll) => _FriendsPickerSheet(
        friends: friends,
        initial: current,
        scroll: scroll,
        note: hideMine
            ? tr('They will not see your Moments, and they are not told.')
            : tr('Their Moments will not show in your feed.'),
      ),
    );
    if (chosen == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(momentsRepositoryProvider);
    try {
      for (final id in chosen.difference(current)) {
        await repository.setFriendPref(
          id,
          hideMine: hideMine ? true : null,
          hideTheirs: hideMine ? null : true,
        );
      }
      for (final id in current.difference(chosen)) {
        await repository.setFriendPref(
          id,
          hideMine: hideMine ? false : null,
          hideTheirs: hideMine ? null : false,
        );
      }
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(couldNotSaveText())));
    }
    ref
      ..invalidate(momentsFriendPrefsProvider)
      ..invalidate(momentsUnseenProvider);
  }
}

class _FriendsPickerSheet extends StatefulWidget {
  const _FriendsPickerSheet({
    required this.friends,
    required this.initial,
    required this.note,
    this.scroll,
  });

  final List<Profile> friends;
  final Set<String> initial;
  final String note;
  final ScrollController? scroll;

  @override
  State<_FriendsPickerSheet> createState() => _FriendsPickerSheetState();
}

class _FriendsPickerSheetState extends State<_FriendsPickerSheet> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
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
                    widget.note,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                ),
                FriendCheckList(
                  friends: widget.friends,
                  selected: _selected,
                  keyPrefix: 'moments-pref',
                  onToggle: (friend) => setState(() {
                    if (!_selected.remove(friend.id)) {
                      _selected.add(friend.id);
                    }
                  }),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: WeCordButton(
              key: const ValueKey('moments-pref-done'),
              label: tr('Done'),
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_selected),
            ),
          ),
        ],
      ),
    );
  }
}
