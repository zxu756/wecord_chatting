import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/developer/bot_directory.dart';
import 'package:wecord/features/ai/assistant/group_ai_row.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/groups/group_creation_sheet.dart';
import 'package:wecord/features/groups/group_invitations.dart';
import 'package:wecord/features/groups/group_members_source.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/qr/group_qr_sheet.dart';
import 'package:wecord/features/urgent/announcement_ack.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

final groupDetailProvider = FutureProvider.autoDispose
    .family<GroupDetail, String>((ref, conversationId) {
      final repository = ref.watch(chatsRepositoryProvider);
      final subscription = repository.conversationChanges().listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      return repository.getGroupDetail(conversationId);
    });

/// A group's details, members and actions. Open it with
/// `showWeCordSheet(detents: GroupDetailSheet.detents, …)` and pass the
/// sheet's [scrollController]; without one it draws its own draggable
/// sheet frame.
class GroupDetailSheet extends ConsumerStatefulWidget {
  const GroupDetailSheet({
    required this.conversationId,
    required this.title,
    this.scrollController,
    super.key,
  });

  /// Where the sheet snaps: half, most of the screen and full.
  static const detents = [0.5, 0.86, 0.95];
  static const initialDetent = 0.86;

  final String conversationId;
  final String title;

  /// The detent sheet's controller, which drives the content's list.
  final ScrollController? scrollController;

  @override
  ConsumerState<GroupDetailSheet> createState() => _GroupDetailSheetState();
}

class _GroupDetailSheetState extends ConsumerState<GroupDetailSheet> {
  final _titleController = TextEditingController();
  final _announcementController = TextEditingController();
  final _memberSearchController = TextEditingController();
  var _query = '';

  // A big group's members (L6): the sheet holds the first page; "show more"
  // adds the next ones and a search asks the database.
  var _moreMembers = const <GroupMember>[];
  GroupMembersCursor? _moreCursor;
  var _moreStarted = false;
  var _moreExhausted = false;
  var _loadingMore = false;
  List<GroupMember>? _searchResults;
  Timer? _searchDebounce;
  var _searchToken = 0;
  var _pendingAvatarUrl = '';
  var _isSaving = false;
  String? _errorText;
  String? _loadedConversationId;

  /// "Ask members to confirm" as the owner set it; null until touched.
  bool? _requireAck;

