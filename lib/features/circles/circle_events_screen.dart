import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/circles/calendar_file_download.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_event_editor_sheet.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/circle_role.dart';

/// Which events of a circle to list.
typedef CircleEventsQuery = ({String circleId, bool includePast});

/// Whether event lists reload by themselves when an event starts or ends.
/// Widget tests turn it off, so no timer outlives them.
final circleEventsFollowClockProvider = Provider<bool>((ref) => true);

/// A circle's events by start time. Reloads with the circle (whose
/// realtime channel covers events and interest) and whenever an event
/// starts or ends, so live and upcoming states follow the clock.
final circleEventsProvider = FutureProvider.autoDispose
    .family<List<CircleEvent>, CircleEventsQuery>((ref, query) async {
      ref.listen(circleDetailProvider(query.circleId), (previous, next) {
        if (previous != null && previous.hasValue && next is AsyncData) {
          ref.invalidateSelf();
        }
      });
      final events = await ref
          .watch(circlesRepositoryProvider)
          .listEvents(circleId: query.circleId, includePast: query.includePast);
      final now = DateTime.now();
      DateTime? nextChange;
      for (final event in events) {
        if (event.isCancelled) {
          continue;
        }
        for (final time in [event.startsAt, event.effectiveEndsAt]) {
          if (time.isAfter(now) &&
              (nextChange == null || time.isBefore(nextChange))) {
            nextChange = time;
          }
        }
      }
      if (nextChange != null && ref.watch(circleEventsFollowClockProvider)) {
        final delay = nextChange.difference(now) + const Duration(seconds: 1);
        if (delay < const Duration(days: 1)) {
          final timer = Timer(delay, ref.invalidateSelf);
          ref.onDispose(timer.cancel);
        }
      }
      return events;
    });

/// Reloads every event list and the reminders after the current user
/// changed an event or their interest.
void refreshCircleEvents(WidgetRef ref) {
  ref.invalidate(circleEventsProvider);
  try {
    unawaited(
      ref
          .read(notificationCoordinatorProvider)
          .refreshEventReminders()
          .catchError((Object _) {}),
    );
  } catch (_) {
    // Reminders refresh on their own later.
  }
}

/// The circle's events, soonest first: upcoming and live ones, and on
/// request past and cancelled ones. Members who manage events create them
/// here.
class CircleEventsScreen extends ConsumerStatefulWidget {
  const CircleEventsScreen({
    required this.circleId,
    this.initialEventId,
    super.key,
  });

  static String pathFor(String circleId, {String? eventId}) {
    final path = '/circles/$circleId/events';
    return eventId == null ? path : '$path?event=$eventId';
  }

  final String circleId;

  /// An event to open once the list has loaded (from a reminder).
  final String? initialEventId;

  @override
  ConsumerState<CircleEventsScreen> createState() => _CircleEventsScreenState();
}

class _CircleEventsScreenState extends ConsumerState<CircleEventsScreen> {
  var _includePast = false;
  var _openedInitialEvent = false;
  final _busyEventIds = <String>{};

  CircleEventsQuery get _query =>
      (circleId: widget.circleId, includePast: _includePast);

  Future<void> _create(CircleDetail detail) async {
    final event = await showCircleEventEditor(context, detail: detail);
    if (event != null && mounted) {
      refreshCircleEvents(ref);
    }
  }

  Future<void> _toggleInterest(CircleEvent event) async {
    if (_busyEventIds.contains(event.id)) {
      return;
    }
    setState(() => _busyEventIds.add(event.id));
    await toggleCircleEventInterest(context, ref, event);
    if (mounted) {
      setState(() => _busyEventIds.remove(event.id));
    }
  }

