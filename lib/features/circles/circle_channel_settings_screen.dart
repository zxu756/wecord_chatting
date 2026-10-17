import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/announcement_widgets.dart';
import 'package:wecord/features/circles/channel_webhooks_section.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/voice/voice_user_limit_section.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/ui/ui.dart';

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
    final confirmed = await showCircleDialog<bool>(
      context,
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
    final target = await showCircleChannelPanel<ChannelOverwriteTarget>(
      context,
      title: tr('Add role or member'),
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
    final loaded = detail.value;
    CircleChannel? channel;
    for (final candidate in loaded?.channels ?? const <CircleChannel>[]) {
      if (candidate.id == widget.channelId) {
        channel = candidate;
      }
    }

    return CirclePageScaffold(
      title: tr('Channel settings'),
      subtitle: channel == null
          ? null
          : channel.isForum || channel.isVoice
          ? channel.name
          : '# ${channel.name}',
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(tr(error.toString()))),
        data: (detail) {
          final found = channel;
          if (found == null) {
            return CircleEmptyState(
              icon: Icons.tag,
              title: tr('This channel is no longer available.'),
            );
          }
          return _buildSettings(detail, found);
        },
      ),
    );
  }

  Widget _buildSettings(CircleDetail detail, CircleChannel channel) {
    final c = context.tokens.colors;
    final children = <Widget>[
      if (detail.canManageChannels) ...[
        SettingsSectionHeader(tr('Overview')),
        CircleCard(
          child: ChannelOverviewForm(
            key: ValueKey('channel-overview-${channel.id}'),
            channel: channel,
            enabled: !_saving,
            onSave: (name, topic) =>
                _saveOverview(channel, name: name, topic: topic),
          ),
        ),
        // Voice channels have a text chat too, with its own slowmode.
        if (channel.isForum)
          ..._forumTagsSection(channel)
        else
          ..._slowmodeSection(channel),
        // Stages have no user limit.
        if (channel.kind == CircleChannelKind.voice) ...[
          const SizedBox(height: 16),
          SettingsGroup(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              VoiceUserLimitSection(
                key: ValueKey('voice-user-limit-${channel.id}'),
                circleId: widget.circleId,
                channelId: channel.id,
                enabled: !_saving,
              ),
            ],
          ),
        ],
      ],
      if (detail.canManageChannels && channel.isTextLike) ...[
        const SizedBox(height: 12),
        SettingsGroup(
          children: [
            AnnouncementChannelSwitch(
              key: ValueKey('channel-announcement-${channel.id}'),
              channel: channel,
              onChanged: () =>
                  ref.invalidate(circleDetailProvider(widget.circleId)),
            ),
          ],
        ),
      ],
      if (detail.canManageRoles) ..._permissionsSection(detail, channel),
      if (channel.isTextLike &&
          detail.canInChannel(channel, CirclePermission.manageWebhooks))
        FollowedChannelsSection(
          key: ValueKey('channel-follows-${channel.id}'),
          channel: channel,
        ),
      // Announcement channels take webhooks too; publishing stays manual.
      if (channel.isTextLike &&
          detail.canInChannel(channel, CirclePermission.manageWebhooks))
        ChannelWebhooksSection(
          key: ValueKey('channel-webhooks-${channel.id}'),
          channel: channel,
        ),
      if (detail.canManageChannels) ...[
        const SizedBox(height: 24),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const ValueKey('channel-delete-button'),
              icon: Icons.delete_outline,
              title: tr('Delete channel'),
              destructive: true,
              showChevron: false,
              onTap: _saving ? null : () => _delete(channel),
            ),
          ],
        ),
      ],
    ];
    if (children.isEmpty) {
      return CircleEmptyState(
        icon: Icons.lock_outline,
        title: tr('You cannot change this channel.'),
      );
    }
    return DefaultTextStyle.merge(
      style: TextStyle(color: c.ink),
      child: ListView(padding: circlePagePadding(context), children: children),
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
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Delete tag'),
      message: tr('Delete "{tag}"? Posts lose this tag.', {'tag': tag.label}),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) {
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
    final c = context.tokens.colors;
    final tags = channel.tags;
    return [
      SettingsSectionHeader(tr('Forum tags')),
      SettingsGroup(
        separatorIndent: 14,
        children: [
          if (tags.isNotEmpty)
            ReorderableListView(
              key: const ValueKey('forum-tags-list'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Material(
                color: c.panel,
                elevation: 0,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
                child: child,
              ),
              onReorderItem: (oldIndex, newIndex) =>
                  _reorderTags(channel, oldIndex, newIndex),
              children: [
                for (final (index, tag) in tags.indexed)
                  _ForumTagRow(
                    key: ValueKey('forum-tag-${tag.id}'),
                    tag: tag,
                    index: index,
                    enabled: !_saving,
                    onEdit: () => _editTag(tag),
                    onDelete: () => _deleteTag(tag),
                  ),
              ],
            ),
          SettingsRow(
            key: const ValueKey('forum-add-tag'),
            icon: Icons.add_rounded,
            tone: SettingsTone.accent,
            title: tr('Add tag'),
            showChevron: false,
            onTap: !_saving && tags.length < ForumTag.maxPerForum
                ? () => _addTag(channel)
                : null,
          ),
        ],
      ),
      _GroupFooter(
        tr(
          'Posts can carry up to {max} tags, and members filter the forum '
          'by them. {count}/{limit} tags.',
          {
            'max': ForumTag.maxPerPost,
            'count': tags.length,
            'limit': ForumTag.maxPerForum,
          },
        ),
      ),
    ];
  }

  Future<void> _chooseSlowmode(
    CircleChannel channel,
    List<int> options,
    Offset? position,
  ) async {
    final current = channel.slowmodeSeconds;
    final seconds = await showCircleActionMenu<int>(
      context,
      title: tr('Slowmode'),
      position: position,
      items: [
        for (final seconds in options)
          CircleMenuItem(
            value: seconds,
            icon: seconds == current
                ? Icons.check_rounded
                : seconds == 0
                ? Icons.timer_off_outlined
                : Icons.timer_outlined,
            tone: seconds == current
                ? SettingsTone.accent
                : SettingsTone.neutral,
            label: channelSlowmodeLabel(seconds),
          ),
      ],
    );
    if (seconds != null && seconds != current && mounted) {
      await _setSlowmode(channel, seconds);
    }
  }

  List<Widget> _slowmodeSection(CircleChannel channel) {
    final current = channel.slowmodeSeconds;
    final options = [
      ...channelSlowmodeOptions,
      if (!channelSlowmodeOptions.contains(current)) current,
    ]..sort();
    return [
      const SizedBox(height: 16),
      SettingsGroup(
        children: [
          Builder(
            builder: (rowContext) => SettingsRow(
              key: const ValueKey('channel-slowmode-dropdown'),
              icon: Icons.timer_outlined,
              title: tr('Slowmode'),
              value: channelSlowmodeLabel(current),
              onTap: _saving
                  ? null
                  : () {
                      final box = rowContext.findRenderObject() as RenderBox?;
                      _chooseSlowmode(
                        channel,
                        options,
                        box?.localToGlobal(box.size.centerRight(Offset.zero)),
                      );
                    },
            ),
          ),
        ],
      ),
      _GroupFooter(
        tr(
          'How long members wait between messages. Members who can manage '
          'messages are exempt.',
        ),
      ),
    ];
  }

  List<Widget> _permissionsSection(CircleDetail detail, CircleChannel channel) {
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
      SettingsSectionHeader(tr('Permissions')),
      SettingsGroup(
        children: [
          SettingsRow.toggle(
            key: const ValueKey('channel-private-switch'),
            icon: Icons.lock_outline,
            title: tr('Private channel'),
            subtitle: tr(
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
          SettingsRow.toggle(
            key: const ValueKey('channel-read-only-switch'),
            icon: Icons.edit_off_outlined,
            title: tr('Read-only channel'),
            subtitle: tr(
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
        ],
      ),
      if (!canEditEveryone && !_saving)
        _GroupFooter(
          tr('You need a role to change permissions for @everyone.'),
        ),
      SettingsSectionHeader(tr('Advanced')),
      SettingsGroup(
        separatorIndent: 58,
        children: [
          ...overwrites.when(
            loading: () => const [
              Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (error, stackTrace) => [
              _GroupNote(tr('Could not load channel permissions.')),
            ],
            data: (overwrites) {
              final tiles = <Widget>[
                for (final overwrite in overwrites)
                  if (_targetOf(detail, overwrite) case final target?)
                    _OverwriteTile(
                      target: target,
                      overwrite: overwrite,
                      onTap: !_saving && target.canEdit(detail)
                          ? () => _editOverwrite(
                              detail,
                              channel,
                              target,
                              overwrite,
                            )
                          : null,
                    ),
              ];
              if (tiles.isEmpty) {
                return [
                  _GroupNote(
                    tr('No role or member has its own permissions here yet.'),
                  ),
                ];
              }
              return tiles;
            },
          ),
          SettingsRow(
            icon: Icons.add_rounded,
            tone: SettingsTone.accent,
            title: tr('Add role or member'),
            showChevron: false,
            onTap: !_saving && overwrites.value != null
                ? () => _addOverwrite(detail, channel, overwrites.value!)
                : null,
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('channel-name-field'),
          controller: _nameController,
          enabled: widget.enabled,
          maxLength: CircleChannel.maxNameLength,
          label: tr('Channel name'),
          errorText: nameError,
        ),
        const SizedBox(height: 8),
        WeCordTextField(
          fieldKey: const ValueKey('channel-topic-field'),
          controller: _topicController,
          enabled: widget.enabled,
          minLines: 1,
          maxLines: 4,
          maxLength: CircleChannel.maxTopicLength,
          label: tr('Topic'),
          hint: tr('Let everyone know what this channel is about'),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: WeCordButton(
            key: const ValueKey('channel-overview-save'),
            label: tr('Save'),
            onPressed: widget.enabled && _dirty && nameError == null
                ? () => widget.onSave(_name, _topic)
                : null,
          ),
        ),
      ],
    );
  }
}

/// Shows [builder]'s content as a sheet on phones and as a centred rounded
/// panel on wide screens. The content sizes itself and scrolls inside.
Future<T?> showCircleChannelPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  double maxWidth = 480,
}) {
  if (!circleWideLayout(context)) {
    return showWeCordSheet<T>(
      context,
      title: title,
      builder: (context, _) => builder(context),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) {
      final tokens = context.tokens;
      final c = tokens.colors;
      return Dialog(
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.xxl),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
              Flexible(child: builder(context)),
            ],
          ),
        ),
      );
    },
  );
}

