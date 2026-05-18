import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/profile.dart';

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
    final title = _titleController.text.trim();
    final canCreate =
        title.isNotEmpty && _selectedFriendIds.length >= 2 && !_isCreating;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New group', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Group name',
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final friend in widget.friends)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(friend.displayLabel),
                      subtitle: Text('@${friend.username}'),
                      value: _selectedFriendIds.contains(friend.id),
                      onChanged: _isCreating
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected == true) {
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
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: canCreate ? _createGroup : null,
                child: _isCreating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
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
        _errorText = 'Unable to create group: $error';
        _isCreating = false;
      });
    }
  }
}
