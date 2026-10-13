import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_role.dart';

typedef ChannelOverwritesKey = ({String circleId, String channelId});

/// The slowmode choices, in seconds (0 = off), like Discord's.
const channelSlowmodeOptions = [
  0,
  5,
  10,
  15,
  30,
  60,
  120,
  300,
  600,
  900,
  1800,
  3600,
  7200,
  21600,
];

/// `Off`, `30s`, `5m` or `2h`.
String channelSlowmodeLabel(int seconds) {
  if (seconds <= 0) {
    return 'Off';
  }
  if (seconds % 3600 == 0) {
    return '${seconds ~/ 3600}h';
  }
  if (seconds % 60 == 0) {
    return '${seconds ~/ 60}m';
  }
  return '${seconds}s';
}

/// A channel's permission overwrites. Reloads whenever the circle does, which
/// realtime refreshes when overwrites change.
final channelOverwritesProvider = FutureProvider.autoDispose
    .family<List<CircleChannelOverwrite>, ChannelOverwritesKey>((
      ref,
      key,
    ) async {
      await ref.watch(circleDetailProvider(key.circleId).future);
      return ref
          .watch(circlesRepositoryProvider)
          .listChannelOverwrites(key.channelId);
    });

void openCircleChannelSettings(
  BuildContext context, {
  required String circleId,
  required String channelId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          CircleChannelSettingsScreen(circleId: circleId, channelId: channelId),
    ),
  );
}

/// Channel settings. Members who can manage channels set slowmode; members
/// who can manage roles make the channel private or read-only for
/// `@everyone` and give roles and members their own permissions in it.
class CircleChannelSettingsScreen extends ConsumerStatefulWidget {
  const CircleChannelSettingsScreen({
    required this.circleId,
    required this.channelId,
    super.key,
  });

  final String circleId;
  final String channelId;

  @override
  ConsumerState<CircleChannelSettingsScreen> createState() =>
      _CircleChannelSettingsScreenState();
}