/// Bottom space for a panel's content: the safe area and keyboard on
/// phones, a little padding on wide screens.
double circleChannelPanelBottom(BuildContext context) =>
    circleWideLayout(context)
    ? 20
    : 16 +
          MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.paddingOf(context).bottom;

/// Asks for a forum tag's name and emoji. Returns them trimmed (a blank
/// emoji as null), or null when cancelled.
Future<({String name, String? emoji})?> showForumTagDialog(
  BuildContext context, {
  ForumTag? tag,
}) {
  return showCircleDialog<({String name, String? emoji})>(
    context,
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
    return CircleDialog(
      title: widget.tag == null ? tr('Add tag') : tr('Edit tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('forum-tag-name-field'),
            controller: _nameController,
            autofocus: true,
            maxLength: ForumTag.maxNameLength,
            label: tr('Name'),
            errorText: _errorText,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          WeCordTextField(
            fieldKey: const ValueKey('forum-tag-emoji-field'),
            controller: _emojiController,
            maxLength: 8,
            label: tr('Emoji (optional)'),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          label: widget.tag == null ? tr('Add') : tr('Save'),
          onPressed: _save,
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
    return CircleDialog(
      title: tr('Delete channel'),
      message: switch (widget.channel.kind) {
        CircleChannelKind.forum => tr(
          'Delete #{name} with all of its posts? This cannot be undone.',
          {'name': name},
        ),
        CircleChannelKind.voice => tr(
          'Delete the voice channel {name}? Everyone in it is '
          'disconnected. This cannot be undone.',
          {'name': name},
        ),
        CircleChannelKind.stage => tr(
          'Delete the stage {name}? Everyone on it is disconnected. '
          'This cannot be undone.',
          {'name': name},
        ),
        CircleChannelKind.text || CircleChannelKind.announcement => tr(
          'Delete #{name} with all of its messages and threads? This '
          'cannot be undone.',
          {'name': name},
        ),
      },
      content: WeCordTextField(
        fieldKey: const ValueKey('channel-delete-confirm-field'),
        controller: _controller,
        autofocus: true,
        label: tr('Type the channel name'),
        hint: name,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_matches) {
            Navigator.of(context).pop(true);
          }
        },
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CircleDialogAction.danger(
          label: tr('Delete'),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
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

  Widget avatar(BuildContext context, {double size = 32}) {
    final c = context.tokens.colors;
    final role = this.role;
    if (role != null) {
      final color = role.color;
      return ThingAvatar(
        size: size,
        icon: role.isDefault ? Icons.groups_outlined : CircleIcons.roles,
        color: color == null ? c.raised : circleRoleColor(color),
        foregroundColor: color == null ? c.ink : Colors.white,
      );
    }
    final member = this.member!;
    return CircleNetworkAvatar(
      name: member.displayName,
      url: member.profile.avatarUrl,
      size: size,
    );
  }
}

/// A muted note under a group of settings.
class _GroupFooter extends StatelessWidget {
  const _GroupFooter(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          color: context.tokens.colors.muted,
          height: 1.4,
        ),
      ),
    );
  }
}

/// A line of muted text inside a group, for empty and error states.
class _GroupNote extends StatelessWidget {
  const _GroupNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(
        text,
        style: TextStyle(fontSize: 13.5, color: context.tokens.colors.muted),
      ),
    );
  }
}

