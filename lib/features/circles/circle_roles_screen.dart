import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

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
    final loaded = detail.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Roles')),
        actions: [
          if (loaded != null &&
              loaded.canManageRoles &&
              loaded.currentUserRank > 0)
            IconButton(
              tooltip: tr('Create role'),
              icon: const Icon(Icons.add),
              onPressed: () => showCircleRoleEditorSheet(context, loaded),
            ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
        data: _buildRoles,
      ),
    );
  }

  Widget _buildRoles(CircleDetail detail) {
    final theme = Theme.of(context);
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Text(
          tr(
            'Members get the permissions of every role they hold. Roles '
            'higher in the list rank higher, and names take the color of '
            'their highest colored role.',
          ),
          style: theme.textTheme.bodySmall,
        ),
      ),
      footer: everyone == null
          ? null
          : _RoleTile(
              key: ValueKey('circle-role-${everyone.id}'),
              role: everyone,
              detail: detail,
              subtitle: tr('Every member'),
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
    final colorScheme = Theme.of(context).colorScheme;
    final color = role.color;
    final count = role.memberCount;
    final canManage = detail.canManageRole(role);

    return ListTile(
      leading: Icon(
        Icons.circle,
        size: 16,
        color: color == null ? colorScheme.outline : circleRoleColor(color),
      ),
      title: Text(
        role.isDefault ? '@everyone' : role.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle ??
            (count == 1
                ? tr('1 member')
                : tr('{count} members', {'count': count})),
      ),
      trailing: switch (dragIndex) {
        final index? => ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_handle),
          ),
        ),
        null when !canManage => Tooltip(
          message: tr('Ranked at or above your highest role'),
          child: const Icon(Icons.lock_outline, size: 18),
        ),
        null => null,
      },
      onTap: () => showCircleRoleEditorSheet(context, detail, role: role),
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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
      if (role == null) {
        await repository.createRole(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Delete role')),
        content: Text(
          tr('Delete "{name}"? Members who have it lose its permissions.', {
            'name': role.name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = _role;
    final editable = _editable && !_isSaving;
    final title = role == null
        ? tr('Create role')
        : _isDefault
        ? '@everyone'
        : editable
        ? tr('Edit role')
        : role.name;

    return SafeArea(
      child: Padding(
        // Lifts the sheet above the keyboard, so the content scrolls
        // within the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (_isDefault) ...[
                const SizedBox(height: 4),
                Text(
                  tr('Every member has these permissions.'),
                  style: theme.textTheme.bodyMedium,
                ),
              ] else if (role != null && !_editable) ...[
                const SizedBox(height: 4),
                Text(
                  tr('This role ranks at or above your highest role.'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (!_isDefault) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  enabled: editable,
                  autofocus: role == null,
                  maxLength: maxCircleRoleNameLength,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: tr('Role name'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(tr('Color'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ColorSwatch(
                      color: null,
                      selected: _color == null,
                      onTap: editable
                          ? () => setState(() => _color = null)
                          : null,
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
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Show separately')),
                  subtitle: Text(
                    tr(
                      'List online members with this role in their own group.',
                    ),
                  ),
                  value: _hoist,
                  onChanged: editable
                      ? (value) => setState(() => _hoist = value)
                      : null,
                ),
              ],
              for (final group in CirclePermissionGroup.values) ...[
                const SizedBox(height: 12),
                Text(
                  group.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final permission in CirclePermission.values)
                  if (permission.group == group)
                    SwitchListTile(
                      key: ValueKey('role-permission-${permission.key}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(permission.label),
                      subtitle: Text(permission.description),
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
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (_editable) ...[
                const SizedBox(height: 16),
                // Stacks the buttons when they do not fit side by side.
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  overflowSpacing: 8,
                  children: [
                    if (role != null && !_isDefault)
                      TextButton.icon(
                        onPressed: _isSaving ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(tr('Delete role')),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: Text(role == null ? tr('Create') : tr('Save')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final value = color;
    final hex = value?.toRadixString(16).padLeft(6, '0').toUpperCase();
    return Tooltip(
      message: hex == null ? tr('No color') : '#$hex',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value == null ? colorScheme.surface : circleRoleColor(value),
            border: Border.all(
              color: selected ? colorScheme.onSurface : colorScheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: value == null
              ? Icon(Icons.block, size: 18, color: colorScheme.outline)
              : selected
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : null,
        ),
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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
    final theme = Theme.of(context);
    final detail = widget.detail;
    final roles = [
      for (final role in detail.roles)
        if (!role.isDefault) role,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Manage roles'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.member.displayName, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (roles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(tr('This circle has no roles yet.')),
              ),
            for (final role in roles)
              CheckboxListTile(
                key: ValueKey('member-role-${role.id}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                secondary: Icon(
                  Icons.circle,
                  size: 14,
                  color: role.color == null
                      ? theme.colorScheme.outline
                      : circleRoleColor(role.color!),
                ),
                title: Text(
                  role.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _selected.contains(role.id),
                onChanged: detail.canManageRole(role) && !_isSaving
                    ? (value) => setState(() {
                        if (value == true) {
                          _selected.add(role.id);
                        } else {
                          _selected.remove(role.id);
                        }
                      })
                    : null,
              ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Text(tr('Save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
