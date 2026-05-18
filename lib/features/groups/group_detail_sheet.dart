import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/profile.dart';

final groupDetailProvider = FutureProvider.autoDispose
    .family<GroupDetail, String>((ref, conversationId) {
      final repository = ref.watch(chatsRepositoryProvider);
      final subscription = repository.conversationChanges().listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      return repository.getGroupDetail(conversationId);
    });

class GroupDetailSheet extends ConsumerStatefulWidget {
  const GroupDetailSheet({
    required this.conversationId,
    required this.title,
    super.key,
  });

  final String conversationId;
  final String title;

  @override
  ConsumerState<GroupDetailSheet> createState() => _GroupDetailSheetState();
}

class _GroupDetailSheetState extends ConsumerState<GroupDetailSheet> {
  final _titleController = TextEditingController();
  final _announcementController = TextEditingController();
  final _memberSearchController = TextEditingController();
  var _query = '';
  var _pendingAvatarUrl = '';
  var _isSaving = false;
  String? _errorText;
  String? _loadedConversationId;

  @override
  void dispose() {
    _titleController.dispose();
    _announcementController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(groupDetailProvider(widget.conversationId));

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return detail.when(
            loading: () => const _LoadingDetail(),
            error: (error, stackTrace) => _ErrorDetail(
              title: widget.title.trim().isEmpty
                  ? widget.conversationId
                  : widget.title.trim(),
              errorText: error.toString(),
            ),
            data: (detail) {
              _syncControllers(detail);
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _Header(
                    detail: detail,
                    avatarUrl: _pendingAvatarUrl.isEmpty
                        ? detail.avatarUrl
                        : _pendingAvatarUrl,
                    onPickAvatar: detail.canManageGroup
                        ? () => _pickAvatar(detail)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    enabled: detail.canManageGroup && !_isSaving,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Group name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _announcementController,
                    enabled: detail.canManageGroup && !_isSaving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Announcement',
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: detail.canManageGroup && !_isSaving
                            ? () => _save(detail)
                            : null,
                        icon: _isSaving
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      ),
                      OutlinedButton.icon(
                        onPressed: detail.canManageGroup && !_isSaving
                            ? () => _showInviteSheet(detail)
                            : null,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Invite friends'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : () => _leaveGroup(detail),
                        icon: const Icon(Icons.logout_outlined),
                        label: const Text('Leave group'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Group members',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _memberSearchController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Search members',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  for (final member in _filteredMembers(detail.members))
                    _MemberTile(
                      member: member,
                      canRemove: _canRemove(detail, member),
                      onRemove: () => _removeMember(detail, member),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _syncControllers(GroupDetail detail) {
    if (_loadedConversationId == detail.conversationId) {
      return;
    }
    _loadedConversationId = detail.conversationId;
    _titleController.text = detail.title;
    _announcementController.text = detail.announcement;
    _pendingAvatarUrl = detail.avatarUrl ?? '';
  }

  List<GroupMember> _filteredMembers(List<GroupMember> members) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return members;
    }
    return members
        .where((member) {
          return member.profile.displayLabel.toLowerCase().contains(query) ||
              member.profile.displayName.toLowerCase().contains(query) ||
              member.profile.username.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  bool _canRemove(GroupDetail detail, GroupMember member) {
    if (member.role == 'owner') {
      return false;
    }
    if (detail.currentUserRole == 'owner') {
      return true;
    }
    return detail.currentUserRole == 'admin' && member.role == 'member';
  }

  Future<void> _pickAvatar(GroupDetail detail) async {
    setState(() {
      _errorText = null;
    });
    try {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (image == null || !mounted) {
        return;
      }
      final avatarUrl = await ref
          .read(chatsRepositoryProvider)
          .uploadGroupAvatar(
            conversationId: detail.conversationId,
            image: image,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingAvatarUrl = avatarUrl;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not update group avatar.';
        });
      }
    }
  }

  Future<void> _save(GroupDetail detail) async {
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(chatsRepositoryProvider)
          .updateGroupProfile(
            conversationId: detail.conversationId,
            title: _titleController.text,
            avatarUrl: _pendingAvatarUrl.isEmpty ? null : _pendingAvatarUrl,
            announcement: _announcementController.text,
          );
      ref.invalidate(groupDetailProvider(detail.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not save group details.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showInviteSheet(GroupDetail detail) async {
    final selected = <String>{};
    final existingIds = {
      for (final member in detail.members) member.profile.id,
    };
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return FutureBuilder<List<Profile>>(
          future: ref.read(contactsRepositoryProvider).listFriends(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SafeArea(
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final friends = snapshot.data!
                .where((profile) => !existingIds.contains(profile.id))
                .toList(growable: false);
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Invite friends',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (friends.isEmpty)
                          const Text('No friends available to invite.')
                        else
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final friend in friends)
                                  CheckboxListTile(
                                    value: selected.contains(friend.id),
                                    title: Text(friend.displayLabel),
                                    subtitle: Text('@${friend.username}'),
                                    onChanged: (value) {
                                      setSheetState(() {
                                        if (value ?? false) {
                                          selected.add(friend.id);
                                        } else {
                                          selected.remove(friend.id);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                },
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Add selected'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
    if (selected.isEmpty || !mounted) {
      return;
    }
    try {
      await ref
          .read(chatsRepositoryProvider)
          .addGroupMembers(
            conversationId: detail.conversationId,
            memberIds: selected.toList(growable: false),
          );
      ref.invalidate(groupDetailProvider(detail.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not invite members.';
        });
      }
    }
  }

  Future<void> _leaveGroup(GroupDetail detail) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .leaveGroupConversation(detail.conversationId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not leave group.';
        });
      }
    }
  }

  Future<void> _removeMember(GroupDetail detail, GroupMember member) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .removeGroupMember(
            conversationId: detail.conversationId,
            memberId: member.profile.id,
          );
      ref.invalidate(groupDetailProvider(detail.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not remove member.';
        });
      }
    }
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorDetail extends StatelessWidget {
  const _ErrorDetail({required this.title, required this.errorText});

  final String title;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            errorText,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.detail,
    required this.avatarUrl,
    required this.onPickAvatar,
  });

  final GroupDetail detail;
  final String? avatarUrl;
  final VoidCallback? onPickAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUrl = ref.watch(avatarDisplayUrlProvider(avatarUrl));
    final image = displayUrl.valueOrNull == null
        ? null
        : NetworkImage(displayUrl.valueOrNull!);
    return Row(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: image,
              onBackgroundImageError: image == null ? null : (_, _) {},
              child: image == null ? Text(_initials(detail.title)) : null,
            ),
            IconButton.filledTonal(
              tooltip: 'Change group avatar',
              onPressed: onPickAvatar,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Group details',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('${detail.memberCount} members'),
              if (detail.currentUserRole != null) Text(detail.currentUserRole!),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canRemove,
    required this.onRemove,
  });

  final GroupMember member;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(_initials(member.profile.displayLabel)),
      ),
      title: Text(member.profile.displayLabel),
      subtitle: Text('@${member.profile.username}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(member.role),
          if (canRemove) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Remove member',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}
