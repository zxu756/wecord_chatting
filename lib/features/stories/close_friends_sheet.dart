import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Edits the close friends list: the friends who see the dailies posted to
/// "Close friends". Returns true once it was saved.
Future<bool?> showCloseFriendsSheet(BuildContext context) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Close friends'),
    detents: const [0.62, 0.94],
    initialDetent: 0.94,
    useRootNavigator: true,
    builder: (_, scroll) => CloseFriendsSheet(scroll: scroll),
  );
}

class CloseFriendsSheet extends ConsumerStatefulWidget {
  const CloseFriendsSheet({this.scroll, super.key});

  final ScrollController? scroll;

  @override
  ConsumerState<CloseFriendsSheet> createState() => _CloseFriendsSheetState();
}

class _CloseFriendsSheetState extends ConsumerState<CloseFriendsSheet> {
  Set<String>? _selected;
  var _saving = false;
  String? _error;

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(storiesRepositoryProvider).setCloseFriends(selected);
      ref.invalidate(closeFriendsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not save the list. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final saved = ref.watch(closeFriendsProvider);
    final selected = _selected ??= saved.value == null
        ? null
        : {...saved.value!};
    final ready = selected != null;
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
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                  child: Text(
                    tr(
                      'Only the friends you choose see a daily shared with '
                      'close friends. They are not told about the list.',
                    ),
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                ),
                if (!ready)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  FriendCheckList(
                    friends: friends,
                    selected: selected,
                    keyPrefix: 'close-friend',
                    emptyText: tr('You have no friends to choose from yet.'),
                    onToggle: (friend) => setState(() {
                      if (!selected.remove(friend.id)) {
                        selected.add(friend.id);
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      key: const ValueKey('close-friends-error'),
                      style: TextStyle(fontSize: 13.5, color: c.dangerText),
                    ),
                  ),
                WeCordButton(
                  key: const ValueKey('close-friends-save'),
                  label: selected == null || selected.isEmpty
                      ? tr('Save')
                      : tr('Save ({count})', {'count': selected.length}),
                  size: WeCordButtonSize.large,
                  expand: true,
                  loading: _saving,
                  onPressed: ready && !_saving ? _save : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
