import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The words for a problem with a tag name.
String friendTagNameProblemText(FriendTagNameProblem problem) {
  return switch (problem) {
    FriendTagNameProblem.empty => tr('Give the tag a name.'),
    FriendTagNameProblem.tooLong => tr(
      'Tag names can have up to {count} characters.',
      {'count': maxFriendTagNameLength},
    ),
    FriendTagNameProblem.taken => tr('You already have a tag with that name.'),
  };
}

/// "No friends" / "1 friend" / "3 friends".
String friendCountLabel(int count) {
  return switch (count) {
    0 => tr('No friends'),
    1 => tr('1 friend'),
    _ => tr('{count} friends', {'count': count}),
  };
}

/// Tags: the person's private groups of friends. Make, rename and delete
/// them, and choose who is in each. Nobody else sees any of it.
class FriendTagsScreen extends ConsumerWidget {
  const FriendTagsScreen({super.key});

  static const path = '/tags';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final data = ref.watch(friendTagsProvider);
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: tr('Tags'),
                  actions: [
                    WeCordButton(
                      key: const ValueKey('tags-new'),
                      label: tr('New tag'),
                      icon: Icons.add_rounded,
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.accent,
                      onPressed: () => unawaited(
                        showFriendTagEditor(context, friends: friends),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: data.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: WeCordButton(
                        label: tr('Try again'),
                        onPressed: () => ref.invalidate(friendTagsProvider),
                      ),
                    ),
                    data: (data) => ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                          child: Text(
                            tr(
                              'Tags are private. Group friends to filter your friends list and to choose who sees a Moment.',
                            ),
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: c.muted,
                            ),
                          ),
                        ),
                        if (data.tags.isEmpty)
                          _EmptyTags(
                            onCreate: () => unawaited(
                              showFriendTagEditor(context, friends: friends),
                            ),
                          )
                        else
                          SettingsGroup(
                            separatorIndent: 58,
                            children: [
                              for (final tag in data.tags)
                                SettingsRow(
                                  key: ValueKey('tag-row-${tag.id}'),
                                  icon: Icons.sell_outlined,
                                  tone: SettingsTone.accent,
                                  title: tag.name,
                                  value: friendCountLabel(
                                    data.membersOf(tag.id).length,
                                  ),
                                  onTap: () => unawaited(
                                    showFriendTagEditor(
                                      context,
                                      friends: friends,
                                      tag: tag,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTags extends StatelessWidget {
  const _EmptyTags({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('tags-empty'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        children: [
          const SettingsIconTile(
            icon: Icons.sell_outlined,
            tone: SettingsTone.accent,
            size: 52,
          ),
          const SizedBox(height: 14),
          Text(
            tr('No tags yet'),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Make one for family, work or any group you like.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
          ),
          const SizedBox(height: 16),
          WeCordButton(label: tr('New tag'), onPressed: onCreate),
        ],
      ),
    );
  }
}

/// Makes a tag (when [tag] is null) or edits one: its name, its friends and
/// deleting it. Resolves to true when something changed.
Future<bool?> showFriendTagEditor(
  BuildContext context, {
  required List<Profile> friends,
  FriendTag? tag,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tag == null ? tr('New tag') : tr('Edit tag'),
    detents: const [0.6, 0.94],
    initialDetent: 0.94,
    builder: (context, scrollController) =>
        FriendTagEditor(friends: friends, tag: tag, scroll: scrollController),
  );
}

class FriendTagEditor extends ConsumerStatefulWidget {
  const FriendTagEditor({
    required this.friends,
    this.tag,
    this.scroll,
    super.key,
  });

  final List<Profile> friends;
  final FriendTag? tag;
  final ScrollController? scroll;

  @override
  ConsumerState<FriendTagEditor> createState() => _FriendTagEditorState();
}

class _FriendTagEditorState extends ConsumerState<FriendTagEditor> {
  late final TextEditingController _name;
  late Set<String> _selected;
  late final Set<String> _initial;
  FriendTagNameProblem? _problem;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.tag?.name ?? '');
    final data = ref.read(friendTagsProvider).value;
    _initial = widget.tag == null
        ? <String>{}
        : {...?data?.membersOf(widget.tag!.id)};
    _selected = {..._initial};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final data = ref.read(friendTagsProvider).value ?? const FriendTagsData();
    final others = data.tags.where((tag) => tag.id != widget.tag?.id);
    final problem = checkFriendTagName(_name.text, others);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
      _error = null;
    });
    final repository = ref.read(friendTagsRepositoryProvider);
    try {
      var tagId = widget.tag?.id;
      if (tagId == null) {
        tagId = (await repository.createTag(_name.text)).id;
      } else if (_name.text.trim() != widget.tag!.name) {
        await repository.renameTag(tagId, _name.text);
      }
      if (!setEquals(_selected, _initial)) {
        await repository.setTagMembers(tagId, _selected, current: _initial);
      }
      ref.invalidate(friendTagsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FriendTagNameException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = error.reason;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not save the tag. Try again.');
        });
      }
    }
  }

