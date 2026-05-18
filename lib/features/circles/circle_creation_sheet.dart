import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/profile.dart';

class CircleCreationSheet extends ConsumerStatefulWidget {
  const CircleCreationSheet({super.key});

  @override
  ConsumerState<CircleCreationSheet> createState() =>
      _CircleCreationSheetState();
}

class _CircleCreationSheetState extends ConsumerState<CircleCreationSheet> {
  final _nameController = TextEditingController();
  final _selectedFriendIds = <String>{};
  var _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friendsFuture = ref.watch(contactsRepositoryProvider).listFriends();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: FutureBuilder<List<Profile>>(
          future: friendsFuture,
          builder: (context, snapshot) {
            final friends = snapshot.data ?? const <Profile>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Circle',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Circle name',
                  ),
                ),
                if (friends.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Invite friends',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final friend in friends)
                          CheckboxListTile(
                            value: _selectedFriendIds.contains(friend.id),
                            title: Text(friend.displayLabel),
                            subtitle: Text('@${friend.username}'),
                            onChanged: _isSaving
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
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _createCircle,
                    child: _isSaving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _createCircle() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorText = 'Circle name is required.';
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      final circleId = await ref
          .read(circlesRepositoryProvider)
          .createCircle(
            name: name,
            memberIds: _selectedFriendIds.toList(growable: false),
          );
      if (!mounted) return;
      context.pop();
      context.go('/circles/$circleId');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Could not create Circle. Try again. $error';
      });
    }
  }
}