class _CircleChannelSettingsScreenState
    extends ConsumerState<CircleChannelSettingsScreen> {
  var _saving = false;

  ChannelOverwritesKey get _overwritesKey =>
      (circleId: widget.circleId, channelId: widget.channelId);

  Future<void> _run(
    Future<void> Function(CirclesRepository repository) action, {
    required String failure,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      await action(ref.read(circlesRepositoryProvider));
      ref.invalidate(circleDetailProvider(widget.circleId));
      ref.invalidate(channelOverwritesProvider(_overwritesKey));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _setPrivacy(
    CircleChannel channel, {
    required bool isPrivate,
    required bool isReadOnly,
  }) {
    return _run(
      (repository) => repository.setChannelPrivacy(
        channelId: channel.id,
        isPrivate: isPrivate,
        isReadOnly: isReadOnly,
      ),
      failure: 'Could not change channel permissions. Try again.',
    );
  }

  Future<void> _setSlowmode(CircleChannel channel, int seconds) {
    return _run(
      (repository) => repository.setChannelSlowmode(
        channelId: channel.id,
        seconds: seconds,
      ),
      failure: 'Could not change slowmode. Try again.',
    );
  }

  Future<void> _editOverwrite(
    CircleDetail detail,
    CircleChannel channel,
    ChannelOverwriteTarget target,
    CircleChannelOverwrite? overwrite,
  ) async {
    final result = await showChannelOverwriteEditorSheet(
      context,
      target: target,
      overwrite: overwrite,
      editableBits: detail.channelPermissionsOf(channel),
    );
    if (result == null || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.setChannelOverwrite(
        channelId: channel.id,
        roleId: target.role?.id,
        userId: target.member?.profile.id,
        allow: result.allow,
        deny: result.deny,
      ),
      failure: 'Could not save channel permissions. Try again.',
    );
  }

  Future<void> _addOverwrite(
    CircleDetail detail,
    CircleChannel channel,
    List<CircleChannelOverwrite> overwrites,
  ) async {
    final taken = {
      for (final overwrite in overwrites)
        if (overwrite.roleId != null) overwrite.roleId else overwrite.userId,
    };
    final candidates = [
      for (final role in detail.roles)
        if (!taken.contains(role.id) && detail.canEditRoleOverwrite(role))
          ChannelOverwriteTarget.role(role),
      for (final member in detail.members)
        if (!taken.contains(member.profile.id) &&
            detail.canEditMemberOverwrite(member))
          ChannelOverwriteTarget.member(member),
    ];
    final target = await showModalBottomSheet<ChannelOverwriteTarget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _OverwriteTargetPicker(candidates: candidates),
    );
    if (target == null || !mounted) {
      return;
    }
    await _editOverwrite(detail, channel, target, null);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(circleDetailProvider(widget.circleId));
    final loaded = detail.valueOrNull;
    CircleChannel? channel;
    for (final candidate in loaded?.channels ?? const <CircleChannel>[]) {
      if (candidate.id == widget.channelId) {
        channel = candidate;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel settings'),
        bottom: channel == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '# ${channel.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
        data: (detail) {
          final found = channel;
          if (found == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This channel is no longer available.'),
              ),
            );
          }
          return _buildSettings(detail, found);
        },
      ),
    );
  }

  Widget _buildSettings(CircleDetail detail, CircleChannel channel) {
    final children = <Widget>[
      if (detail.canManageChannels) ..._slowmodeSection(channel),
      if (detail.canManageRoles) ..._permissionsSection(detail, channel),
    ];
    if (children.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('You cannot change this channel.'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  List<Widget> _slowmodeSection(CircleChannel channel) {
    final current = channel.slowmodeSeconds;
    final options = [
      ...channelSlowmodeOptions,
      if (!channelSlowmodeOptions.contains(current)) current,
    ]..sort();
    return [
      const _SectionHeader('Slowmode'),
      ListTile(
        title: const Text('Slowmode'),
        subtitle: const Text(
          'How long members wait between messages. Members who can manage '
          'messages are exempt.',
        ),
        trailing: DropdownButton<int>(
          key: const ValueKey('channel-slowmode-dropdown'),
          value: current,
          onChanged: _saving
              ? null
              : (seconds) {
                  if (seconds != null && seconds != current) {
                    _setSlowmode(channel, seconds);
                  }
                },
          items: [
            for (final seconds in options)
              DropdownMenuItem(
                value: seconds,
                child: Text(channelSlowmodeLabel(seconds)),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _permissionsSection(CircleDetail detail, CircleChannel channel) {
    final theme = Theme.of(context);
    CircleRole? everyone;
    for (final role in detail.roles) {
      if (role.isDefault) {
        everyone = role;
      }
    }
    final canEditEveryone =
        !_saving && everyone != null && detail.canEditRoleOverwrite(everyone);
    final overwrites = ref.watch(channelOverwritesProvider(_overwritesKey));

    return [
      const _SectionHeader('Permissions'),
      SwitchListTile(
        key: const ValueKey('channel-private-switch'),
        title: const Text('Private channel'),
        subtitle: const Text(
          'Only roles and members allowed below can see this channel.',
        ),
        value: channel.isPrivate,
        onChanged: canEditEveryone
            ? (value) => _setPrivacy(
                channel,
                isPrivate: value,
                isReadOnly: channel.isReadOnly,
              )
            : null,
      ),
      SwitchListTile(
        key: const ValueKey('channel-read-only-switch'),
        title: const Text('Read-only channel'),
        subtitle: const Text(
          'Only roles and members allowed below can send messages.',
        ),
        value: channel.isReadOnly,
        onChanged:
            canEditEveryone &&
                detail.canInChannel(channel, CirclePermission.sendMessages)
            ? (value) => _setPrivacy(
                channel,
                isPrivate: channel.isPrivate,
                isReadOnly: value,
              )
            : null,
      ),
      if (!canEditEveryone && !_saving)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'You need a role to change permissions for @everyone.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      const _SectionHeader('Advanced'),
      ...overwrites.when(
        loading: () => const [
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
        error: (error, stackTrace) => const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Could not load channel permissions.'),
          ),
        ],
        data: (overwrites) {
          final tiles = <Widget>[
            for (final overwrite in overwrites)
              if (_targetOf(detail, overwrite) case final target?)
                _OverwriteTile(
                  target: target,
                  overwrite: overwrite,
                  onTap: !_saving && target.canEdit(detail)
                      ? () => _editOverwrite(detail, channel, target, overwrite)
                      : null,
                ),
          ];
          if (tiles.isEmpty) {
            return [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'No role or member has its own permissions here yet.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ];
          }
          return tiles;
        },
      ),
      ListTile(
        leading: const Icon(Icons.add),
        title: const Text('Add role or member'),
        enabled: !_saving && overwrites.valueOrNull != null,
        onTap: () => _addOverwrite(detail, channel, overwrites.valueOrNull!),
      ),
    ];
  }

  ChannelOverwriteTarget? _targetOf(
    CircleDetail detail,
    CircleChannelOverwrite overwrite,
  ) {
    if (overwrite.roleId case final roleId?) {
      for (final role in detail.roles) {
        if (role.id == roleId) {
          return ChannelOverwriteTarget.role(role);
        }
      }
    }
    if (overwrite.userId case final userId?) {
      for (final member in detail.members) {
        if (member.profile.id == userId) {
          return ChannelOverwriteTarget.member(member);
        }
      }
    }
    return null;
  }
}

/// The role or member an overwrite applies to.
class ChannelOverwriteTarget {
  const ChannelOverwriteTarget.role(CircleRole this.role) : member = null;

  const ChannelOverwriteTarget.member(CircleMember this.member) : role = null;

  final CircleRole? role;
  final CircleMember? member;

  String get name => role?.name ?? member!.displayName;

  bool canEdit(CircleDetail detail) {
    final role = this.role;
    return role != null
        ? detail.canEditRoleOverwrite(role)
        : detail.canEditMemberOverwrite(member!);
  }

  Widget avatar(BuildContext context) {
    final role = this.role;
    if (role != null) {
      final color = role.color;
      return CircleAvatar(
        radius: 16,
        backgroundColor: color == null
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : circleRoleColor(color),
        child: Icon(
          role.isDefault ? Icons.groups_outlined : Icons.shield_outlined,
          size: 18,
          color: color == null ? null : Colors.white,
        ),
      );
    }
    final name = member!.displayName.trim();
    return CircleAvatar(
      radius: 16,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _OverwriteTile extends StatelessWidget {
  const _OverwriteTile({
    required this.target,
    required this.overwrite,
    required this.onTap,
  });

  final ChannelOverwriteTarget target;
  final CircleChannelOverwrite overwrite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    String names(int bits) => [
      for (final permission in CirclePermission.channelPermissions)
        if (bits & permission.bit != 0) permission.label,
    ].join(', ');
    final allowed = names(overwrite.allow);
    final denied = names(overwrite.deny);

    return ListTile(
      key: ValueKey('channel-overwrite-${overwrite.id}'),
      leading: target.avatar(context),
      title: Text(target.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (allowed.isNotEmpty) 'Allowed: $allowed',
          if (denied.isNotEmpty) 'Denied: $denied',
        ].join(' · '),
      ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _OverwriteTargetPicker extends StatelessWidget {
  const _OverwriteTargetPicker({required this.candidates});

  final List<ChannelOverwriteTarget> candidates;

  @override
  Widget build(BuildContext context) {
    final roles = [
      for (final candidate in candidates)
        if (candidate.role != null) candidate,
    ];
    final members = [
      for (final candidate in candidates)
        if (candidate.member != null) candidate,
    ];
    Widget tile(ChannelOverwriteTarget target) => ListTile(
      leading: target.avatar(context),
      title: Text(target.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).pop(target),
    );

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Add role or member')),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Every role and member you can manage is listed.'),
            ),
          if (roles.isNotEmpty) ...[
            const _SectionHeader('Roles'),
            for (final target in roles) tile(target),
          ],
          if (members.isNotEmpty) ...[
            const _SectionHeader('Members'),
            for (final target in members) tile(target),
          ],
        ],
      ),
    );
  }
}

/// Edits one overwrite with allow / inherit / deny per channel permission.
/// Returns the new bits (both 0 to remove it), or null when cancelled.
/// Permissions outside [editableBits] stay as they are.
Future<({int allow, int deny})?> showChannelOverwriteEditorSheet(
  BuildContext context, {
  required ChannelOverwriteTarget target,
  required CircleChannelOverwrite? overwrite,
  required int editableBits,
}) {
  return showModalBottomSheet<({int allow, int deny})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ChannelOverwriteEditorSheet(
      target: target,
      overwrite: overwrite,
      editableBits: editableBits,
    ),
  );
}

class ChannelOverwriteEditorSheet extends StatefulWidget {
  const ChannelOverwriteEditorSheet({
    required this.target,
    required this.overwrite,
    required this.editableBits,
    super.key,
  });

  final ChannelOverwriteTarget target;
  final CircleChannelOverwrite? overwrite;
  final int editableBits;

  @override
  State<ChannelOverwriteEditorSheet> createState() =>
      _ChannelOverwriteEditorSheetState();
}

class _ChannelOverwriteEditorSheetState
    extends State<ChannelOverwriteEditorSheet> {
  late var _allow = widget.overwrite?.allow ?? 0;
  late var _deny = widget.overwrite?.deny ?? 0;

  void _set(CirclePermission permission, OverwriteState state) {
    setState(() {
      _allow &= ~permission.bit;
      _deny &= ~permission.bit;
      switch (state) {
        case OverwriteState.allow:
          _allow |= permission.bit;
        case OverwriteState.deny:
          _deny |= permission.bit;
        case OverwriteState.inherit:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editable =
        CirclePermission.administrator.isGrantedBy(widget.editableBits)
        ? CirclePermission.all
        : widget.editableBits;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                widget.target.avatar(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.target.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Allow or deny permissions in this channel, or inherit them '
              'from roles.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final permission in CirclePermission.channelPermissions)
              _OverwritePermissionRow(
                permission: permission,
                state: OverwriteState.of(
                  permission,
                  allow: _allow,
                  deny: _deny,
                ),
                onChanged: editable & permission.bit != 0
                    ? (state) => _set(permission, state)
                    : null,
              ),
            const SizedBox(height: 12),
            OverflowBar(
              spacing: 8,
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                if (widget.overwrite != null)
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop((allow: 0, deny: 0)),
                    child: const Text('Remove'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop((allow: _allow, deny: _deny)),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverwritePermissionRow extends StatelessWidget {
  const _OverwritePermissionRow({
    required this.permission,
    required this.state,
    required this.onChanged,
  });

  final CirclePermission permission;
  final OverwriteState state;
  final ValueChanged<OverwriteState>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onChanged = this.onChanged;
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(permission.label, style: theme.textTheme.bodyLarge),
        Text(permission.description, style: theme.textTheme.bodySmall),
      ],
    );
    final choice = SegmentedButton<OverwriteState>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: OverwriteState.deny,
          icon: Icon(Icons.close),
          tooltip: 'Deny',
        ),
        ButtonSegment(
          value: OverwriteState.inherit,
          icon: Icon(Icons.horizontal_rule),
          tooltip: 'Inherit',
        ),
        ButtonSegment(
          value: OverwriteState.allow,
          icon: Icon(Icons.check),
          tooltip: 'Allow',
        ),
      ],
      selected: {state},
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged(selection.single),
    );
    return Padding(
      key: ValueKey('overwrite-row-${permission.key}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      // Phones put the choice under the description.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 480
            ? Row(
                children: [
                  Expanded(child: labels),
                  const SizedBox(width: 8),
                  choice,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labels,
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: choice,
                  ),
                ],
              ),
      ),
    );
  }
}