/// A forum tag in channel settings: drag handle, label, edit and delete.
class _ForumTagRow extends StatelessWidget {
  const _ForumTagRow({
    required this.tag,
    required this.index,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final ForumTag tag;
  final int index;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            enabled: enabled,
            child: SizedBox.square(
              dimension: minTouchTargetSize,
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 20,
                color: c.faint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              tag.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          WeCordIconButton(
            tooltip: tr('Edit tag'),
            icon: Icons.edit_outlined,
            variant: WeCordButtonVariant.ghost,
            size: 36,
            iconSize: 18,
            onPressed: enabled ? onEdit : null,
          ),
          WeCordIconButton(
            tooltip: tr('Delete tag'),
            icon: Icons.delete_outline,
            variant: WeCordButtonVariant.ghost,
            size: 36,
            iconSize: 18,
            onPressed: enabled ? onDelete : null,
          ),
        ],
      ),
    );
  }
}

/// A role or member with its own permissions in the channel.
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
    return _TargetRow(
      key: ValueKey('channel-overwrite-${overwrite.id}'),
      target: target,
      subtitle: [
        if (allowed.isNotEmpty)
          tr('Allowed: {permissions}', {'permissions': allowed}),
        if (denied.isNotEmpty)
          tr('Denied: {permissions}', {'permissions': denied}),
      ].join(' · '),
      onTap: onTap,
      chevron: onTap != null,
    );
  }
}

