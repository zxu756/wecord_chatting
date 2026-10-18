import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/role_mentions.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/ui/ui.dart';

const maxCircleRoleNameLength = 32;

/// The colour of a 0xRRGGBB role colour.
Color circleRoleColor(int rgb) => Color(0xFF000000 | rgb);

void openCircleRolesScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleRolesScreen(circleId: circleId),
    ),
  );
}

/// The circle's roles, highest first, with `@everyone` last. Members who
/// can manage roles create roles, edit and delete the ones below their
/// highest role, and drag those into a new order.
class CircleRolesScreen extends ConsumerStatefulWidget {
  const CircleRolesScreen({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleRolesScreen> createState() => _CircleRolesScreenState();
}

class _CircleRolesScreenState extends ConsumerState<CircleRolesScreen> {
  /// Shown instead of the server's order while a reorder is saved.
  List<CircleRole>? _pendingOrder;
  CircleDetail? _pendingFor;

  Future<void> _reorder(
    CircleDetail detail,
    List<CircleRole> roles,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) {
      return;
    }
    final next = [...roles];
    next.insert(newIndex, next.removeAt(oldIndex));
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Positions are handed out in order, so a role the user cannot manage
    // must stay where it is.
    for (final (index, role) in next.indexed) {
      if (!detail.canManageRole(role) && roles[index].id != role.id) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              tr('You can only move roles below your highest role.'),
            ),
          ),
        );
        return;
      }
    }
    setState(() {
      _pendingOrder = next;
      _pendingFor = detail;
    });
    try {
      await ref
          .read(circlesRepositoryProvider)
          .reorderRoles(
            circleId: widget.circleId,
            roleIds: [for (final role in next) role.id],
          );
      ref.invalidate(circleDetailProvider(widget.circleId));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _pendingOrder = null);
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not reorder roles. Try again.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(circleDetailProvider(widget.circleId));
    final loaded = detail.value;

    return CirclePageScaffold(
      title: tr('Roles'),
      subtitle: loaded?.circle.name,
      actions: [
        if (loaded != null &&
            loaded.canManageRoles &&
            loaded.currentUserRank > 0)
          WeCordIconButton(
            tooltip: tr('Create role'),
            icon: Icons.add_rounded,
            variant: WeCordButtonVariant.onPaper,
            size: 42,
            onPressed: () => showCircleRoleEditorSheet(context, loaded),
          ),
      ],
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: Icons.error_outline,
          title: tr('Could not load the circle.'),
          message: errorText(error),
        ),
        data: _buildRoles,
      ),
    );
  }

  Widget _buildRoles(CircleDetail detail) {
    final c = context.tokens.colors;
    if (!identical(detail, _pendingFor)) {
      // Fresh data from the server replaces the optimistic order.
      _pendingOrder = null;
      _pendingFor = null;
    }
    final roles =
        _pendingOrder ??
        [
          for (final role in detail.roles)
            if (!role.isDefault) role,
        ];
    CircleRole? everyone;
    for (final role in detail.roles) {
      if (role.isDefault) {
        everyone = role;
      }
    }

    return ReorderableListView.builder(
      padding: circlePagePadding(context),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            boxShadow: context.tokens.shadows.menu,
          ),
          child: child,
        ),
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
        child: Text(
          tr(
            'Members get the permissions of every role they hold. Roles '
            'higher in the list rank higher, and names take the color of '
            'their highest colored role.',
          ),
          style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
        ),
      ),
      footer: everyone == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 18),
              child: _RoleTile(
                key: ValueKey('circle-role-${everyone.id}'),
                role: everyone,
                detail: detail,
                subtitle: tr('Every member'),
              ),
            ),
      itemCount: roles.length,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(detail, roles, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final role = roles[index];
        return _RoleTile(
          key: ValueKey('circle-role-${role.id}'),
          role: role,
          detail: detail,
          dragIndex: detail.canManageRole(role) ? index : null,
        );
      },
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.detail,
    this.dragIndex,
    this.subtitle,
    super.key,
  });

  final CircleRole role;
  final CircleDetail detail;

  /// Index in the reorderable list, or null when the role cannot move.
  final int? dragIndex;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final color = role.color;
    final count = role.memberCount;
    final canManage = detail.canManageRole(role);
    final trailing = switch (dragIndex) {
      final index? => ReorderableDragStartListener(
        index: index,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(Icons.drag_handle, color: c.faint),
        ),
      ),
      null when !canManage => Tooltip(
        message: tr('Ranked at or above your highest role'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(Icons.lock_outline, size: 18, color: c.faint),
        ),
      ),
      null => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: WeCordPressable(
        onPressed: () => showCircleRoleEditorSheet(context, detail, role: role),
        pressedScale: 0.99,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) {
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);
          return AnimatedContainer(
            duration: WeCordMotion.quick,
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            decoration: BoxDecoration(
              color: hovered
                  ? Color.alphaBlend(c.ink.withValues(alpha: 0.03), c.panel)
                  : c.panel,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              children: [
                _RoleColorTile(color: color, isDefault: role.isDefault),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        role.isDefault ? '@everyone' : role.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: color == null ? c.ink : circleRoleColor(color),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ??
                            (count == 1
                                ? tr('1 member')
                                : tr('{count} members', {'count': count})),
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ],
                  ),
                ),
                ?trailing,
                if (trailing == null) const SizedBox(width: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The 32px tile with a role's colour dot (or @ for @everyone).
class _RoleColorTile extends StatelessWidget {
  const _RoleColorTile({required this.color, this.isDefault = false});

  final int? color;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final value = color;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: value == null
            ? c.raised
            : circleRoleColor(value).withValues(alpha: 0.16),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ),
      child: isDefault
          ? Icon(Icons.alternate_email_rounded, size: 17, color: c.muted)
          : Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value == null ? c.faint : circleRoleColor(value),
              ),
            ),
    );
  }
}