  @override
  void dispose() {
    _titleController.dispose();
    _announcementController.dispose();
    _memberSearchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.scrollController;
    if (controller != null) {
      return SafeArea(
        top: false,
        child: Padding(
          // The sheet reaches under the keyboard; its list stops above it
          // so the focused field scrolls into view.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: _buildContent(context, controller),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        // Keeps the focused field above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: GroupDetailSheet.initialDetent,
          minChildSize: GroupDetailSheet.detents.first,
          maxChildSize: GroupDetailSheet.detents.last,
          builder: (context, scrollController) {
            return WeCordSheet(
              expand: true,
              child: Expanded(child: _buildContent(context, scrollController)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ScrollController controller) {
    final detail = ref.watch(groupDetailProvider(widget.conversationId));
    return detail.when(
      loading: () => const _LoadingDetail(),
      error: (error, stackTrace) => _ErrorDetail(
        title: widget.title.trim().isEmpty
            ? widget.conversationId
            : widget.title.trim(),
        errorText: errorText(error),
      ),
      data: (detail) => _buildDetail(context, detail, controller),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    GroupDetail detail,
    ScrollController scrollController,
  ) {
    final c = context.tokens.colors;
    _syncControllers(detail);
    final canManage = detail.canManageGroup;
    final members = _visibleMembers(detail);
    final searching = _query.trim().isNotEmpty;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _Header(
          detail: detail,
          avatarUrl: _pendingAvatarUrl.isEmpty
              ? detail.avatarUrl
              : _pendingAvatarUrl,
          onPickAvatar: canManage ? () => _pickAvatar(detail) : null,
        ),
        const SizedBox(height: 20),
        WeCordTextField(
          controller: _titleController,
          enabled: canManage && !_isSaving,
          label: tr('Group name'),
        ),
        const SizedBox(height: 14),
        WeCordTextField(
          controller: _announcementController,
          enabled: canManage && !_isSaving,
          minLines: 2,
          maxLines: 4,
          label: tr('Announcement'),
        ),
        if (_announcementMetaText(detail) case final metaText?)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              metaText,
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
        if (canManage) ...[
          const SizedBox(height: 12),
          AnnouncementAckToggle(
            value:
                _requireAck ??
                ref
                    .watch(announcementAckStateProvider(detail.conversationId))
                    .value
                    ?.requiresAck ??
                false,
            onChanged: _isSaving
                ? null
                : (value) => setState(() => _requireAck = value),
          ),
        ],
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(_errorText!, style: TextStyle(color: c.dangerText)),
          ),
        if (canManage) ...[
          const SizedBox(height: 14),
          WeCordButton(
            key: const ValueKey('group-detail-save'),
            label: tr('Save'),
            icon: Icons.check_rounded,
            expand: true,
            loading: _isSaving,
            onPressed: () => _save(detail),
          ),
        ],
        const SizedBox(height: 16),
        SettingsGroup(
          color: c.well,
          children: [
            if (canManage)
              SettingsRow(
                key: const ValueKey('group-detail-invite'),
                icon: Icons.person_add_alt_1_outlined,
                tone: SettingsTone.accent,
                title: tr('Invite friends'),
                onTap: _isSaving ? null : () => _showInviteSheet(detail),
              ),
            // Whoever may add members can share the group's QR code.
            if (canManage)
              SettingsRow(
                key: const ValueKey('group-detail-qr'),
                icon: Icons.qr_code_2_rounded,
                tone: SettingsTone.success,
                title: tr('Group QR code'),
                subtitle: tr('Lets people join; works for 7 days'),
                onTap: _isSaving
                    ? null
                    : () => unawaited(
                        showGroupQrSheet(
                          context,
                          conversationId: widget.conversationId,
                          title: detail.title,
                          avatarUrl: detail.avatarUrl,
                          memberCount: detail.memberCount,
                        ),
                      ),
              ),
            // The owner decides whether WeCord AI answers in the group.
            if (detail.currentUserRole == 'owner')
              AiAssistantGroupRow(conversationId: widget.conversationId),
            // Everyone sees the bots in the group; the owner brings them in.
            GroupBotsRow(
              chatId: widget.conversationId,
              isOwner: detail.currentUserRole == 'owner',
            ),
            SettingsRow(
              key: const ValueKey('group-detail-leave'),
              icon: Icons.logout_rounded,
              title: tr('Leave group'),
              destructive: true,
              showChevron: false,
              onTap: _isSaving ? null : () => _leaveGroup(detail),
            ),
          ],
        ),
        SettingsSectionHeader(
          tr('Group members'),
          trailing: Text(
            '${detail.memberCount}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.subtle,
            ),
          ),
        ),
        WeCordTextField(
          controller: _memberSearchController,
          hint: tr('Search members'),
          prefixIcon: Icons.search_rounded,
          onChanged: (value) {
            setState(() {
              _query = value;
            });
            if (detail.hasMoreMembers) {
              _scheduleMemberSearch(detail, value);
            }
          },
        ),
        const SizedBox(height: 10),
        if (members.isEmpty && searching && detail.hasMoreMembers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _searchResults == null ? '' : tr('No members found'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
        if (members.isNotEmpty)
          SettingsGroup(
            color: c.well,
            separatorIndent: 66,
            children: [
              for (final member in members)
                _MemberTile(
                  member: member,
                  canRemove: _canRemove(detail, member),
                  onOpenProfile: () {
                    context.push(
                      userProfileLocation(
                        member.profile.id,
                        source: FriendSource.group,
                      ),
                    );
                  },
                  onRemove: () => _removeMember(detail, member),
                ),
            ],
          ),
        if (detail.hasMoreMembers && !searching && !_moreExhausted) ...[
          const SizedBox(height: 10),
          WeCordButton(
            key: const ValueKey('group-detail-more-members'),
            label: tr('Show more members'),
            variant: WeCordButtonVariant.secondary,
            expand: true,
            loading: _loadingMore,
            onPressed: _loadingMore ? null : () => _loadMoreMembers(detail),
          ),
        ],
      ],
    );
  }

  /// The members the list shows: for a big group the pages loaded so far, or
  /// the database's answer to the search; otherwise everyone, filtered here.
  List<GroupMember> _visibleMembers(GroupDetail detail) {
    if (!detail.hasMoreMembers) {
      return _filteredMembers(detail.members);
    }
    if (_query.trim().isNotEmpty) {
      return _searchResults ?? _filteredMembers(detail.members);
    }
    final seen = <String>{};
    return [
      ...detail.members,
      ..._moreMembers,
    ].where((member) => seen.add(member.profile.id)).toList(growable: false);
  }

  void _scheduleMemberSearch(GroupDetail detail, String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final token = ++_searchToken;
    if (query.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final found = await ref
            .read(groupMembersSourceProvider)
            .search(detail.conversationId, query);
        if (mounted && token == _searchToken) {
          setState(() => _searchResults = found);
        }
      } catch (_) {
        if (mounted && token == _searchToken) {
          setState(() {
            _searchResults = const [];
            _errorText = tr('Could not load members.');
          });
        }
      }
    });
  }

  Future<void> _loadMoreMembers(GroupDetail detail) async {
    final after = _moreStarted ? _moreCursor : detail.moreMembersAfter;
    if (after == null) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(groupMembersSourceProvider)
          .page(detail.conversationId, after: after);
      if (!mounted) {
        return;
      }
      setState(() {
        _moreStarted = true;
        _moreMembers = [..._moreMembers, ...page.members];
        _moreCursor = page.next;
        _moreExhausted = page.next == null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = tr('Could not load members.'));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
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

  String? _announcementMetaText(GroupDetail detail) {
    if (detail.announcement.trim().isEmpty ||
        detail.announcementUpdatedAt == null) {
      return null;
    }
    GroupMember? updater;
    for (final member in detail.members) {
      if (member.profile.id == detail.announcementUpdatedBy) {
        updater = member;
        break;
      }
    }
    if (updater == null) {
      return tr('Updated {time}', {
        'time': _formatAnnouncementTime(detail.announcementUpdatedAt!),
      });
    }
    return tr('Updated by {name}', {'name': updater.profile.displayLabel});
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
          _errorText = tr('Could not update group avatar.');
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
      // Asking for confirmations is a separate call (A7): after the text, so
      // the request is for the text just saved.
      final wanted = _requireAck;
      final before = ref
          .read(announcementAckStateProvider(detail.conversationId))
          .value
          ?.requiresAck;
      if (wanted != null && wanted != before) {
        try {
          await ref
              .read(urgentRepositoryProvider)
              .setAnnouncementRequiresAck(
                detail.conversationId,
                required: wanted,
              );
        } catch (error) {
          if (mounted) {
            setState(() {
              _requireAck = before;
              _errorText = announcementAckProblemText(error);
            });
          }
        }
      }
      ref
        ..invalidate(announcementAckStateProvider(detail.conversationId))
        ..invalidate(groupDetailProvider(detail.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not save group details.');
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
    await showWeCordSheet<void>(
      context,
      title: tr('Invite friends'),
      builder: (context, scrollController) {
        return FutureBuilder<List<Profile>>(
          future: ref.read(contactsRepositoryProvider).listFriends(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final friends = snapshot.data!
                .where((profile) => !existingIds.contains(profile.id))
                .toList(growable: false);
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final c = context.tokens.colors;
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (friends.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              tr('No friends available to invite.'),
                              style: TextStyle(fontSize: 14, color: c.muted),
                            ),
                          )
                        else
                          Flexible(
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.well,
                                borderRadius: BorderRadius.circular(
                                  WeCordRadii.xl,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                children: [
                                  for (final friend in friends)
                                    FriendPickerRow(
                                      profile: friend,
                                      selected: selected.contains(friend.id),
                                      onChanged: (value) {
                                        setSheetState(() {
                                          if (value) {
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
                          ),
                        const SizedBox(height: 16),
                        WeCordButton(
                          label: tr('Add selected'),
                          icon: Icons.person_add_alt_1_outlined,
                          size: WeCordButtonSize.large,
                          expand: true,
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                },
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(chatsRepositoryProvider)
          .addGroupMembers(
            conversationId: detail.conversationId,
            memberIds: selected.toList(growable: false),
          );
      ref.invalidate(groupDetailProvider(detail.conversationId));
      unawaited(
        noticePendingInvitations(
          ref,
          messenger,
          detail.conversationId,
          selected,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not invite members.');
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
          _errorText = tr('Could not leave group.');
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
      if (mounted) {
        // The pages loaded here are not part of the reloaded detail.
        setState(() {
          bool kept(GroupMember m) => m.profile.id != member.profile.id;
          _moreMembers = _moreMembers.where(kept).toList(growable: false);
          _searchResults = _searchResults?.where(kept).toList(growable: false);
        });
      }
      ref.invalidate(groupDetailProvider(detail.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not remove member.');
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
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 12),
          Text(errorText, style: TextStyle(color: c.dangerText)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.avatarUrl,
    required this.onPickAvatar,
  });

  final GroupDetail detail;
  final String? avatarUrl;
  final VoidCallback? onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final role = detail.currentUserRole;
    return Row(
      children: [
        SizedBox.square(
          dimension: 68,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _GroupAvatar(title: detail.title, avatarUrl: avatarUrl, size: 64),
              Positioned(
                right: -6,
                bottom: -6,
                child: WeCordPressable(
                  onPressed: onPickAvatar,
                  tooltip: tr('Change group avatar'),
                  semanticLabel: tr('Change group avatar'),
                  shape: const CircleBorder(),
                  pressedScale: 0.92,
                  builder: (context, states) => AnimatedOpacity(
                    duration: WeCordMotion.quick,
                    opacity: onPickAvatar == null ? 0.5 : 1,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.panel, width: 2.5),
                      ),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 15,
                        color: c.onInk,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  tr('Group details'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tr('{count} members', {'count': detail.memberCount}),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
              if (role != null) ...[
                const SizedBox(height: 6),
                _RoleTag(role: role),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The group's picture in a squircle, or its initial.
class _GroupAvatar extends ConsumerStatefulWidget {
  const _GroupAvatar({
    required this.title,
    required this.avatarUrl,
    required this.size,
  });

  final String title;
  final String? avatarUrl;
  final double size;

  @override
  ConsumerState<_GroupAvatar> createState() => _GroupAvatarState();
}

class _GroupAvatarState extends ConsumerState<_GroupAvatar> {
  /// The URL that failed to load, so the initial shows instead.
  String? _failedUrl;

  @override
  Widget build(BuildContext context) {
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(widget.avatarUrl))
        .value;
    if (displayUrl == null || displayUrl == _failedUrl) {
      return ThingAvatar(label: widget.title, size: widget.size);
    }
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        children: [
          ThingAvatar(label: widget.title, size: widget.size),
          Positioned.fill(
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(widget.size / 3),
              child: Image.network(
                displayUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _failedUrl != displayUrl) {
                      setState(() => _failedUrl = displayUrl);
                      refreshAvatarDisplayUrl(ref, widget.avatarUrl);
                    }
                  });
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "owner", "admin" or "member" as a small tag.
class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final (fill, foreground) = switch (role) {
      'owner' => (c.warningSoft, c.warningText),
      'admin' => (c.accentSoft, c.accentText),
      _ => (c.raised, c.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(WeCordRadii.xs),
      ),
      child: Text(
        _roleLabel(role),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canRemove,
    required this.onOpenProfile,
    required this.onRemove,
  });

  final GroupMember member;
  final bool canRemove;
  final VoidCallback onOpenProfile;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onOpenProfile,
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
          padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
          child: Row(
            children: [
              ProfileAvatar(
                name: member.profile.displayLabel,
                avatarUrl: member.profile.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.profile.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '@${member.profile.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RoleTag(role: member.role),
              if (canRemove) ...[
                const SizedBox(width: 2),
                WeCordIconButton(
                  icon: Icons.person_remove_outlined,
                  tooltip: tr('Remove member'),
                  size: 36,
                  variant: WeCordButtonVariant.ghost,
                  onPressed: onRemove,
                ),
              ] else
                const SizedBox(width: 6),
            ],
          ),
        );
      },
    );
  }
}

String _formatAnnouncementTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

String _roleLabel(String role) {
  return switch (role) {
    'owner' => tr('owner'),
    'admin' => tr('admin'),
    'member' => tr('member'),
    _ => role,
  };
}
