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
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/ui/ui.dart';

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

    return CirclePageScaffold(
      title: tr('Events'),
      subtitle: detail?.circle.name,
      actions: [
        if (canCreate)
          WeCordIconButton(
            key: const ValueKey('circle-events-create'),
            tooltip: tr('Create event'),
            icon: Icons.add_rounded,
            variant: WeCordButtonVariant.accent,
            onPressed: () => _create(detail),
          ),
      ],
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: Icons.event_busy_outlined,
          title: tr('Could not load events.'),
          action: WeCordButton(
            label: tr('Retry'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: () => ref.invalidate(circleEventsProvider(_query)),
          ),
        ),
        data: (events) {
          _openInitialEvent(events);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(circleEventsProvider(_query).future),
            child: ListView(
              key: const ValueKey('circle-events-list'),
              padding: circlePagePadding(context),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (events.isEmpty)
                  _EmptyEvents(
                    includePast: _includePast,
                    onCreate: canCreate ? () => _create(detail) : null,
                  ),
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CircleEventCard(
                      event: event,
                      busy: _busyEventIds.contains(event.id),
                      onTap: () => _open(event),
                      onToggleInterest: () => _toggleInterest(event),
                    ),
                  ),
                const SizedBox(height: 4),
                Center(
                  child: WeCordButton(
                    key: const ValueKey('circle-events-show-past'),
                    variant: WeCordButtonVariant.ghost,
                    onPressed: () =>
                        setState(() => _includePast = !_includePast),
                    icon: _includePast
                        ? Icons.visibility_off_outlined
                        : Icons.history_rounded,
                    label: _includePast
                        ? tr('Hide past and cancelled events')
                        : tr('Show past and cancelled events'),
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
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          ThingAvatar(
            icon: Icons.event_outlined,
            size: 64,
            color: c.warningSoft,
            foregroundColor: c.warningText,
          ),
          const SizedBox(height: 16),
          Text(
            includePast ? tr('No events yet') : tr('No upcoming events'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            onCreate == null
                ? tr('Events scheduled in this circle show up here.')
                : tr('Schedule a meetup, a voice hangout or a game night.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
          ),
          if (onCreate != null) ...[
            const SizedBox(height: 20),
            WeCordButton(
              onPressed: onCreate,
              icon: Icons.add_rounded,
              label: tr('Create event'),
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

/// Buttons inside event cards: finger-sized on touch screens.
WeCordButtonSize _cardButtonSize(BuildContext context) =>
    usesTouchInput(context) ? WeCordButtonSize.medium : WeCordButtonSize.small;

/// The day of an event in a small tinted tile: weekday (or Today) over the
/// day of the month. Live events are red, upcoming ones warm, finished and
/// cancelled ones quiet.
class CircleEventDateTile extends StatelessWidget {
  const CircleEventDateTile({
    required this.event,
    required this.status,
    this.now,
    this.size = 48,
    super.key,
  });

  final CircleEvent event;
  final CircleEventStatus status;
  final DateTime? now;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final start = event.startsAt.toLocal();
    final today = DateUtils.dateOnly((now ?? DateTime.now()).toLocal());
    final days = DateUtils.dateOnly(start).difference(today).inDays;
    final (fill, foreground) = switch (status) {
      CircleEventStatus.ongoing => (c.dangerSoft, c.dangerText),
      CircleEventStatus.scheduled => (c.warningSoft, c.warningText),
      _ => (c.raised, c.muted),
    };
    final top = switch (days) {
      _ when status == CircleEventStatus.ongoing => tr('Now'),
      0 => tr('Today'),
      _ => localizations.narrowWeekdays[start.weekday % 7],
    };
    return Container(
      width: size,
      constraints: BoxConstraints(minHeight: size + 4),
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: fill,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.md),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            top,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: foreground,
              height: 1.1,
            ),
          ),
          Text(
            '${start.day}',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: foreground,
              height: 1.15,
            ),
          ),
        ],
      ),
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
    final tokens = context.tokens;
    final c = tokens.colors;
    final now = this.now ?? DateTime.now();
    final status = event.statusAt(now);
    final live = status == CircleEventStatus.ongoing;
    final creator = event.creator;
    final interested = switch (event.interestedCount) {
      0 => tr('No one interested yet'),
      final count => tr('{count} interested', {'count': count}),
    };
    final radius = BorderRadius.circular(WeCordRadii.xl);

    return WeCordPressable(
      key: ValueKey('circle-event-${event.id}'),
      onPressed: onTap,
      pressedScale: 0.98,
      shape: RoundedRectangleBorder(borderRadius: radius),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: radius,
            border: Border.all(
              color: live ? c.danger.withValues(alpha: 0.5) : c.panel,
              width: 1.5,
            ),
            boxShadow: hovered ? tokens.shadows.hairline : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleEventDateTile(event: event, status: status, now: now),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ?circleEventStatusBadge(context, status),
                            Text(
                              formatCircleEventTime(context, event, now: now),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: live ? c.dangerText : c.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: event.isCancelled ? c.muted : c.ink,
                            decoration: event.isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        CircleEventLocationChip(event: event),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                      style: TextStyle(fontSize: 12.5, color: c.muted),
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
        );
      },
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
      child: WeCordButton(
        key: ValueKey('circle-event-join-voice-${event.id}'),
        variant: WeCordButtonVariant.accent,
        size: _cardButtonSize(context),
        onPressed: connected || canConnect ? join : null,
        icon: Icons.volume_up_rounded,
        label: connected ? tr('Open') : tr('Join'),
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
    return WeCordButton(
      variant: event.interestedByMe
          ? WeCordButtonVariant.primary
          : WeCordButtonVariant.secondary,
      size: _cardButtonSize(context),
      onPressed: enabled ? onPressed : null,
      icon: event.interestedByMe
          ? Icons.notifications_active_rounded
          : Icons.notifications_none_rounded,
      label: tr('Interested'),
    );
  }
}

/// Live now / Cancelled / Ended, or null for scheduled events.
Widget? circleEventStatusBadge(BuildContext context, CircleEventStatus status) {
  final c = context.tokens.colors;
  final (label, background, foreground) = switch (status) {
    CircleEventStatus.ongoing => (tr('Live now'), c.danger, c.onDanger),
    CircleEventStatus.cancelled => (
      tr('Cancelled'),
      c.dangerSoft,
      c.dangerText,
    ),
    CircleEventStatus.over => (tr('Ended'), c.raised, c.muted),
    CircleEventStatus.scheduled => (null, null, null),
  };
  if (label == null) {
    return null;
  }
  return KeyedSubtree(
    key: ValueKey('circle-event-status-${status.name}'),
    child: CircleTag(
      label: label,
      background: background!,
      foreground: foreground!,
    ),
  );
}

/// Where the event happens, as a small chip.
class CircleEventLocationChip extends StatelessWidget {
  const CircleEventLocationChip({required this.event, super.key});

  final CircleEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: c.raised,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
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

  Future<void> _showMenu(
    CircleDetail? detail,
    bool canEdit,
    Offset? position,
  ) async {
    final action = await showCircleActionMenu<_EventMenuAction>(
      context,
      title: _event.title,
      position: position,
      items: [
        if (canEdit)
          CircleMenuItem(
            value: _EventMenuAction.edit,
            icon: Icons.edit_outlined,
            label: tr('Edit event'),
          ),
        CircleMenuItem(
          value: _EventMenuAction.cancel,
          icon: Icons.event_busy_outlined,
          label: tr('Cancel event'),
          destructive: true,
        ),
      ],
    );
    if (action != null && mounted) {
      await _onMenu(action, detail);
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
        final confirmed = await showCircleDialog<bool>(
          context,
          builder: (context) => CircleDialog(
            title: tr('Cancel event?'),
            message: tr(
              '"{title}" will be marked as cancelled and no one will be '
              'reminded of it.',
              {'title': _event.title},
            ),
            actions: [
              CircleDialogAction(
                label: tr('Keep event'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              CircleDialogAction.danger(
                key: const ValueKey('circle-event-confirm-cancel'),
                label: tr('Cancel event'),
                onPressed: () => Navigator.of(context).pop(true),
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
    final c = context.tokens.colors;
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
    final buttonSize = _cardButtonSize(context);

    return CirclePageScaffold(
      title: tr('Event'),
      subtitle: detail?.circle.name,
      actions: [
        if (canManage)
          Builder(
            builder: (buttonContext) => WeCordIconButton(
              tooltip: tr('Event options'),
              icon: Icons.more_horiz_rounded,
              variant: WeCordButtonVariant.onPaper,
              onPressed: () {
                final box = buttonContext.findRenderObject() as RenderBox?;
                _showMenu(
                  detail,
                  status != CircleEventStatus.over,
                  box?.localToGlobal(box.size.bottomRight(Offset.zero)),
                );
              },
            ),
          ),
      ],
      body: ListView(
        key: const ValueKey('circle-event-detail'),
        padding: circlePagePadding(context),
        children: [
          CircleCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleEventDateTile(
                      event: event,
                      status: status,
                      now: now,
                      size: 56,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (circleEventStatusBadge(context, status)
                              case final badge?) ...[
                            badge,
                            const SizedBox(height: 6),
                          ],
                          Text(
                            event.title,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              height: 1.2,
                              color: event.isCancelled ? c.muted : c.ink,
                              decoration: event.isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DetailLine(
                  icon: Icons.schedule_rounded,
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
                    icon: Icons.person_outline_rounded,
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
                    WeCordButton(
                      key: const ValueKey('circle-event-add-to-calendar'),
                      variant: WeCordButtonVariant.secondary,
                      size: buttonSize,
                      onPressed: event.isCancelled ? null : _addToCalendar,
                      icon: Icons.event_available_outlined,
                      label: tr('Add to calendar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (description != null) ...[
            SettingsSectionHeader(tr('About')),
            CircleCard(
              child: MessageMarkdownText(
                key: const ValueKey('circle-event-description'),
                body: description,
                color: c.ink,
              ),
            ),
          ],
          SettingsSectionHeader(
            tr('Interested · {count}', {'count': event.interestedCount}),
          ),
          FutureBuilder<List<CircleEventPerson>>(
            future: _interested,
            builder: (context, snapshot) {
              final people = snapshot.data;
              if (people == null) {
                return snapshot.hasError
                    ? CircleCard(
                        child: Text(
                          tr('Could not load who is interested.'),
                          style: TextStyle(color: c.muted),
                        ),
                      )
                    : const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
              }
              if (people.isEmpty) {
                return CircleCard(
                  child: Text(
                    tr('No one yet.'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                );
              }
              return SettingsGroup(
                key: const ValueKey('circle-event-interested-list'),
                separatorIndent: 66,
                children: [
                  for (final person in people) _InterestedRow(person: person),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InterestedRow extends StatelessWidget {
  const _InterestedRow({required this.person});

  final CircleEventPerson person;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          CircleNetworkAvatar(
            name: person.name,
            url: person.profile.avatarUrl,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                Text(
                  '@${person.profile.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
            ),
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
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14.5, color: c.ink, height: 1.35),
            ),
          ),
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

  /// Builds the entry from its label, whether an event is live, and the
  /// live or next event (null when none is planned).
  final Widget Function(
    BuildContext context,
    String label,
    bool live,
    CircleEvent? next,
  )
  builder;

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
    final upcoming = [...active]
      ..sort((left, right) {
        final leftLive = left.statusAt(now) == CircleEventStatus.ongoing;
        final rightLive = right.statusAt(now) == CircleEventStatus.ongoing;
        if (leftLive != rightLive) {
          return leftLive ? -1 : 1;
        }
        return left.startsAt.compareTo(right.startsAt);
      });
    return builder(
      context,
      label,
      live,
      upcoming.isEmpty ? null : upcoming.first,
    );
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
