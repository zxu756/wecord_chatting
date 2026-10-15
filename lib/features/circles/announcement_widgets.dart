import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/announcement_repository.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message_origin.dart';

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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(tr('Turn off announcements?')),
          content: Text(
            tr(
              'Channels that follow #{name} stop receiving its posts, and '
              'their follows are removed.',
              {'name': widget.channel.name},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              key: const ValueKey('announcement-off-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Turn off')),
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

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const ValueKey('announcement-channel-switch'),
      secondary: const Icon(Icons.campaign_outlined),
      title: Text(tr('Announcement channel')),
      subtitle: Text(
        tr('Posts here can be published to channels that follow it.'),
      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Unfollow channel')),
        content: Text(
          tr('Stop receiving posts from #{channel} in {circle}?', {
            'channel': follow.sourceChannelName,
            'circle': follow.sourceCircleName,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('unfollow-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Unfollow')),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final follows = ref.watch(channelFollowsProvider(channel.id));
    final list = follows.valueOrNull ?? const <ChannelFollow>[];
    return Column(
      key: const ValueKey('followed-channels'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            tr('Followed channels'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            // Loading and failures read like an empty list, so the
            // section keeps its height.
            list.isEmpty
                ? tr(
                    'This channel follows no announcement channels. Follow '
                    'one from its channel header.',
                  )
                : tr('Posts published in these channels appear here.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final follow in list)
          ListTile(
            key: ValueKey('channel-follow-${follow.id}'),
            leading: const Icon(Icons.campaign_outlined),
            title: Text(
              '#${follow.sourceChannelName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              follow.creatorName == null
                  ? follow.sourceCircleName
                  : tr('{circle} · followed by {name}', {
                      'circle': follow.sourceCircleName,
                      'name': follow.creatorName,
                    }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: () => unawaited(_unfollow(context, ref, follow)),
              child: Text(tr('Unfollow')),
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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _FollowChannelSheet(channel: channel),
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
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(
              tr('Follow #{name}', {'name': widget.channel.name}),
              style: theme.textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              tr(
                'Choose where its published posts should appear. You need '
                'to manage webhooks in that channel.',
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Flexible(
            child: FutureBuilder<List<FollowTarget>>(
              future: _targets,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('Could not load your channels.')),
                        TextButton(
                          onPressed: () => setState(() {
                            _targets = ref
                                .read(announcementRepositoryProvider)
                                .listFollowTargets(widget.channel.id);
                          }),
                          child: Text(tr('Retry')),
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
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr(
                        'None of your circles has a text channel where you '
                        'manage webhooks.',
                      ),
                    ),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  children: [
                    for (final target in targets)
                      ListTile(
                        key: ValueKey('follow-target-${target.channelId}'),
                        leading: const Icon(Icons.tag),
                        title: Text(
                          target.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          target.circleName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: target.isFollowing
                            ? Text(
                                tr('Following'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : _busyChannelId == target.channelId
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        enabled: !target.isFollowing && _busyChannelId == null,
                        onTap: () => unawaited(_follow(target)),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
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
    final theme = Theme.of(context);
    final muted = foregroundColor.withValues(alpha: 0.75);
    return InkWell(
      key: ValueKey('crosspost-origin-${crosspost.sourceMessageId}'),
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
