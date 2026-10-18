import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/groups/group_invitations.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

class GroupCreationResult {
  const GroupCreationResult({
    required this.conversationId,
    required this.title,
    required this.memberIds,
  });

  final String conversationId;
  final String title;
  final List<String> memberIds;
}

class GroupCreationSheet extends ConsumerStatefulWidget {
  const GroupCreationSheet({required this.friends, super.key});

  final List<Profile> friends;

  @override
  ConsumerState<GroupCreationSheet> createState() => _GroupCreationSheetState();
}

class _GroupCreationSheetState extends ConsumerState<GroupCreationSheet> {
  final _titleController = TextEditingController();
  final _selectedFriendIds = <String>{};
  var _isCreating = false;
  String? _errorText;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = _titleController.text.trim();
    final canCreate =
        title.isNotEmpty && _selectedFriendIds.length >= 2 && !_isCreating;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                tr('New group'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(height: 16),
            WeCordTextField(
              controller: _titleController,
              hint: tr('Group name'),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                setState(() {});
              },
            ),
            SettingsSectionHeader(
              tr('Choose at least two friends'),
              trailing: Text(
                '${_selectedFriendIds.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.subtle,
                ),
              ),
            ),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: c.well,
                  borderRadius: BorderRadius.circular(WeCordRadii.xl),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final friend in widget.friends)
                      FriendPickerRow(
                        key: ValueKey('group-pick-${friend.id}'),
                        profile: friend,
                        selected: _selectedFriendIds.contains(friend.id),
                        onChanged: _isCreating
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedFriendIds.add(friend.id);
                                  } else {
                                    _selectedFriendIds.remove(friend.id);
                                  }
                                });
                              },
                      ),
                  ],
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(_errorText!, style: TextStyle(color: c.dangerText)),
            ],
            const SizedBox(height: 16),
            WeCordButton(
              key: const ValueKey('group-create'),
              label: tr('Create'),
              size: WeCordButtonSize.large,
              expand: true,
              loading: _isCreating,
              onPressed: canCreate ? _createGroup : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroup() async {
    setState(() {
      _isCreating = true;
      _errorText = null;
    });

    final title = _titleController.text.trim();
    final memberIds = _selectedFriendIds.toList(growable: false);

    try {
      final conversationId = await ref
          .read(chatsRepositoryProvider)
          .createGroupConversation(title: title, memberIds: memberIds);
      if (!mounted) {
        return;
      }
      unawaited(
        noticePendingInvitations(
          ref,
          ScaffoldMessenger.maybeOf(context),
          conversationId,
          memberIds,
        ),
      );
      Navigator.of(context).pop(
        GroupCreationResult(
          conversationId: conversationId,
          title: title,
          memberIds: memberIds,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = tr('Unable to create group: {error}', {'error': error});
        _isCreating = false;
      });
    }
  }
}

/// A friend with a round check, for picking group members.
class FriendPickerRow extends StatelessWidget {
  const FriendPickerRow({
    required this.profile,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Profile profile;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final onChanged = this.onChanged;
    return WeCordPressable(
      onPressed: onChanged == null ? null : () => onChanged(!selected),
      toggled: selected,
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final highlighted =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          color: c.ink.withValues(alpha: highlighted ? 0.04 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ProfileAvatar(
                name: profile.displayLabel,
                avatarUrl: profile.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '@${profile.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: WeCordMotion.quick,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.accent : c.panel,
                  border: selected
                      ? null
                      : Border.all(color: c.track, width: 1.5),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 16, color: c.onAccent)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