  Future<void> _delete() async {
    final tag = widget.tag!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete tag?')),
        content: Text(
          tr(
            '"{name}" is removed. Your friends stay friends, and Moments shared with this tag are no longer shared through it.',
            {'name': tag.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('tag-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(friendTagsRepositoryProvider).deleteTag(tag.id);
      ref.invalidate(friendTagsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not delete the tag. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                controller: widget.scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  WeCordTextField(
                    fieldKey: const ValueKey('tag-name-field'),
                    controller: _name,
                    label: tr('Name'),
                    hint: tr('Family, Work, Climbing…'),
                    inputFormatters: [LengthLimitingTextInputFormatter(60)],
                    errorText: _problem == null
                        ? null
                        : friendTagNameProblemText(_problem!),
                    textInputAction: TextInputAction.done,
                    autofocus: widget.tag == null,
                    onChanged: (_) {
                      if (_problem != null) {
                        setState(() => _problem = null);
                      }
                    },
                  ),
                  SettingsSectionHeader(
                    _selected.isEmpty
                        ? tr('Friends')
                        : tr('Friends · {count}', {'count': _selected.length}),
                  ),
                  FriendCheckList(
                    friends: widget.friends,
                    selected: _selected,
                    keyPrefix: 'tag-friend',
                    emptyText: tr('Add friends first, then put them in tags.'),
                    onToggle: (friend) => setState(() {
                      if (!_selected.remove(friend.id)) {
                        _selected.add(friend.id);
                      }
                    }),
                  ),
                ],
              ),
            ),
            // Save and delete stay in reach however long the list is.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Text(
                        _error!,
                        key: const ValueKey('tag-error'),
                        style: TextStyle(fontSize: 13.5, color: c.dangerText),
                      ),
                    ),
                  WeCordButton(
                    key: const ValueKey('tag-save'),
                    label: widget.tag == null ? tr('Create tag') : tr('Save'),
                    size: WeCordButtonSize.large,
                    expand: true,
                    loading: _saving,
                    onPressed: _save,
                  ),
                  if (widget.tag != null) ...[
                    const SizedBox(height: 4),
                    WeCordButton(
                      key: const ValueKey('tag-delete'),
                      label: tr('Delete tag'),
                      variant: WeCordButtonVariant.ghost,
                      expand: true,
                      onPressed: _saving ? null : _delete,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which tags a friend is in: a sheet of the person's tags to switch on and
/// off, and a field to make a new one on the spot.
Future<void> showFriendTagsPicker(
  BuildContext context, {
  required Profile friend,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Tags for {name}', {'name': friend.displayLabel}),
    builder: (context, _) => FriendTagsPicker(friend: friend),
  );
}

class FriendTagsPicker extends ConsumerStatefulWidget {
  const FriendTagsPicker({required this.friend, super.key});

  final Profile friend;

  @override
  ConsumerState<FriendTagsPicker> createState() => _FriendTagsPickerState();
}

class _FriendTagsPickerState extends ConsumerState<FriendTagsPicker> {
  final _newName = TextEditingController();
  FriendTagNameProblem? _problem;
  var _busy = false;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _toggle(FriendTagsData data, FriendTag tag) async {
    final members = {...data.membersOf(tag.id)};
    final friendId = widget.friend.id;
    final next = {...members};
    if (!next.remove(friendId)) {
      next.add(friendId);
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(friendTagsRepositoryProvider)
          .setTagMembers(tag.id, next, current: members);
      ref.invalidate(friendTagsProvider);
      await ref.read(friendTagsProvider.future);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not save the tag. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create(FriendTagsData data) async {
    final problem = checkFriendTagName(_newName.text, data.tags);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(friendTagsRepositoryProvider);
      final tag = await repository.createTag(_newName.text);
      await repository.setTagMembers(tag.id, {
        widget.friend.id,
      }, current: const {});
      _newName.clear();
      ref.invalidate(friendTagsProvider);
      await ref.read(friendTagsProvider.future);
    } on FriendTagNameException catch (error) {
      if (mounted) {
        setState(() => _problem = error.reason);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not save the tag. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final data = ref.watch(friendTagsProvider).value ?? const FriendTagsData();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.tags.isNotEmpty)
              SettingsGroup(
                color: c.well,
                separatorIndent: 14,
                children: [
                  for (final tag in data.tags)
                    Semantics(
                      checked: data
                          .membersOf(tag.id)
                          .contains(widget.friend.id),
                      child: SettingsRow(
                        key: ValueKey('picker-tag-${tag.id}'),
                        title: tag.name,
                        trailing: CheckCircle(
                          checked: data
                              .membersOf(tag.id)
                              .contains(widget.friend.id),
                        ),
                        onTap: _busy ? null : () => _toggle(data, tag),
                      ),
                    ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Text(
                  tr('No tags yet. Make the first one below.'),
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: WeCordTextField(
                    fieldKey: const ValueKey('picker-new-tag-field'),
                    controller: _newName,
                    hint: tr('New tag'),
                    prefixIcon: Icons.sell_outlined,
                    errorText: _problem == null
                        ? null
                        : friendTagNameProblemText(_problem!),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(data),
                    onChanged: (_) {
                      if (_problem != null) {
                        setState(() => _problem = null);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: WeCordIconButton(
                    key: const ValueKey('picker-new-tag-add'),
                    icon: Icons.add_rounded,
                    tooltip: tr('Add tag'),
                    variant: WeCordButtonVariant.accent,
                    onPressed: _busy ? null : () => _create(data),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
