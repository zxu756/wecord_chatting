import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/channel_webhooks_section.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/forum.dart';

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
    return tr('Off');
  }
  if (seconds % 3600 == 0) {
    return tr('{hours}h', {'hours': seconds ~/ 3600});
  }
  if (seconds % 60 == 0) {
    return tr('{minutes}m', {'minutes': seconds ~/ 60});
  }
  return tr('{seconds}s', {'seconds': seconds});
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

/// Channel settings. Members who can manage channels rename the channel,
/// set its topic and slowmode, or delete it; members who can manage roles
/// make the channel private or read-only for `@everyone` and give roles and
/// members their own permissions in it.
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
      failure: tr('Could not change channel permissions. Try again.'),
    );
  }

  Future<void> _saveOverview(
    CircleChannel channel, {
    required String name,
    required String? topic,
  }) {
    return _run(
      (repository) => repository.updateChannel(
        channelId: channel.id,
        name: name,
        topic: topic,
      ),
      failure: tr('Could not save the channel. Try again.'),
    );
  }

  Future<void> _delete(CircleChannel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteChannelDialog(channel: channel),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(circlesRepositoryProvider).deleteChannel(channel.id);
      ref.invalidate(circleDetailProvider(widget.circleId));
      ref.invalidate(conversationsProvider);
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Deleted #{name}.', {'name': channel.name}))),
      );
      if (mounted) {
        navigator.pop();
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not delete the channel. Try again.'))),
      );
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _setSlowmode(CircleChannel channel, int seconds) {
    return _run(
      (repository) => repository.setChannelSlowmode(
        channelId: channel.id,
        seconds: seconds,
      ),
      failure: tr('Could not change slowmode. Try again.'),
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
      failure: tr('Could not save channel permissions. Try again.'),
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
        title: Text(tr('Channel settings')),
        bottom: channel == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      channel.isForum || channel.isVoice
                          ? channel.name
                          : '# ${channel.name}',
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
        error: (error, stackTrace) => Center(child: Text(tr(error.toString()))),
        data: (detail) {
          final found = channel;
          if (found == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('This channel is no longer available.')),
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
      if (detail.canManageChannels) ...[
        _SectionHeader(tr('Overview')),
        ChannelOverviewForm(
          key: ValueKey('channel-overview-${channel.id}'),
          channel: channel,
          enabled: !_saving,
          onSave: (name, topic) =>
              _saveOverview(channel, name: name, topic: topic),
        ),
        if (channel.isForum)
          ..._forumTagsSection(channel)
        else if (!channel.isVoice)
          ..._slowmodeSection(channel),
      ],
      if (detail.canManageRoles) ..._permissionsSection(detail, channel),
      if (channel.kind == CircleChannelKind.text &&
          detail.canInChannel(channel, CirclePermission.manageWebhooks))
        ChannelWebhooksSection(
          key: ValueKey('channel-webhooks-${channel.id}'),
          channel: channel,
        ),
      if (detail.canManageChannels) ...[
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const ValueKey('channel-delete-button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _saving ? null : () => _delete(channel),
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('Delete channel')),
            ),
          ),
        ),
      ],
    ];
    if (children.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('You cannot change this channel.')),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  Future<void> _addTag(CircleChannel channel) async {
    final result = await showForumTagDialog(context);
    if (result == null || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.createForumTag(
        channelId: channel.id,
        name: result.name,
        emoji: result.emoji,
      ),
      failure: tr('Could not add the tag. Try again.'),
    );
  }

  Future<void> _editTag(ForumTag tag) async {
    final result = await showForumTagDialog(context, tag: tag);
    if (result == null || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.updateForumTag(
        tagId: tag.id,
        name: result.name,
        emoji: result.emoji,
      ),
      failure: tr('Could not save the tag. Try again.'),
    );
  }

  Future<void> _deleteTag(ForumTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Delete tag')),
        content: Text(
          tr('Delete "{tag}"? Posts lose this tag.', {'tag': tag.label}),
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
    await _run(
      (repository) => repository.deleteForumTag(tag.id),
      failure: tr('Could not delete the tag. Try again.'),
    );
  }

  Future<void> _reorderTags(
    CircleChannel channel,
    int oldIndex,
    int newIndex,
  ) async {
    final tags = [...channel.tags];
    final moved = tags.removeAt(oldIndex);
    tags.insert(newIndex.clamp(0, tags.length), moved);
    await _run(
      (repository) => repository.reorderForumTags(
        channelId: channel.id,
        tagIds: [for (final tag in tags) tag.id],
      ),
      failure: tr('Could not reorder the tags. Try again.'),
    );
  }

  List<Widget> _forumTagsSection(CircleChannel channel) {
    final theme = Theme.of(context);
    final tags = channel.tags;
    return [
      _SectionHeader(tr('Forum tags')),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          tr(
            'Posts can carry up to {max} tags, and members filter the forum '
            'by them. {count}/{limit} tags.',
            {
              'max': ForumTag.maxPerPost,
              'count': tags.length,
              'limit': ForumTag.maxPerForum,
            },
          ),
          style: theme.textTheme.bodySmall,
        ),
      ),
      ReorderableListView(
        key: const ValueKey('forum-tags-list'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (oldIndex, newIndex) =>
            _reorderTags(channel, oldIndex, newIndex),
        children: [
          for (final (index, tag) in tags.indexed)
            ListTile(
              key: ValueKey('forum-tag-${tag.id}'),
              leading: ReorderableDragStartListener(
                index: index,
                enabled: !_saving,
                child: const Icon(Icons.drag_indicator),
              ),
              title: Text(
                tag.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr('Edit tag'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _saving ? null : () => _editTag(tag),
                  ),
                  IconButton(
                    tooltip: tr('Delete tag'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _saving ? null : () => _deleteTag(tag),
                  ),
                ],
              ),
            ),
        ],
      ),
      ListTile(
        key: const ValueKey('forum-add-tag'),
        leading: const Icon(Icons.add),
        title: Text(tr('Add tag')),
        enabled: !_saving && tags.length < ForumTag.maxPerForum,
        onTap: () => _addTag(channel),
      ),
    ];
  }

  List<Widget> _slowmodeSection(CircleChannel channel) {
    final current = channel.slowmodeSeconds;
    final options = [
      ...channelSlowmodeOptions,
      if (!channelSlowmodeOptions.contains(current)) current,
    ]..sort();
    return [
      _SectionHeader(tr('Slowmode')),
      ListTile(
        title: Text(tr('Slowmode')),
        subtitle: Text(
          tr(
            'How long members wait between messages. Members who can manage '
            'messages are exempt.',
          ),
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
      _SectionHeader(tr('Permissions')),
      SwitchListTile(
        key: const ValueKey('channel-private-switch'),
        title: Text(tr('Private channel')),
        subtitle: Text(
          tr('Only roles and members allowed below can see this channel.'),
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
        title: Text(tr('Read-only channel')),
        subtitle: Text(
          tr('Only roles and members allowed below can send messages.'),
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
            tr('You need a role to change permissions for @everyone.'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      _SectionHeader(tr('Advanced')),
      ...overwrites.when(
        loading: () => const [
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
        error: (error, stackTrace) => [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(tr('Could not load channel permissions.')),
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
                  tr('No role or member has its own permissions here yet.'),
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
        title: Text(tr('Add role or member')),
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

/// The channel's name and topic, saved together.
class ChannelOverviewForm extends StatefulWidget {
  const ChannelOverviewForm({
    required this.channel,
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final CircleChannel channel;
  final bool enabled;
  final Future<void> Function(String name, String? topic) onSave;

  @override
  State<ChannelOverviewForm> createState() => _ChannelOverviewFormState();
}

class _ChannelOverviewFormState extends State<ChannelOverviewForm> {
  late final _nameController = TextEditingController(text: widget.channel.name);
  late final _topicController = TextEditingController(
    text: widget.channel.topic ?? '',
  );

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_changed);
    _topicController.addListener(_changed);
  }

  @override
  void didUpdateWidget(ChannelOverviewForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Take the server's values unless they are being edited.
    final name = widget.channel.name;
    if (_nameController.text == oldWidget.channel.name &&
        _nameController.text != name) {
      _nameController.text = name;
    }
    final topic = widget.channel.topic ?? '';
    if (_topicController.text == (oldWidget.channel.topic ?? '') &&
        _topicController.text != topic) {
      _topicController.text = topic;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  String get _name => _nameController.text.trim();

  String? get _topic {
    final topic = _topicController.text.trim();
    return topic.isEmpty ? null : topic;
  }

  bool get _dirty =>
      _name != widget.channel.name || _topic != widget.channel.topic;

  @override
  Widget build(BuildContext context) {
    final nameError = _name.isEmpty ? tr('Channel name is required.') : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('channel-name-field'),
            controller: _nameController,
            enabled: widget.enabled,
            maxLength: CircleChannel.maxNameLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Channel name'),
              errorText: nameError,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('channel-topic-field'),
            controller: _topicController,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: 4,
            maxLength: CircleChannel.maxTopicLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Topic'),
              hintText: tr('Let everyone know what this channel is about'),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const ValueKey('channel-overview-save'),
              onPressed: widget.enabled && _dirty && nameError == null
                  ? () => widget.onSave(_name, _topic)
                  : null,
              child: Text(tr('Save')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a forum tag's name and emoji. Returns them trimmed (a blank
/// emoji as null), or null when cancelled.
Future<({String name, String? emoji})?> showForumTagDialog(
  BuildContext context, {
  ForumTag? tag,
}) {
  return showDialog<({String name, String? emoji})>(
    context: context,
    builder: (context) => _ForumTagDialog(tag: tag),
  );
}

class _ForumTagDialog extends StatefulWidget {
  const _ForumTagDialog({this.tag});

  final ForumTag? tag;

  @override
  State<_ForumTagDialog> createState() => _ForumTagDialogState();
}

class _ForumTagDialogState extends State<_ForumTagDialog> {
  late final _nameController = TextEditingController(text: widget.tag?.name);
  late final _emojiController = TextEditingController(text: widget.tag?.emoji);
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = tr('Tag name is required.'));
      return;
    }
    final emoji = _emojiController.text.trim();
    Navigator.of(
      context,
    ).pop((name: name, emoji: emoji.isEmpty ? null : emoji));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.tag == null ? tr('Add tag') : tr('Edit tag')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('forum-tag-name-field'),
            controller: _nameController,
            autofocus: true,
            maxLength: ForumTag.maxNameLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Name'),
              errorText: _errorText,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('forum-tag-emoji-field'),
            controller: _emojiController,
            maxLength: 8,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Emoji (optional)'),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.tag == null ? tr('Add') : tr('Save')),
        ),
      ],
    );
  }
}

/// Confirms deleting a channel by typing its name.
class _DeleteChannelDialog extends StatefulWidget {
  const _DeleteChannelDialog({required this.channel});

  final CircleChannel channel;

  @override
  State<_DeleteChannelDialog> createState() => _DeleteChannelDialogState();
}

class _DeleteChannelDialogState extends State<_DeleteChannelDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim() == widget.channel.name;

  @override
  Widget build(BuildContext context) {
    final name = widget.channel.name;
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Delete channel')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (widget.channel.kind) {
            CircleChannelKind.forum => tr(
              'Delete #{name} with all of its posts? This cannot be undone.',
              {'name': name},
            ),
            CircleChannelKind.voice => tr(
              'Delete the voice channel {name}? Everyone in it is '
              'disconnected. This cannot be undone.',
              {'name': name},
            ),
            CircleChannelKind.text => tr(
              'Delete #{name} with all of its messages and threads? This '
              'cannot be undone.',
              {'name': name},
            ),
          }),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('channel-delete-confirm-field'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Type the channel name'),
              hintText: name,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_matches) {
                Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(tr('Delete')),
        ),
      ],
    );
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
          if (allowed.isNotEmpty)
            tr('Allowed: {permissions}', {'permissions': allowed}),
          if (denied.isNotEmpty)
            tr('Denied: {permissions}', {'permissions': denied}),
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
          ListTile(title: Text(tr('Add role or member'))),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                tr('Every role and member you can manage is listed.'),
              ),
            ),
          if (roles.isNotEmpty) ...[
            _SectionHeader(tr('Roles')),
            for (final target in roles) tile(target),
          ],
          if (members.isNotEmpty) ...[
            _SectionHeader(tr('Members')),
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
              tr(
                'Allow or deny permissions in this channel, or inherit them '
                'from roles.',
              ),
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
                    child: Text(tr('Remove')),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop((allow: _allow, deny: _deny)),
                  child: Text(tr('Save')),
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
      segments: [
        ButtonSegment(
          value: OverwriteState.deny,
          icon: const Icon(Icons.close),
          tooltip: tr('Deny'),
        ),
        ButtonSegment(
          value: OverwriteState.inherit,
          icon: const Icon(Icons.horizontal_rule),
          tooltip: tr('Inherit'),
        ),
        ButtonSegment(
          value: OverwriteState.allow,
          icon: const Icon(Icons.check),
          tooltip: tr('Allow'),
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