/// Opens the role editor: a new role without [role], otherwise [role],
/// read-only when the current user may not manage it.
void showCircleRoleEditorSheet(
  BuildContext context,
  CircleDetail detail, {
  CircleRole? role,
}) {
  showCircleDialog<void>(
    context,
    builder: (context) => CircleRoleEditorSheet(detail: detail, role: role),
  );
}

class CircleRoleEditorSheet extends ConsumerStatefulWidget {
  const CircleRoleEditorSheet({required this.detail, this.role, super.key});

  final CircleDetail detail;

  /// Null to create a role.
  final CircleRole? role;

  @override
  ConsumerState<CircleRoleEditorSheet> createState() =>
      _CircleRoleEditorSheetState();
}

class _CircleRoleEditorSheetState extends ConsumerState<CircleRoleEditorSheet> {
  late final _nameController = TextEditingController(
    text: widget.role?.name ?? '',
  );
  late int? _color = widget.role?.color;
  late bool _hoist = widget.role?.hoist ?? false;
  late int _permissions = widget.role?.permissions ?? 0;

  /// Whether anyone may @mention the role; null until changed here.
  bool? _mentionable;
  var _isSaving = false;
  String? _errorText;

  CircleRole? get _role => widget.role;

  bool get _isDefault => _role?.isDefault ?? false;

  bool get _editable => _role == null
      ? widget.detail.canManageRoles
      : widget.detail.canManageRole(_role!);

