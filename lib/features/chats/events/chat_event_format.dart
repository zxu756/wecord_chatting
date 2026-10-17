import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/shared/calendar/ics.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';

/// "Today", "Tomorrow", a weekday this week, else the date.
String chatEventDayLabel(DateTime time, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final difference = day.difference(today).inDays;
  if (difference == 0) return tr('Today');
  if (difference == 1) return tr('Tomorrow');
  if (difference > 1 && difference < 7) return formatWeekday(time);
  return '${formatWeekday(time, abbreviated: true)}, '
      '${formatDateShort(time, now: now)}';
}

/// "Today · 8:00 PM – 10:00 PM" in the reader's time zone.
String formatChatEventWhen(
  ChatEvent event,
  DateTime now, {
  bool use24Hour = false,
}) {
  final start = event.startsAt.toLocal();
  final end = event.endsAt?.toLocal();
  String clock(DateTime time) => formatClock(time, use24Hour: use24Hour);
  final startText = '${chatEventDayLabel(start, now)} · ${clock(start)}';
  if (end == null) {
    return startText;
  }
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) {
    return '$startText – ${clock(end)}';
  }
  return '$startText – ${chatEventDayLabel(end, now)} · ${clock(end)}';
}

/// "Starts in 2 hours", "Live now", "Ended", "Cancelled".
String chatEventStatusText(ChatEvent event, DateTime now) {
  return switch (event.statusAt(now)) {
    ChatEventStatus.cancelled => tr('Cancelled'),
    ChatEventStatus.over => tr('Ended'),
    ChatEventStatus.live => tr('Live now'),
    ChatEventStatus.upcoming => tr('Starts {when}', {
      'when': relativeTimeText(event.startsAt, now),
    }),
  };
}

/// "5 going · 2 maybe".
String chatEventCountsText(ChatEvent event) {
  final parts = [
    if (event.goingCount > 0) tr('{count} going', {'count': event.goingCount}),
    if (event.maybeCount > 0) tr('{count} maybe', {'count': event.maybeCount}),
  ];
  return parts.isEmpty ? tr('No answers yet') : parts.join(' · ');
}

/// The event as a calendar file (.ics) with its place, link and a reminder.
String chatEventCalendarFile(ChatEvent event, {DateTime? now}) {
  final details = [
    if (event.description != null) event.description!.trim(),
    if (event.linkUrl != null) event.linkUrl!,
  ].join('\n\n');
  return buildIcsCalendar(
    uid: '${event.id}@wecord',
    title: event.title,
    start: event.startsAt,
    end: event.effectiveEndsAt,
    description: details,
    location: event.locationText ?? event.linkUrl,
    url: event.linkUrl,
    cancelled: event.isCancelled,
    remindMinutesBefore: event.reminderLeads.isEmpty
        ? 15
        : event.reminderLeads.reduce((a, b) => a < b ? a : b),
    now: now,
  );
}

/// The host of [url] without www, for a compact link row.
String chatEventLinkLabel(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  if (host.isEmpty) {
    return url;
  }
  final bare = host.startsWith('www.') ? host.substring(4) : host;
  final path = uri!.path == '/' ? '' : uri.path;
  return '$bare$path';
}