/// A role or member row: avatar, name, optional subtitle and chevron.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.target,
    required this.onTap,
    this.subtitle,
    this.chevron = false,
    super.key,
  });

  final ChannelOverwriteTarget target;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final subtitle = this.subtitle;
    final roleColor = target.role?.color;
    return WeCordPressable(
      onPressed: onTap,
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
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              target.avatar(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      target.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: roleColor == null
                            ? c.ink
                            : circleRoleColor(roleColor),
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Picks a role or member to give their own permissions in the channel.
class _OverwriteTargetPicker extends StatelessWidget {
  const _OverwriteTargetPicker({required this.candidates});

  final List<ChannelOverwriteTarget> candidates;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final roles = [
      for (final candidate in candidates)
        if (candidate.role != null) candidate,
    ];
    final members = [
      for (final candidate in candidates)
        if (candidate.member != null) candidate,
    ];
    Widget group(List<ChannelOverwriteTarget> targets) => SettingsGroup(
      color: c.well,
      separatorIndent: 58,
      children: [
        for (final target in targets)
          _TargetRow(
            target: target,
            onTap: () => Navigator.of(context).pop(target),
          ),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        circleChannelPanelBottom(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                tr('Every role and member you can manage is listed.'),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ),
          if (roles.isNotEmpty) ...[
            SettingsSectionHeader(tr('Roles')),
            group(roles),
          ],
          if (members.isNotEmpty) ...[
            SettingsSectionHeader(tr('Members')),
            group(members),
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
  return showCircleChannelPanel<({int allow, int deny})>(
    context,
    maxWidth: 560,
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
    final c = context.tokens.colors;
    final wide = circleWideLayout(context);
    final editable =
        CirclePermission.administrator.isGrantedBy(widget.editableBits)
        ? CirclePermission.all
        : widget.editableBits;
    final permissions = CirclePermission.channelPermissions;
    final remove = widget.overwrite == null
        ? null
        : WeCordButton(
            label: tr('Remove'),
            variant: wide
                ? WeCordButtonVariant.ghost
                : WeCordButtonVariant.secondary,
            expand: !wide,
            onPressed: () => Navigator.of(context).pop((allow: 0, deny: 0)),
          );
    final cancel = WeCordButton(
      label: tr('Cancel'),
      variant: WeCordButtonVariant.secondary,
      expand: !wide,
      onPressed: () => Navigator.of(context).pop(),
    );
    final save = WeCordButton(
      label: tr('Save'),
      expand: !wide,
      size: wide ? WeCordButtonSize.medium : WeCordButtonSize.large,
      onPressed: () => Navigator.of(context).pop((allow: _allow, deny: _deny)),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, wide ? 22 : 4, 20, 4),
          child: Row(
            children: [
              widget.target.avatar(context, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.target.name,
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            tr(
              'Allow or deny permissions in this channel, or inherit them '
              'from roles.',
            ),
            style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SettingsGroup(
              color: c.well,
              separatorIndent: 14,
              children: [
                for (final permission in permissions)
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
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.lineSoft)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            circleChannelPanelBottom(context) - 4,
          ),
          child: wide
              ? Row(
                  children: [
                    ?remove,
                    const Spacer(),
                    cancel,
                    const SizedBox(width: 8),
                    save,
                  ],
                )
              // Phones stack a full-width Save over the quieter actions.
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    save,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (remove != null) ...[
                          Expanded(child: remove),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: cancel),
                      ],
                    ),
                  ],
                ),
        ),
      ],
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
    final c = context.tokens.colors;
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          permission.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: onChanged == null ? c.muted : c.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          permission.description,
          style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.35),
        ),
      ],
    );
    final choice = ChannelOverwriteChoice(state: state, onChanged: onChanged);
    return Padding(
      key: ValueKey('overwrite-row-${permission.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      // Phones put the choice under the description.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 420
            ? Row(
                children: [
                  Expanded(child: labels),
                  const SizedBox(width: 12),
                  choice,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labels,
                  const SizedBox(height: 8),
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

/// Deny / inherit / allow for one permission: three round buttons on a
/// raised track; the chosen one fills red, white or green.
class ChannelOverwriteChoice extends StatelessWidget {
  const ChannelOverwriteChoice({
    required this.state,
    required this.onChanged,
    super.key,
  });

  final OverwriteState state;

  /// Null when the permission is not the current user's to change.
  final ValueChanged<OverwriteState>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final onChanged = this.onChanged;
    final touch = usesTouchInput(context);
    Widget option(
      OverwriteState value,
      IconData icon,
      String tooltip,
      Color fill,
      Color foreground,
    ) {
      final selected = value == state;
      return WeCordPressable(
        tooltip: tooltip,
        semanticLabel: tooltip,
        selected: selected,
        shape: const CircleBorder(),
        pressedScale: 0.92,
        onPressed: onChanged == null
            ? null
            : () {
                WeCordHaptics.selection();
                onChanged(value);
              },
        builder: (context, states) => SizedBox.square(
          dimension: touch ? minTouchTargetSize : 36,
          child: Center(
            child: AnimatedContainer(
              duration: WeCordMotion.quick,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? fill : fill.withValues(alpha: 0),
                boxShadow: selected && value == OverwriteState.inherit
                    ? tokens.shadows.hairline
                    : null,
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? foreground : c.subtle,
              ),
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(WeCordRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
              OverwriteState.deny,
              Icons.close_rounded,
              tr('Deny'),
              c.danger,
              c.onDanger,
            ),
            option(
              OverwriteState.inherit,
              Icons.horizontal_rule_rounded,
              tr('Inherit'),
              tokens.isDark ? c.raisedStrong : c.panel,
              c.ink,
            ),
            option(
              OverwriteState.allow,
              Icons.check_rounded,
              tr('Allow'),
              c.success,
              Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
