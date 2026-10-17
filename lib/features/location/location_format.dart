import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "42 min left", "1 h 5 min left", "Less than a minute left".
String timeLeftLabel(Duration left) {
  if (left <= Duration.zero) {
    return tr('Ended');
  }
  if (left < const Duration(minutes: 1)) {
    return tr('Less than a minute left');
  }
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  if (hours == 0) {
    return tr('{minutes} min left', {'minutes': minutes});
  }
  if (minutes == 0) {
    return tr('{hours} h left', {'hours': hours});
  }
  return tr('{hours} h {minutes} min left', {
    'hours': hours,
    'minutes': minutes,
  });
}

/// "Just now", "20 s ago", "3 min ago", "2 h ago".
String agoLabel(Duration age) {
  if (age < const Duration(seconds: 10)) {
    return tr('Just now');
  }
  if (age < const Duration(minutes: 1)) {
    return tr('{seconds} s ago', {'seconds': age.inSeconds});
  }
  if (age < const Duration(hours: 1)) {
    return tr('{minutes}m ago', {'minutes': age.inMinutes});
  }
  return tr('{hours}h ago', {'hours': age.inHours});
}

/// "Until 3:40 PM" in the device's time style.
String untilLabel(BuildContext context, DateTime end) {
  final time = TimeOfDay.fromDateTime(end.toLocal());
  return tr('Until {time}', {
    'time': MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    ),
  });
}