  /// Like the server: only permissions the user holds can be flipped.
  bool _canToggle(CirclePermission permission) {
    return _editable &&
        (widget.detail.isOwner ||
            permission.isGrantedBy(widget.detail.currentUserPermissions));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = tr('Role name is required.'));
      return;
    }
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    final repository = ref.read(circlesRepositoryProvider);
    final circleId = widget.detail.circle.id;
    try {
      final role = _role;
      String? roleId = role?.id;
      if (role == null) {
        roleId = await repository.createRole(
          circleId: circleId,
          name: name,
          color: _color,
          permissions: _permissions,
          hoist: _hoist,
        );
      } else {
        await repository.updateRole(
          roleId: role.id,
          name: role.isDefault ? role.name : name,
          color: role.isDefault ? null : _color,
          permissions: _permissions,
          hoist: !role.isDefault && _hoist,
        );
      }
      final mentionable = _mentionable;
      if (roleId != null &&
          mentionable != null &&
          mentionable != _savedMentionable) {
        await ref
            .read(roleMentionsRepositoryProvider)
            .setRoleMentionable(roleId: roleId, mentionable: mentionable);
        ref.invalidate(circleMentionableRoleIdsProvider(circleId));
      }
      ref.invalidate(circleDetailProvider(circleId));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = tr('Could not save the role. Try again.');
      });
    }
  }

  Future<void> _delete() async {
    final role = _role!;
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Delete role'),
      message: tr(
        'Delete "{name}"? Members who have it lose its permissions.',
        {'name': role.name},
      ),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await ref.read(circlesRepositoryProvider).deleteRole(role.id);
      ref.invalidate(circleDetailProvider(widget.detail.circle.id));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = tr('Could not delete the role. Try again.');
      });
    }
  }

  /// Whether anyone may mention the role as saved; false for new roles.
  bool get _savedMentionable {
    final role = _role;
    if (role == null) {
      return false;
    }
    return ref
            .watch(circleMentionableRoleIdsProvider(widget.detail.circle.id))
            .value
            ?.contains(role.id) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final role = _role;
    final editable = _editable && !_isSaving;
    final title = role == null
        ? tr('Create role')
        : _isDefault
        ? '@everyone'
        : editable
        ? tr('Edit role')
        : role.name;
    final message = _isDefault
        ? tr('Every member has these permissions.')
        : role != null && !_editable
        ? tr('This role ranks at or above your highest role.')
        : null;

    return CircleDialog(
      title: title,
      message: message,
      maxWidth: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isDefault) ...[
            WeCordTextField(
              controller: _nameController,
              enabled: editable,
              autofocus: role == null,
              maxLength: maxCircleRoleNameLength,
              label: tr('Role name'),
            ),
            SettingsSectionHeader(tr('Color')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ColorSwatch(
                  color: null,
                  selected: _color == null,
                  onTap: editable ? () => setState(() => _color = null) : null,
                ),
                for (final color in circleRoleColors)
                  _ColorSwatch(
                    color: color,
                    selected: _color == color,
                    onTap: editable
                        ? () => setState(() => _color = color)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsGroup(
              color: c.well,
              separatorIndent: 14,
              children: [
                SettingsRow.toggle(
                  title: tr('Show separately'),
                  subtitle: tr(
                    'List online members with this role in their own group.',
                  ),
                  value: _hoist,
                  onChanged: editable
                      ? (value) => setState(() => _hoist = value)
                      : null,
                ),
                SettingsRow.toggle(
                  key: const ValueKey('role-mentionable'),
                  title: tr('Allow anyone to @mention this role'),
                  subtitle: tr(
                    'Members with Mention everyone can mention any role.',
                  ),
                  value: _mentionable ?? _savedMentionable,
                  onChanged: editable
                      ? (value) => setState(() => _mentionable = value)
                      : null,
                ),
              ],
            ),
          ],
          for (final group in CirclePermissionGroup.values)
            SettingsGroup(
              header: group.label,
              color: c.well,
              separatorIndent: 14,
              children: [
                for (final permission in CirclePermission.values)
                  if (permission.group == group)
                    SettingsRow.toggle(
                      key: ValueKey('role-permission-${permission.key}'),
                      title: permission.label,
                      subtitle: permission.description,
                      value: _permissions & permission.bit != 0,
                      onChanged: _canToggle(permission) && !_isSaving
                          ? (value) => setState(() {
                              _permissions = value
                                  ? _permissions | permission.bit
                                  : _permissions & ~permission.bit;
                            })
                          : null,
                    ),
              ],
            ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(fontSize: 13, color: c.dangerText),
            ),
          ],
        ],
      ),
      actions: [
        if (_editable && role != null && !_isDefault)
          CircleDialogAction(
            label: tr('Delete role'),
            onPressed: _isSaving ? null : _delete,
          ),
        if (_editable)
          CircleDialogAction.primary(
            label: role == null ? tr('Create') : tr('Save'),
            onPressed: _isSaving ? null : _save,
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  /// 0xRRGGBB, or null for no colour.
  final int? color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final value = color;
    final hex = value?.toRadixString(16).padLeft(6, '0').toUpperCase();
    return WeCordPressable(
      tooltip: hex == null ? tr('No color') : '#$hex',
      onPressed: onTap,
      selected: selected,
      pressedScale: 0.9,
      shape: const CircleBorder(),
      builder: (context, states) => AnimatedContainer(
        duration: WeCordMotion.quick,
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value == null ? c.raised : circleRoleColor(value),
          border: Border.all(
            color: selected ? c.ink : c.line,
            width: selected ? 3 : 1,
          ),
        ),
        child: value == null
            ? Icon(Icons.block, size: 18, color: c.faint)
            : selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

/// Lets the current user pick which roles [member] holds. Roles at or
/// above the user's highest role are shown but cannot be changed.
void showCircleMemberRolesSheet(
  BuildContext context, {
  required CircleDetail detail,
  required CircleMember member,
}) {
  showCircleDialog<void>(
    context,
    builder: (context) =>
        CircleMemberRolesSheet(detail: detail, member: member),
  );
}

class CircleMemberRolesSheet extends ConsumerStatefulWidget {
  const CircleMemberRolesSheet({
    required this.detail,
    required this.member,
    super.key,
  });

  final CircleDetail detail;
  final CircleMember member;

  @override
  ConsumerState<CircleMemberRolesSheet> createState() =>
      _CircleMemberRolesSheetState();
}

class _CircleMemberRolesSheetState
    extends ConsumerState<CircleMemberRolesSheet> {
  late final _selected = {...widget.member.roleIds};
  var _isSaving = false;
  String? _errorText;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    final circleId = widget.detail.circle.id;
    try {
      await ref
          .read(circlesRepositoryProvider)
          .setMemberRoles(
            circleId: circleId,
            userId: widget.member.profile.id,
            roleIds: [
              for (final role in widget.detail.roles)
                if (_selected.contains(role.id)) role.id,
            ],
          );
      ref.invalidate(circleDetailProvider(circleId));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = tr('Could not save roles. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final detail = widget.detail;
    final roles = [
      for (final role in detail.roles)
        if (!role.isDefault) role,
    ];

    return CircleDialog(
      title: tr('Manage roles'),
      message: widget.member.displayName,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (roles.isEmpty)
            Text(
              tr('This circle has no roles yet.'),
              style: TextStyle(fontSize: 14, color: c.muted),
            )
          else
            SettingsGroup(
              color: c.well,
              separatorIndent: 14,
              children: [
                for (final role in roles)
                  SettingsRow.toggle(
                    key: ValueKey('member-role-${role.id}'),
                    title: role.name,
                    value: _selected.contains(role.id),
                    onChanged: detail.canManageRole(role) && !_isSaving
                        ? (value) => setState(() {
                            if (value) {
                              _selected.add(role.id);
                            } else {
                              _selected.remove(role.id);
                            }
                          })
                        : null,
                  ),
              ],
            ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(fontSize: 13, color: c.dangerText),
            ),
          ],
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          label: tr('Save'),
          onPressed: _isSaving ? null : _save,
        ),
      ],
    );
  }
}
