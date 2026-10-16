import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/announcement_repository.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message_origin.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Channel settings: turns a text channel into an announcement channel
/// and back.
class AnnouncementChannelSwitch extends ConsumerStatefulWidget {
  const AnnouncementChannelSwitch({
    required this.channel,
    required this.onChanged,
    super.key,
  });

  final CircleChannel channel;
  final VoidCallback onChanged;

  @override
  ConsumerState<AnnouncementChannelSwitch> createState() =>
      _AnnouncementChannelSwitchState();
}

class _AnnouncementChannelSwitchState
    extends ConsumerState<AnnouncementChannelSwitch> {
  var _busy = false;
  bool? _value;

  Future<void> _set(bool enabled) async {
    if (!enabled) {
      final confirmed = await showCircleDialog<bool>(
        context,
        builder: (context) => CircleDialog(
          title: tr('Turn off announcements?'),
          message: tr(
            'Channels that follow #{name} stop receiving its posts, and '
            'their follows are removed.',
            {'name': widget.channel.name},
          ),
          actions: [
            CircleDialogAction(
              label: tr('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            CircleDialogAction.danger(
              key: const ValueKey('announcement-off-confirm'),
              label: tr('Turn off'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _value = enabled;
    });
    try {
      await ref
          .read(announcementRepositoryProvider)
          .setAnnouncementChannel(
            channelId: widget.channel.id,
            enabled: enabled,
          );
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        setState(() => _value = null);
      }
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not change the channel. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// A settings row: place it in a [SettingsGroup].
  @override
  Widget build(BuildContext context) {
    return SettingsRow.toggle(
      key: const ValueKey('announcement-channel-switch'),
      icon: Icons.campaign_outlined,
      tone: SettingsTone.accent,
      title: tr('Announcement channel'),
      subtitle: tr('Posts here can be published to channels that follow it.'),
      value: _value ?? widget.channel.isAnnouncement,
      onChanged: _busy ? null : (value) => unawaited(_set(value)),
    );
  }
}

/// Channel settings: the announcement channels this channel follows, with
/// a way to unfollow each.
class FollowedChannelsSection extends ConsumerWidget {
  const FollowedChannelsSection({required this.channel, super.key});

  final CircleChannel channel;

  Future<void> _unfollow(
    BuildContext context,
    WidgetRef ref,
    ChannelFollow follow,
  ) async {
    final confirmed = await showCircleDialog<bool>(
      context,
      builder: (context) => CircleDialog(
        title: tr('Unfollow channel'),
        message: tr('Stop receiving posts from #{channel} in {circle}?', {
          'channel': follow.sourceChannelName,
          'circle': follow.sourceCircleName,
        }),
        actions: [
          CircleDialogAction(
            label: tr('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CircleDialogAction.danger(
            key: const ValueKey('unfollow-confirm'),
            label: tr('Unfollow'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(announcementRepositoryProvider).unfollow(follow.id);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not unfollow. Try again.'))),
      );
    }
    ref.invalidate(channelFollowsProvider(channel.id));
  }

  /// A whole section (header, note and a group of rows) for a column of
  /// settings groups.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final follows = ref.watch(channelFollowsProvider(channel.id));
    final list = follows.value ?? const <ChannelFollow>[];
    return Column(
      key: const ValueKey('followed-channels'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('Followed channels')),
        if (list.isNotEmpty) ...[
          SettingsGroup(
            children: [
              for (final follow in list)
                SettingsRow(
                  key: ValueKey('channel-follow-${follow.id}'),
                  icon: Icons.campaign_outlined,
                  tone: SettingsTone.accent,
                  title: '#${follow.sourceChannelName}',
                  subtitle: follow.creatorName == null
                      ? follow.sourceCircleName
                      : tr('{circle} · followed by {name}', {
                          'circle': follow.sourceCircleName,
                          'name': follow.creatorName,
                        }),
                  trailing: WeCordButton(
                    label: tr('Unfollow'),
                    variant: WeCordButtonVariant.secondary,
                    size: WeCordButtonSize.small,
                    onPressed: () => unawaited(_unfollow(context, ref, follow)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            // Loading and failures read like an empty list, so the
            // section keeps its height.
            list.isEmpty
                ? tr(
                    'This channel follows no announcement channels. Follow '
                    'one from its channel header.',
                  )
                : tr('Posts published in these channels appear here.'),
            style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// Lets the current user follow [channel] (an announcement channel) into
/// a channel of one of their circles where they manage webhooks.
Future<void> showFollowChannelSheet(
  BuildContext context, {
  required CircleChannel channel,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Follow #{name}', {'name': channel.name}),
    builder: (context, _) => _FollowChannelSheet(channel: channel),
  );
}

class _FollowChannelSheet extends ConsumerStatefulWidget {
  const _FollowChannelSheet({required this.channel});

  final CircleChannel channel;

  @override
  ConsumerState<_FollowChannelSheet> createState() =>
      _FollowChannelSheetState();
}

class _FollowChannelSheetState extends ConsumerState<_FollowChannelSheet> {
  late Future<List<FollowTarget>> _targets = ref
      .read(announcementRepositoryProvider)
      .listFollowTargets(widget.channel.id);
  String? _busyChannelId;

  Future<void> _follow(FollowTarget target) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busyChannelId = target.channelId);
    try {
      await ref
          .read(announcementRepositoryProvider)
          .follow(
            sourceChannelId: widget.channel.id,
            targetChannelId: target.channelId,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr('#{source} now posts to #{target} in {circle}.', {
              'source': widget.channel.name,
              'target': target.channelName,
              'circle': target.circleName,
            }),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _busyChannelId = null);
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not follow the channel. Try again.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final message = TextStyle(fontSize: 14, color: c.muted, height: 1.4);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              tr(
                'Choose where its published posts should appear. You need '
                'to manage webhooks in that channel.',
              ),
              style: message,
            ),
          ),
          FutureBuilder<List<FollowTarget>>(
            future: _targets,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Could not load your channels.'), style: message),
                      const SizedBox(height: 10),
                      WeCordButton(
                        label: tr('Retry'),
                        variant: WeCordButtonVariant.secondary,
                        onPressed: () => setState(() {
                          _targets = ref
                              .read(announcementRepositoryProvider)
                              .listFollowTargets(widget.channel.id);
                        }),
                      ),
                    ],
                  ),
                );
              }
              final targets = snapshot.data;
              if (targets == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (targets.isEmpty) {
                return CircleCard(
                  color: c.well,
                  child: Text(
                    tr(
                      'None of your circles has a text channel where you '
                      'manage webhooks.',
                    ),
                    style: message,
                  ),
                );
              }
              return SettingsGroup(
                color: c.well,
                children: [
                  for (final target in targets)
                    SettingsRow(
                      key: ValueKey('follow-target-${target.channelId}'),
                      icon: Icons.tag,
                      title: target.channelName,
                      subtitle: target.circleName,
                      showChevron:
                          !target.isFollowing &&
                          _busyChannelId != target.channelId,
                      trailing: target.isFollowing
                          ? Text(
                              tr('Following'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.muted,
                              ),
                            )
                          : _busyChannelId == target.channelId
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: target.isFollowing || _busyChannelId != null
                          ? null
                          : () => unawaited(_follow(target)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Above a message copied from a followed announcement channel: who wrote
/// the original and where, linking back to it.
class CrosspostOrigin extends StatelessWidget {
  const CrosspostOrigin({
    required this.crosspost,
    required this.foregroundColor,
    super.key,
  });

  final MessageCrosspost crosspost;
  final Color foregroundColor;

  void _open(BuildContext context) {
    GoRouter.maybeOf(context)?.push(
      Uri(
        path: '${CircleRoutes.path}/${crosspost.sourceCircleId}',
        queryParameters: crosspost.sourceConversationId.isEmpty
            ? null
            : {'c': crosspost.sourceConversationId},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = foregroundColor.withValues(alpha: 0.75);
    return WeCordPressable(
      key: ValueKey('crosspost-origin-${crosspost.sourceMessageId}'),
      onPressed: () => _open(context),
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xs),
      ),
      builder: (context, states) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 14, color: muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                tr('{author} · from #{channel} · {circle}', {
                  'author': crosspost.authorName,
                  'channel': crosspost.channelName,
                  'circle': crosspost.circleName,
                }),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: muted,
                  fontWeight: FontWeight.w600,
                  decoration: states.contains(WidgetState.hovered)
                      ? TextDecoration.underline
                      : null,
                  decorationColor: muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Below a published announcement.
class PublishedMarker extends StatelessWidget {
  const PublishedMarker({required this.foregroundColor, super.key});

  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final muted = foregroundColor.withValues(alpha: 0.75);
    return Padding(
      key: const ValueKey('message-published'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined, size: 12, color: muted),
          const SizedBox(width: 4),
          Text(
            tr('Published'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}
