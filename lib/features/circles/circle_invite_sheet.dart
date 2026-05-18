import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/circle.dart';

class CircleInviteSheet extends ConsumerStatefulWidget {
  const CircleInviteSheet({required this.detail, super.key});

  final CircleDetail detail;

  @override
  ConsumerState<CircleInviteSheet> createState() => _CircleInviteSheetState();
}

class _CircleInviteSheetState extends ConsumerState<CircleInviteSheet> {
  final _selectedFriendIds = <String>{};
  var _isSaving = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final existingMemberIds = {
      for (final member in widget.detail.members) member.profile.id,
    };
    final friendsFuture = ref.watch(contactsRepositoryProvider).listFriends();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder(
          future: friendsFuture,
          builder: (context, snapshot) {
            final friends = (snapshot.data ?? [])
                .where((friend) => !existingMemberIds.contains(friend.id))
                .toList(growable: false);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite friends',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No friends to invite'),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
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
                    onPressed: _isSaving || _selectedFriendIds.isEmpty
                        ? null
                        : _invite,
                    child: const Text('Invite'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _invite() async {
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(circlesRepositoryProvider)
          .inviteMembers(
            circleId: widget.detail.circle.id,
            memberIds: _selectedFriendIds.toList(growable: false),
          );
      ref.invalidate(circleDetailProvider(widget.detail.circle.id));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Could not invite friends. Try again. $error';
      });
    }
  }
}
