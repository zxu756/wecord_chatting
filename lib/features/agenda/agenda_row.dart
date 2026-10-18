import 'package:flutter/material.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/later/later_cards.dart' show laterPreview;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Event", "Task", "Reminder" or "Scheduled message".
String agendaKindLabel(AgendaKind kind) => switch (kind) {
  AgendaKind.chatEvent || AgendaKind.circleEvent => tr('Event'),
  AgendaKind.task => tr('Task'),
  AgendaKind.reminder => tr('Reminder'),
  AgendaKind.scheduledMessage => tr('Scheduled message'),
};

IconData agendaKindIcon(AgendaKind kind) => switch (kind) {
  AgendaKind.chatEvent || AgendaKind.circleEvent => Icons.event_outlined,
  AgendaKind.task => Icons.check_circle_outline_rounded,
  AgendaKind.reminder => Icons.notifications_none_rounded,
  AgendaKind.scheduledMessage => Icons.schedule_send_outlined,
};

/// What to call [item]: its title, the preview of its message, or a plain
/// word when the message is gone.
String agendaTitle(AgendaItem item) {
  final title = item.title;
  if (title != null) {
    return title;
  }
  if (item.kind == AgendaKind.reminder) {
    final type = item.messageType;
    if (type == null) {
      return tr('Message unavailable');
    }
    return laterPreview(
      conversationId: item.conversationId ?? '',
      body: '',
      type: MessageType.fromJson(type),
    );
  }
  return agendaKindLabel(item.kind);
}

/// My answer to an event as a word, or null.
String? agendaRsvpLabel(AgendaItem item) => switch (item.rsvp) {
  'going' => tr('Going'),
  'maybe' => tr('Maybe'),
  'interested' => tr('Interested'),
  _ => null,
};

String _time(BuildContext context, DateTime local) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// "All day", "6:00 PM" or "6:00 PM – 8:00 PM"; with [withDate] after the
/// day ("Oct 21 · 6:00 PM").
String agendaTimeLabel(
  BuildContext context,
  AgendaItem item, {
  bool withDate = false,
}) {
  final local = item.localStart;
  var time = item.allDay ? tr('All day') : _time(context, local);
  final end = item.endsAt?.toLocal();
  if (!item.allDay &&
      end != null &&
      end.isAfter(local) &&
      dateOnly(end) == dateOnly(local)) {
    time = '$time – ${_time(context, end)}';
  }
  if (!withDate) {
    return time;
  }
  final date = MaterialLocalizations.of(context).formatShortMonthDay(local);
  return '$date · $time';
}

/// One entry of the agenda: a kind icon, the title, where it lives and when.
/// Overdue entries are red ("needs you").
class AgendaRow extends StatelessWidget {
  const AgendaRow({
    required this.item,
    required this.now,
    required this.onPressed,
    this.withDate = false,
    super.key,
  });

  final AgendaItem item;
  final DateTime now;
  final VoidCallback onPressed;

  /// Names the day in the time line (lists that span several days).
  final bool withDate;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final overdue = item.isOverdue(now);
    final title = agendaTitle(item);
    final kind = agendaKindLabel(item.kind);
    final time = agendaTimeLabel(context, item, withDate: withDate);
    final place = [
      if (item.placeName != null) item.placeName!,
      if (item.subtitle != null) item.subtitle!,
    ].join(' · ');
    final rsvp = agendaRsvpLabel(item);
    final status = overdue ? tr('Overdue') : rsvp;
    final accent = overdue ? c.dangerText : c.muted;
    final semantics = [
      kind,
      title,
      if (overdue) tr('Overdue'),
      time,
      if (place.isNotEmpty) place,
      if (!overdue && rsvp != null) rsvp,
    ].join(', ');
    return WeCordPressable(
      key: ValueKey('agenda-${item.key}'),
      onPressed: onPressed,
      semanticLabel: semantics,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      pressedScale: 0.99,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: hovered ? c.well : Colors.transparent,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThingAvatar(
                size: 40,
                icon: agendaKindIcon(item.kind),
                color: overdue ? c.dangerSoft : c.raised,
                foregroundColor: overdue ? c.dangerText : c.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$kind · $time',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                        color: accent,
                      ),
                    ),
                    if (place.isNotEmpty)
                      Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                  ],
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 8),
                _StatusPill(label: status, overdue: overdue),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.overdue});

  final String label;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: ShapeDecoration(
        color: overdue ? c.dangerSoft : c.raised,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: overdue ? c.dangerText : c.muted,
        ),
      ),
    );
  }
}
