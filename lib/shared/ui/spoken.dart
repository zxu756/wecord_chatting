import 'package:wecord/shared/l10n/l10n.dart';

/// How long ago [time] was, as a screen reader should say it: "Just now",
/// "5 minutes ago", "3 hours ago", "2 days ago", then the date.
String spokenAge(DateTime time, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inMinutes < 1) {
    return tr('Just now');
  }
  if (elapsed.inHours < 1) {
    final minutes = elapsed.inMinutes;
    return minutes == 1
        ? tr('1 minute ago')
        : tr('{count} minutes ago', {'count': minutes});
  }
  if (elapsed.inDays < 1) {
    final hours = elapsed.inHours;
    return hours == 1
        ? tr('1 hour ago')
        : tr('{count} hours ago', {'count': hours});
  }
  if (elapsed.inDays < 30) {
    final days = elapsed.inDays;
    return days == 1
        ? tr('1 day ago')
        : tr('{count} days ago', {'count': days});
  }
  final local = time.toLocal();
  return tr('{year}/{month}/{day}', {
    'year': local.year,
    'month': local.month,
    'day': local.day,
  });
}

/// A clock time as a screen reader says it ("9:20"): the same digits the
/// screen shows, without the colon being read as a ratio.
String spokenClock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
}

/// Joins the non-empty [parts] with commas, for a control's one-line
/// accessible label ("Ada, Online, 3 unread, 5 minutes ago").
String spokenList(Iterable<String?> parts) => [
  for (final part in parts)
    if (part != null && part.trim().isNotEmpty) part.trim(),
].join(', ');