  void _open(CircleEvent event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CircleEventDetailScreen(
          circleId: widget.circleId,
          initialEvent: event,
        ),
      ),
    );
  }

  void _openInitialEvent(List<CircleEvent> events) {
    final eventId = widget.initialEventId;
    if (_openedInitialEvent || eventId == null) {
      return;
    }
    _openedInitialEvent = true;
    final event = events.where((event) => event.id == eventId).firstOrNull;
    if (event != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _open(event);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(circleDetailProvider(widget.circleId)).valueOrNull;
    final events = ref.watch(circleEventsProvider(_query));
    final canCreate =
        detail != null && detail.can(CirclePermission.manageEvents);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Events')),
        actions: [
          if (canCreate)
            IconButton(
              key: const ValueKey('circle-events-create'),
              tooltip: tr('Create event'),
              onPressed: () => _create(detail),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Could not load events.')),
              TextButton(
                onPressed: () => ref.invalidate(circleEventsProvider(_query)),
                child: Text(tr('Retry')),
              ),
            ],
          ),
        ),
        data: (events) {
          _openInitialEvent(events);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(circleEventsProvider(_query).future),
            child: ListView(
              key: const ValueKey('circle-events-list'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (events.isEmpty)
                  _EmptyEvents(
                    includePast: _includePast,
                    onCreate: canCreate ? () => _create(detail) : null,
                  ),
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CircleEventCard(
                      event: event,
                      busy: _busyEventIds.contains(event.id),
                      onTap: () => _open(event),
                      onToggleInterest: () => _toggleInterest(event),
                    ),
                  ),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('circle-events-show-past'),
                    onPressed: () =>
                        setState(() => _includePast = !_includePast),
                    icon: Icon(
                      _includePast ? Icons.visibility_off : Icons.history,
                    ),
                    label: Text(
                      _includePast
                          ? tr('Hide past and cancelled events')
                          : tr('Show past and cancelled events'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({required this.includePast, this.onCreate});

  final bool includePast;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.event_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            includePast ? tr('No events yet') : tr('No upcoming events'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            onCreate == null
                ? tr('Events scheduled in this circle show up here.')
                : tr('Schedule a meetup, a voice hangout or a game night.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (onCreate != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(tr('Create event')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Toggles the current user's interest in [event], refreshing the lists
/// and reminders, or says it failed.
Future<void> toggleCircleEventInterest(
  BuildContext context,
  WidgetRef ref,
  CircleEvent event,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(circlesRepositoryProvider).toggleEventInterest(event.id);
    refreshCircleEvents(ref);
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not update your interest.'))),
    );
  }
}

/// An event in the list: when, what, where, who is interested, and the
/// Interested toggle.
class CircleEventCard extends StatelessWidget {
  const CircleEventCard({
    required this.event,
    required this.onTap,
    required this.onToggleInterest,
    this.busy = false,
    this.now,
    super.key,
  });

  final CircleEvent event;
  final VoidCallback onTap;
  final VoidCallback onToggleInterest;
  final bool busy;

  /// The current time, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = this.now ?? DateTime.now();
    final status = event.statusAt(now);
    final creator = event.creator;
    final interested = switch (event.interestedCount) {
      0 => tr('No one interested yet'),
      final count => tr('{count} interested', {'count': count}),
    };

    return Material(
      key: ValueKey('circle-event-${event.id}'),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: status == CircleEventStatus.ongoing
              ? colorScheme.primary
              : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (circleEventStatusBadge(context, status) case final badge?)
                    badge,
                  Text(
                    formatCircleEventTime(context, event, now: now),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: status == CircleEventStatus.ongoing
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: event.isCancelled
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              CircleEventLocationChip(event: event),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        interested,
                        if (creator != null)
                          tr('by {name}', {'name': creator.name}),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleEventJoinVoiceButton(event: event, now: now),
                  CircleEventInterestButton(
                    key: ValueKey('circle-event-interest-${event.id}'),
                    event: event,
                    busy: busy,
                    now: now,
                    onPressed: onToggleInterest,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Join" for a voice event that is on now: connects to its voice channel
/// and opens it. Nothing for other events.
class CircleEventJoinVoiceButton extends ConsumerWidget {
  const CircleEventJoinVoiceButton({required this.event, this.now, super.key});

  final CircleEvent event;

  /// The current time, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelId = event.channelId;
    if (event.locationType != CircleEventLocationType.voice ||
        channelId == null ||
        event.statusAt(now ?? DateTime.now()) != CircleEventStatus.ongoing) {
      return const SizedBox.shrink();
    }
    final detail = ref.watch(circleDetailProvider(event.circleId)).valueOrNull;
    CircleChannel? channel;
    for (final candidate in detail?.channels ?? const <CircleChannel>[]) {
      if (candidate.id == channelId && candidate.isVoice) {
        channel = candidate;
      }
    }
    if (detail == null || channel == null) {
      return const SizedBox.shrink();
    }
    final voiceChannel = channel;
    final connected = ref.watch(voiceSessionProvider)?.channelId == channelId;
    final canConnect = detail.canInChannel(
      voiceChannel,
      CirclePermission.connectVoice,
    );

    Future<void> join() async {
      if (!connected) {
        final joined = await joinVoiceChannel(
          context,
          ref,
          circleId: event.circleId,
          channelId: voiceChannel.id,
          conversationId: voiceChannel.conversationId,
          channelName: voiceChannel.name,
        );
        if (!joined || !context.mounted) {
          return;
        }
      }
      GoRouter.maybeOf(context)?.push(
        CircleChannelThreadScreen.pathFor(
          event.circleId,
          voiceChannel.conversationId,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilledButton.icon(
        key: ValueKey('circle-event-join-voice-${event.id}'),
        onPressed: connected || canConnect ? join : null,
        icon: const Icon(Icons.volume_up, size: 18),
        label: Text(connected ? tr('Open') : tr('Join')),
      ),
    );
  }
}

/// "Interested", filled while the current user is.
class CircleEventInterestButton extends StatelessWidget {
  const CircleEventInterestButton({
    required this.event,
    required this.onPressed,
    this.busy = false,
    this.now,
    super.key,
  });

  final CircleEvent event;
  final VoidCallback onPressed;
  final bool busy;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final active = event.isActiveAt(now ?? DateTime.now());
    // Interest can always be taken back, but only given while the event is
    // still on.
    final enabled = !busy && (active || event.interestedByMe);
    final icon = Icon(
      event.interestedByMe
          ? Icons.notifications_active
          : Icons.notifications_none,
      size: 18,
    );
    final label = Text(tr('Interested'));
    return event.interestedByMe
        ? FilledButton.tonalIcon(
            onPressed: enabled ? onPressed : null,
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: icon,
            label: label,
          );
  }
}

/// Live now / Cancelled / Ended, or null for scheduled events.
Widget? circleEventStatusBadge(BuildContext context, CircleEventStatus status) {
  final colorScheme = Theme.of(context).colorScheme;
  final (label, background, foreground) = switch (status) {
    CircleEventStatus.ongoing => (
      tr('Live now'),
      colorScheme.primary,
      colorScheme.onPrimary,
    ),
    CircleEventStatus.cancelled => (
      tr('Cancelled'),
      colorScheme.errorContainer,
      colorScheme.onErrorContainer,
    ),
    CircleEventStatus.over => (
      tr('Ended'),
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
    ),
    CircleEventStatus.scheduled => (null, null, null),
  };
  if (label == null) {
    return null;
  }
  return Container(
    key: ValueKey('circle-event-status-${status.name}'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Where the event happens, as a small chip.
class CircleEventLocationChip extends StatelessWidget {
  const CircleEventLocationChip({required this.event, super.key});

  final CircleEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = switch (event.locationType) {
      CircleEventLocationType.voice => Icons.volume_up_outlined,
      CircleEventLocationType.text => Icons.tag,
      CircleEventLocationType.external => Icons.place_outlined,
    };
    final label = switch (event.locationType) {
      CircleEventLocationType.external => event.locationLabel,
      _ => event.channelName ?? tr('Deleted channel'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An event with its description, interested members, Add to calendar and,
/// for its managers, edit and cancel.
class CircleEventDetailScreen extends ConsumerStatefulWidget {
  const CircleEventDetailScreen({
    required this.circleId,
    required this.initialEvent,
    super.key,
  });

  final String circleId;
  final CircleEvent initialEvent;

  @override
  ConsumerState<CircleEventDetailScreen> createState() =>
      _CircleEventDetailScreenState();
}

enum _EventMenuAction { edit, cancel }

class _CircleEventDetailScreenState
    extends ConsumerState<CircleEventDetailScreen> {
  late CircleEvent _event = widget.initialEvent;
  late Future<List<CircleEventPerson>> _interested = _loadInterested();
  var _busy = false;

  Future<List<CircleEventPerson>> _loadInterested() {
    return ref
        .read(circlesRepositoryProvider)
        .listEventInterested(widget.initialEvent.id);
  }

  void _adopt(CircleEvent event) {
    final interestChanged =
        event.interestedCount != _event.interestedCount ||
        event.interestedByMe != _event.interestedByMe;
    _event = event;
    if (interestChanged) {
      _interested = _loadInterested();
    }
  }

  Future<void> _toggleInterest() async {
    setState(() => _busy = true);
    await toggleCircleEventInterest(context, ref, _event);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _onMenu(_EventMenuAction action, CircleDetail? detail) async {
    switch (action) {
      case _EventMenuAction.edit:
        if (detail == null) {
          return;
        }
        final updated = await showCircleEventEditor(
          context,
          detail: detail,
          event: _event,
        );
        if (updated != null && mounted) {
          setState(() => _adopt(updated));
          refreshCircleEvents(ref);
        }
      case _EventMenuAction.cancel:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(tr('Cancel event?')),
            content: Text(
              tr(
                '"{title}" will be marked as cancelled and no one will be '
                'reminded of it.',
                {'title': _event.title},
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(tr('Keep event')),
              ),
              FilledButton(
                key: const ValueKey('circle-event-confirm-cancel'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(tr('Cancel event')),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.maybeOf(context);
        try {
          final cancelled = await ref
              .read(circlesRepositoryProvider)
              .cancelEvent(_event.id);
          if (mounted) {
            setState(() => _adopt(cancelled));
          }
          refreshCircleEvents(ref);
        } catch (_) {
          messenger?.showSnackBar(
            SnackBar(content: Text(tr('Could not cancel the event.'))),
          );
        }
    }
  }

  Future<void> _addToCalendar() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final summary = circleEventSummaryText(
      _event,
      time: formatCircleEventTime(context, _event, relative: false),
    );
    await Clipboard.setData(ClipboardData(text: summary));
    final downloaded = downloadCalendarFile(
      '${_safeFileName(_event.title)}.ics',
      circleEventCalendarFile(_event, now: DateTime.now()),
    );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? tr('Calendar file downloaded and details copied.')
              : tr('Event details copied. Paste them into your calendar.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final detail = ref.watch(circleDetailProvider(widget.circleId)).valueOrNull;
    final latest = ref
        .watch(
          circleEventsProvider((circleId: widget.circleId, includePast: true)),
        )
        .valueOrNull
        ?.where((event) => event.id == _event.id)
        .firstOrNull;
    if (latest != null && !identical(latest, _event)) {
      _adopt(latest);
    }
    final event = _event;
    final now = DateTime.now();
    final status = event.statusAt(now);
    final creator = event.creator;
    final description = event.description;
    final canManage = event.canManage && !event.isCancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Event')),
        actions: [
          if (canManage)
            PopupMenuButton<_EventMenuAction>(
              tooltip: tr('Event options'),
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => _onMenu(action, detail),
              itemBuilder: (context) => [
                if (status != CircleEventStatus.over)
                  PopupMenuItem(
                    value: _EventMenuAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(tr('Edit event')),
                    ),
                  ),
                PopupMenuItem(
                  value: _EventMenuAction.cancel,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_busy_outlined),
                    title: Text(tr('Cancel event')),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        key: const ValueKey('circle-event-detail'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (circleEventStatusBadge(context, status) case final badge?)
            Align(alignment: Alignment.centerLeft, child: badge),
          const SizedBox(height: 8),
          Text(
            event.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: event.isCancelled ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(height: 12),
          _DetailLine(
            icon: Icons.schedule,
            text: formatCircleEventTime(context, event, now: now),
          ),
          _DetailLine(
            icon: switch (event.locationType) {
              CircleEventLocationType.voice => Icons.volume_up_outlined,
              CircleEventLocationType.text => Icons.tag,
              CircleEventLocationType.external => Icons.place_outlined,
            },
            text: _locationText(event),
          ),
          if (creator != null)
            _DetailLine(
              icon: Icons.person_outline,
              text: tr('Created by {name}', {'name': creator.name}),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CircleEventJoinVoiceButton(event: event, now: now),
              CircleEventInterestButton(
                key: const ValueKey('circle-event-detail-interest'),
                event: event,
                busy: _busy,
                now: now,
                onPressed: _toggleInterest,
              ),
              OutlinedButton.icon(
                key: const ValueKey('circle-event-add-to-calendar'),
                onPressed: event.isCancelled ? null : _addToCalendar,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(tr('Add to calendar')),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 20),
            Text(tr('About'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            MessageMarkdownText(
              key: const ValueKey('circle-event-description'),
              body: description,
              color: colorScheme.onSurface,
            ),
          ],
          const SizedBox(height: 20),
          Text(
            tr('Interested · {count}', {'count': event.interestedCount}),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          FutureBuilder<List<CircleEventPerson>>(
            future: _interested,
            builder: (context, snapshot) {
              final people = snapshot.data;
              if (people == null) {
                return snapshot.hasError
                    ? Text(tr('Could not load who is interested.'))
                    : const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
              }
              if (people.isEmpty) {
                return Text(
                  tr('No one yet.'),
                  style: theme.textTheme.bodySmall,
                );
              }
              return Column(
                key: const ValueKey('circle-event-interested-list'),
                children: [
                  for (final person in people)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text(_initial(person.name))),
                      title: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '@${person.profile.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// The sidebar's Events entry: how many events are coming up, and Live now
/// while one is on.
class CircleEventsEntry extends ConsumerWidget {
  const CircleEventsEntry({
    required this.circleId,
    required this.builder,
    super.key,
  });

  final String circleId;

  /// Builds the row from its label and whether an event is live.
  final Widget Function(BuildContext context, String label, bool live) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events =
        ref
            .watch(
              circleEventsProvider((circleId: circleId, includePast: false)),
            )
            .valueOrNull ??
        const <CircleEvent>[];
    final now = DateTime.now();
    final active = events.where((event) => event.isActiveAt(now)).toList();
    final live = active.any(
      (event) => event.statusAt(now) == CircleEventStatus.ongoing,
    );
    final label = active.isEmpty
        ? tr('Events')
        : tr('Events ({count})', {'count': active.length});
    return builder(context, label, live);
  }
}

/// "Today · 5:30 PM – 7:30 PM", "Sat, Oct 18 · 5:30 PM" or, across days,
/// "Sat, Oct 18 · 10:00 PM – Sun, Oct 19 · 2:00 AM", in local time.
/// [relative] names today and tomorrow.
String formatCircleEventTime(
  BuildContext context,
  CircleEvent event, {
  DateTime? now,
  bool relative = true,
}) {
  final localizations = MaterialLocalizations.of(context);
  final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
  final today = (now ?? DateTime.now()).toLocal();

  String day(DateTime time) {
    if (relative) {
      final date = DateUtils.dateOnly(time);
      final difference = date.difference(DateUtils.dateOnly(today)).inDays;
      if (difference == 0) {
        return tr('Today');
      }
      if (difference == 1) {
        return tr('Tomorrow');
      }
    }
    final medium = localizations.formatMediumDate(time);
    return time.year == today.year ? medium : '$medium, ${time.year}';
  }

  String clock(DateTime time) => localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(time),
    alwaysUse24HourFormat: use24Hour,
  );

  final start = event.startsAt.toLocal();
  final end = event.endsAt?.toLocal();
  final startText = '${day(start)} · ${clock(start)}';
  if (end == null) {
    return startText;
  }
  if (DateUtils.isSameDay(start, end)) {
    return '$startText – ${clock(end)}';
  }
  return '$startText – ${day(end)} · ${clock(end)}';
}

/// The event as plain text, for pasting into a calendar or a message.
String circleEventSummaryText(CircleEvent event, {required String time}) {
  final description = event.description;
  return [
    event.title,
    time,
    tr('Where: {location}', {'location': _locationText(event)}),
    if (description != null) ...['', plainTextFromMarkdown(description).trim()],
  ].join('\n');
}

/// The event as an iCalendar (.ics) file.
String circleEventCalendarFile(CircleEvent event, {required DateTime now}) {
  String time(DateTime value) {
    final utc = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}'
        'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  String escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(RegExp(r'\r?\n'), r'\n');

  final description = event.description;
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//WeCord//Circle events//EN',
    'BEGIN:VEVENT',
    'UID:${event.id}@wecord',
    'DTSTAMP:${time(now)}',
    'DTSTART:${time(event.startsAt)}',
    'DTEND:${time(event.effectiveEndsAt)}',
    'SUMMARY:${escape(event.title)}',
    if (description != null)
      'DESCRIPTION:${escape(plainTextFromMarkdown(description).trim())}',
    'LOCATION:${escape(event.locationLabel)}',
    if (event.isCancelled) 'STATUS:CANCELLED',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

String _locationText(CircleEvent event) {
  if (event.locationType != CircleEventLocationType.external &&
      event.channelName == null) {
    return tr('Deleted channel');
  }
  return event.locationLabel;
}

String _safeFileName(String title) {
  final safe = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return safe.isEmpty ? 'event' : safe;
}

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}
