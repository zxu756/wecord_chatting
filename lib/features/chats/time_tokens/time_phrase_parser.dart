/// Finds dates and times written in everyday English and Chinese ("tomorrow
/// 8pm", "10/20 15:00", "明天晚上8点", "下周三下午3点") so the composer can
/// offer to turn them into time tokens. Everything is read in the writer's
/// own time zone (the [DateTime]s are local); the token then fixes the
/// instant for every reader.
library;

/// A date and time found in a message.
class TimePhrase {
  const TimePhrase({
    required this.start,
    required this.end,
    required this.time,
  });

  /// Offsets of the words in the text, [end] exclusive.
  final int start;
  final int end;

  /// The moment they name, in the local time zone.
  final DateTime time;

  String textIn(String source) => source.substring(start, end);

  @override
  String toString() => 'TimePhrase($start-$end, $time)';
}

/// The date and time phrases in [text], in order, none overlapping. Only
/// moments after [now] are returned. Phrases inside links, `<...>` tokens
/// and code are skipped.
List<TimePhrase> findTimePhrases(String text, {required DateTime now}) {
  if (text.trim().isEmpty) {
    return const [];
  }
  final masked = _mask(text);
  final dates = _dropOverlaps([
    ..._englishDates(masked),
    ..._chineseDates(masked),
  ]);
  final times =
      _dropOverlaps([..._englishTimes(masked), ..._chineseTimes(masked)])
          .where(
            (time) => !dates.any(
              (date) => time.start < date.end && date.start < time.end,
            ),
          )
          .toList();
  final relatives = _dropOverlaps([
    ..._englishRelatives(masked, now),
    ..._chineseRelatives(masked, now),
  ]);

  final used = <_Time>{};
  final phrases = <TimePhrase>[];

  for (final date in dates) {
    final after = times
        .where((time) => !used.contains(time) && time.start >= date.end)
        .firstOrNull;
    final before = times
        .where((time) => !used.contains(time) && time.end <= date.start)
        .lastOrNull;
    _Time? pick;
    if (after != null &&
        _glueAfter.hasMatch(masked.substring(date.end, after.start))) {
      pick = after;
    } else if (before != null &&
        _glueBefore.hasMatch(masked.substring(before.end, date.start))) {
      pick = before;
    }
    if (pick == null) {
      continue;
    }
    // A time spoken for by a date is never offered on its own, even when
    // the date turns out to be impossible or over.
    used.add(pick);
    final period = pick.period ?? date.period;
    final hour = _resolveHour(pick.hour, pick.ampm, period);
    if (hour == null || (hour == 24 && pick.minute != 0)) {
      continue;
    }
    final resolved = date.resolve(now, hour, pick.minute);
    if (resolved == null || !resolved.isAfter(now)) {
      continue;
    }
    phrases.add(
      TimePhrase(
        start: date.start < pick.start ? date.start : pick.start,
        end: date.end > pick.end ? date.end : pick.end,
        time: resolved,
      ),
    );
  }

  for (final time in times) {
    if (used.contains(time) || !time.strong) {
      continue;
    }
    final hour = _resolveHour(time.hour, time.ampm, time.period);
    if (hour == null || (hour == 24 && time.minute != 0)) {
      continue;
    }
    var resolved = DateTime(now.year, now.month, now.day, hour, time.minute);
    if (!resolved.isAfter(now)) {
      resolved = DateTime(now.year, now.month, now.day + 1, hour, time.minute);
    }
    phrases.add(TimePhrase(start: time.start, end: time.end, time: resolved));
  }

  for (final relative in relatives) {
    final resolved = relative.resolve(now, 0, 0);
    if (resolved != null && resolved.isAfter(now)) {
      phrases.add(
        TimePhrase(start: relative.start, end: relative.end, time: resolved),
      );
    }
  }

  phrases.sort((a, b) => a.start.compareTo(b.start));
  final result = <TimePhrase>[];
  for (final phrase in phrases) {
    if (result.isNotEmpty && phrase.start < result.last.end) {
      continue;
    }
    result.add(phrase);
  }
  return result;
}

/// What may sit between a date and a time after it, or a time and a date
/// after it ("tomorrow at 8pm", "8pm on friday").
final _glueAfter = RegExp(r'^[\s,]*(?:(?:at|@|around|by|from)\s*)?$');
final _glueBefore = RegExp(r'^[\s,]*(?:on\s*)?$');

enum _Period { earlyMorning, morning, noon, afternoon, evening, night }

enum _Ampm { am, pm }

class _Date {
  _Date(this.start, this.end, this.resolve, {this.period});

  final int start;
  final int end;
  final _Period? period;

  /// The moment on this date at [hour]:[minute], or null when it makes no
  /// sense (31 February, last week).
  final DateTime? Function(DateTime now, int hour, int minute) resolve;

  _Date extended(int newEnd, _Period newPeriod) =>
      _Date(start, newEnd, resolve, period: newPeriod);
}

class _Time {
  _Time({
    required this.start,
    required this.end,
    required this.hour,
    this.minute = 0,
    this.ampm,
    this.period,
    this.strong = false,
  });

  final int start;
  final int end;
  final int hour;
  final int minute;
  final _Ampm? ampm;
  final _Period? period;

  /// Clear enough to stand without a date ("8pm", "晚上8点").
  final bool strong;
}

List<T> _dropOverlaps<T>(List<T> items) {
  int startOf(T item) => switch (item) {
    _Date() => item.start,
    _Time() => item.start,
    _ => 0,
  };
  int endOf(T item) => switch (item) {
    _Date() => item.end,
    _Time() => item.end,
    _ => 0,
  };
  final sorted = [...items]
    ..sort((a, b) {
      final byStart = startOf(a).compareTo(startOf(b));
      return byStart != 0
          ? byStart
          : (endOf(b) - startOf(b)).compareTo(endOf(a) - startOf(a));
    });
  final kept = <T>[];
  for (final item in sorted) {
    if (kept.isNotEmpty && startOf(item) < endOf(kept.last)) {
      continue;
    }
    kept.add(item);
  }
  return kept;
}

final _skipPattern = RegExp(
  r'https?://[^\s<]+|<[^<>\n]{1,200}>|`[^`\n]*`',
  caseSensitive: false,
);

/// [text] with links, `<...>` tokens and code spans blanked out (same
/// length, so offsets stay valid).
String _mask(String text) {
  return text.replaceAllMapped(
    _skipPattern,
    (match) => ' ' * match.group(0)!.length,
  );
}

// ---------------------------------------------------------------- hours

int? _resolveHour(int raw, _Ampm? ampm, _Period? period) {
  if (raw < 0 || raw > 24) {
    return null;
  }
  if (ampm != null) {
    if (raw < 1 || raw > 12) {
      return null;
    }
    return switch (ampm) {
      _Ampm.am => raw == 12 ? 0 : raw,
      _Ampm.pm => raw == 12 ? 12 : raw + 12,
    };
  }
  switch (period) {
    case null:
      return raw;
    case _Period.earlyMorning:
      return raw == 12 ? 0 : raw;
    case _Period.morning:
      return raw;
    case _Period.noon:
      return raw >= 1 && raw <= 5 ? raw + 12 : raw;
    case _Period.afternoon:
      if (raw >= 1 && raw <= 11) return raw + 12;
      return raw;
    case _Period.evening:
    case _Period.night:
      if (raw >= 1 && raw <= 11) return raw + 12;
      if (raw == 12) return 24;
      return raw;
  }
}

// ------------------------------------------------------------ resolvers

DateTime? _validDate(int year, int month, int day, int hour, int minute) {
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final probe = DateTime(year, month, day);
  if (probe.month != month || probe.day != day) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}

DateTime? Function(DateTime, int, int) _daysFromToday(int days) {
  return (now, hour, minute) =>
      DateTime(now.year, now.month, now.day + days, hour, minute);
}

/// A calendar date; without a year, this year, or next when it has passed.
DateTime? Function(DateTime, int, int) _monthDay(
  int month,
  int day, {
  int? year,
  int monthOffset = 0,
}) {
  return (now, hour, minute) {
    if (year != null) {
      return _validDate(year, month, day, hour, minute);
    }
    if (monthOffset != 0) {
      final target = DateTime(now.year, now.month + monthOffset);
      return _validDate(target.year, target.month, day, hour, minute);
    }
    final thisYear = _validDate(now.year, month, day, hour, minute);
    if (thisYear == null) {
      return _validDate(now.year + 1, month, day, hour, minute);
    }
    if (thisYear.isBefore(now)) {
      return _validDate(now.year + 1, month, day, hour, minute);
    }
    return thisYear;
  };
}

/// [weekday] is 1 (Monday) to 7 (Sunday). [nextWeek] means that day of the
/// calendar week after this one; otherwise the coming one.
DateTime? Function(DateTime, int, int) _weekday(
  int weekday, {
  bool nextWeek = false,
  bool weekAfterNext = false,
}) {
  return (now, hour, minute) {
    if (nextWeek || weekAfterNext) {
      final mondayThisWeek = now.day - (now.weekday - 1);
      final offset = weekAfterNext ? 14 : 7;
      return DateTime(
        now.year,
        now.month,
        mondayThisWeek + offset + weekday - 1,
        hour,
        minute,
      );
    }
    var ahead = (weekday - now.weekday) % 7;
    var candidate = DateTime(
      now.year,
      now.month,
      now.day + ahead,
      hour,
      minute,
    );
    if (!candidate.isAfter(now)) {
      ahead += 7;
      candidate = DateTime(now.year, now.month, now.day + ahead, hour, minute);
    }
    return candidate;
  };
}

// -------------------------------------------------------------- English

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

const _monthPattern =
    r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

const _englishWeekdayNumbers = {
  'mon': 1,
  'tue': 2,
  'wed': 3,
  'thu': 4,
  'fri': 5,
  'sat': 6,
  'sun': 7,
};

final _englishWordDates = RegExp(
  r'(?<![A-Za-z])(?:(?:the\s+)?day\s+after\s+tomorrow|tomorrow|tmrw|tmr|today|tonight|this\s+(?:morning|afternoon|evening))(?![A-Za-z])',
  caseSensitive: false,
);

final _englishWeekdayDates = RegExp(
  r'(?<![A-Za-z])(?:on\s+)?(?:(next|this|coming|upcoming)\s+)?(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sunday)(?![A-Za-z])',
  caseSensitive: false,
);

final _englishMonthDay = RegExp(
  '(?<![A-Za-z0-9])(?:on\\s+)?($_monthPattern)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s+(20\\d{2})\\b)?',
  caseSensitive: false,
);

final _englishDayMonth = RegExp(
  '(?<![A-Za-z0-9])(?:on\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?($_monthPattern)\\b\\.?(?:,?\\s+(20\\d{2})\\b)?',
  caseSensitive: false,
);

final _numericDate = RegExp(
  r'(?<![\d/.\-])(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\d/])',
);

final _isoDate = RegExp(
  r'(?<![\d\-/])(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})(?![\d])',
);

final _trailingPeriod = RegExp(
  r'\s+(?:in\s+the\s+)?(morning|afternoon|evening|night)\b',
  caseSensitive: false,
);

_Period? _englishPeriod(String word) {
  final lower = word.toLowerCase();
  if (lower.endsWith('morning')) return _Period.morning;
  if (lower.endsWith('afternoon')) return _Period.afternoon;
  if (lower.endsWith('evening')) return _Period.evening;
  if (lower.endsWith('night')) return _Period.night;
  return null;
}

List<_Date> _englishDates(String text) {
  final dates = <_Date>[];

  void add(_Date date) {
    // "tomorrow morning at 9": the word after the date sets the period.
    final trailing = _trailingPeriod.matchAsPrefix(text, date.end);
    if (trailing != null && date.period == null) {
      dates.add(
        date.extended(trailing.end, _englishPeriod(trailing.group(1)!)!),
      );
    } else {
      dates.add(date);
    }
  }

  for (final match in _englishWordDates.allMatches(text)) {
    final word = match.group(0)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (word.contains('after tomorrow')) {
      add(_Date(match.start, match.end, _daysFromToday(2)));
    } else if (word == 'tomorrow' || word == 'tmrw' || word == 'tmr') {
      add(_Date(match.start, match.end, _daysFromToday(1)));
    } else if (word == 'tonight') {
      add(
        _Date(match.start, match.end, _daysFromToday(0), period: _Period.night),
      );
    } else if (word == 'today') {
      add(_Date(match.start, match.end, _daysFromToday(0)));
    } else {
      add(
        _Date(
          match.start,
          match.end,
          _daysFromToday(0),
          period: _englishPeriod(word),
        ),
      );
    }
  }

  for (final match in _englishWeekdayDates.allMatches(text)) {
    final modifier = match.group(1)?.toLowerCase();
    final weekday =
        _englishWeekdayNumbers[match.group(2)!.toLowerCase().substring(0, 3)]!;
    add(
      _Date(
        match.start,
        match.end,
        _weekday(weekday, nextWeek: modifier == 'next'),
      ),
    );
  }

  for (final match in _englishMonthDay.allMatches(text)) {
    final month = _months[match.group(1)!.toLowerCase().substring(0, 3)]!;
    final day = int.parse(match.group(2)!);
    final year = int.tryParse(match.group(3) ?? '');
    add(_Date(match.start, match.end, _monthDay(month, day, year: year)));
  }

  for (final match in _englishDayMonth.allMatches(text)) {
    final day = int.parse(match.group(1)!);
    final month = _months[match.group(2)!.toLowerCase().substring(0, 3)]!;
    final year = int.tryParse(match.group(3) ?? '');
    add(_Date(match.start, match.end, _monthDay(month, day, year: year)));
  }

  for (final match in _isoDate.allMatches(text)) {
    add(
      _Date(
        match.start,
        match.end,
        _monthDay(
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          year: int.parse(match.group(1)!),
        ),
      ),
    );
  }

  for (final match in _numericDate.allMatches(text)) {
    var first = int.parse(match.group(1)!);
    var second = int.parse(match.group(2)!);
    // 20/10 can only be day/month; otherwise month/day.
    if (first > 12 && second <= 12) {
      (first, second) = (second, first);
    }
    var year = int.tryParse(match.group(3) ?? '');
    if (year != null && year < 100) {
      year += 2000;
    }
    add(_Date(match.start, match.end, _monthDay(first, second, year: year)));
  }

  return dates;
}

final _englishClock = RegExp(
  r'(?<![\d:./\-$#])(?:'
  r'(?<h>1[0-2]|0?[1-9])(?::(?<m>[0-5]\d))?\s*(?<ap>[ap])\.?m(?![A-Za-z])\.?'
  r'|(?<h24>[01]?\d|2[0-3]):(?<m24>[0-5]\d)(?![\d:])'
  r'|(?<word>noon|midnight)(?![A-Za-z])'
  r'|(?:at|@)\s*(?<hat>[01]?\d|2[0-3])(?::(?<mat>[0-5]\d))?(?![\d:%/.]|\s*(?:am|pm|a\.m|p\.m)(?![A-Za-z]))'
  r')',
  caseSensitive: false,
);

List<_Time> _englishTimes(String text) {
  final times = <_Time>[];
  for (final match in _englishClock.allMatches(text)) {
    if (match.namedGroup('h') != null) {
      times.add(
        _Time(
          start: match.start,
          end: match.end,
          hour: int.parse(match.namedGroup('h')!),
          minute: int.tryParse(match.namedGroup('m') ?? '') ?? 0,
          ampm: match.namedGroup('ap')!.toLowerCase() == 'a'
              ? _Ampm.am
              : _Ampm.pm,
          strong: true,
        ),
      );
    } else if (match.namedGroup('h24') != null) {
      times.add(
        _Time(
          start: match.start,
          end: match.end,
          hour: int.parse(match.namedGroup('h24')!),
          minute: int.parse(match.namedGroup('m24')!),
        ),
      );
    } else if (match.namedGroup('word') != null) {
      final noon = match.namedGroup('word')!.toLowerCase() == 'noon';
      times.add(
        _Time(
          start: match.start,
          end: match.end,
          hour: noon ? 12 : 24,
          strong: true,
        ),
      );
    } else {
      times.add(
        _Time(
          start: match.start,
          end: match.end,
          hour: int.parse(match.namedGroup('hat')!),
          minute: int.tryParse(match.namedGroup('mat') ?? '') ?? 0,
          strong: match.namedGroup('mat') != null,
        ),
      );
    }
  }
  return times;
}

const _unitMinutes = {
  'minute': 1,
  'min': 1,
  'hour': 60,
  'hr': 60,
  'day': 1440,
  'week': 10080,
};

const _numberWords = {
  'a': 1,
  'an': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'fifteen': 15,
  'twenty': 20,
  'thirty': 30,
};

final _englishRelative = RegExp(
  r'(?<![A-Za-z])in\s+(?:(?<half>half\s+an?\s+hour)|(?<n>\d{1,3}|an?|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty)\s*(?<u>minutes?|mins?|hours?|hrs?|days?|weeks?))(?![A-Za-z])',
  caseSensitive: false,
);

List<_Date> _englishRelatives(String text, DateTime now) {
  final result = <_Date>[];
  for (final match in _englishRelative.allMatches(text)) {
    int minutes;
    if (match.namedGroup('half') != null) {
      minutes = 30;
    } else {
      final raw = match.namedGroup('n')!.toLowerCase();
      final count = int.tryParse(raw) ?? _numberWords[raw]!;
      var unit = match.namedGroup('u')!.toLowerCase();
      if (unit.endsWith('s')) {
        unit = unit.substring(0, unit.length - 1);
      }
      minutes = count * _unitMinutes[unit]!;
    }
    result.add(
      _Date(match.start, match.end, (now, _, _) => _addMinutes(now, minutes)),
    );
  }
  return result;
}

/// Whole days keep the clock time across daylight saving changes.
DateTime _addMinutes(DateTime now, int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) {
    return DateTime(
      now.year,
      now.month,
      now.day + minutes ~/ 1440,
      now.hour,
      now.minute,
    );
  }
  return now.add(Duration(minutes: minutes));
}

// -------------------------------------------------------------- Chinese

const _chineseDigits = {
  '零': 0,
  '〇': 0,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

/// 8, 十, 十二, 二十三, 两 as numbers; null when it is not one.
int? _chineseNumber(String text) {
  final plain = int.tryParse(text);
  if (plain != null) {
    return plain;
  }
  if (text.isEmpty) {
    return null;
  }
  final ten = text.indexOf('十');
  if (ten != -1) {
    final tens = ten == 0 ? 1 : _chineseDigits[text.substring(0, ten)];
    final rest = text.substring(ten + 1);
    final ones = rest.isEmpty ? 0 : _chineseDigits[rest];
    if (tens == null || ones == null) {
      return null;
    }
    return tens * 10 + ones;
  }
  var value = 0;
  for (final rune in text.runes) {
    final digit = _chineseDigits[String.fromCharCode(rune)];
    if (digit == null) {
      return null;
    }
    value = value * 10 + digit;
  }
  return value;
}

const _cnNumber = r'(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3})';

final _chineseWordDates = RegExp('(今天|今日|今晚|今夜|今早|今晨|明天|明日|明晚|明早|明晨|大后天|后天)');

final _chineseWeekdayDates = RegExp(
  r'(下下|下|这|本|上)?(?:个)?(?:周|星期|礼拜)([一二三四五六日天1-7])',
);

final _chineseCalendarDate = RegExp(
  '(?:(\\d{4})\\s*年\\s*)?($_cnNumber)\\s*月\\s*($_cnNumber)\\s*[日号號]',
);

final _chineseNextMonthDate = RegExp('(下个?月|本月|这个月)\\s*($_cnNumber)\\s*[日号號]');

List<_Date> _chineseDates(String text) {
  final dates = <_Date>[];

  for (final match in _chineseWordDates.allMatches(text)) {
    final word = match.group(1)!;
    final days = switch (word) {
      '今天' || '今日' || '今晚' || '今夜' || '今早' || '今晨' => 0,
      '明天' || '明日' || '明晚' || '明早' || '明晨' => 1,
      '后天' => 2,
      _ => 3,
    };
    final period = switch (word) {
      '今晚' || '今夜' || '明晚' => _Period.night,
      '今早' || '今晨' || '明早' || '明晨' => _Period.morning,
      _ => null,
    };
    dates.add(
      _Date(match.start, match.end, _daysFromToday(days), period: period),
    );
  }

  for (final match in _chineseWeekdayDates.allMatches(text)) {
    final modifier = match.group(1);
    // "每周三" repeats and "上周三" is over.
    if (modifier == '上' || (match.start > 0 && text[match.start - 1] == '每')) {
      dates.add(_Date(match.start, match.end, (_, _, _) => null));
      continue;
    }
    final raw = match.group(2)!;
    final weekday = switch (raw) {
      '日' || '天' || '7' => 7,
      _ => _chineseNumber(raw)!,
    };
    dates.add(
      _Date(
        match.start,
        match.end,
        _weekday(
          weekday,
          nextWeek: modifier == '下',
          weekAfterNext: modifier == '下下',
        ),
      ),
    );
  }

  for (final match in _chineseCalendarDate.allMatches(text)) {
    final month = _chineseNumber(match.group(2)!);
    final day = _chineseNumber(match.group(3)!);
    if (month == null || day == null) {
      continue;
    }
    final year = int.tryParse(match.group(1) ?? '');
    dates.add(_Date(match.start, match.end, _monthDay(month, day, year: year)));
  }

  for (final match in _chineseNextMonthDate.allMatches(text)) {
    final day = _chineseNumber(match.group(2)!);
    if (day == null) {
      continue;
    }
    final next = match.group(1)!.startsWith('下');
    dates.add(
      _Date(
        match.start,
        match.end,
        next
            ? _monthDay(0, day, monthOffset: 1)
            : (current, hour, minute) =>
                  _validDate(current.year, current.month, day, hour, minute),
      ),
    );
  }

  return dates;
}

final _chineseClock = RegExp(
  '(?<![\\d:：])(?:(?<![今明])(?<period>凌晨|清晨|早上|早晨|早|上午|中午|午后|下午|傍晚|晚上|晚|夜里|夜间|半夜))?\\s*'
  '(?<h>\\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\\s*'
  '(?:(?:点钟|点|时)\\s*(?:(?<m>[0-5]?\\d|[零〇一二三四五六七八九十]{1,3})\\s*分?|(?<half>半)|(?<whole>整))?'
  '|[:：](?<m2>[0-5]\\d)(?![\\d:：]))',
);

_Period? _chinesePeriod(String? word) {
  return switch (word) {
    null => null,
    '凌晨' => _Period.earlyMorning,
    '清晨' || '早上' || '早晨' || '早' || '上午' => _Period.morning,
    '中午' || '午后' => _Period.noon,
    '下午' => _Period.afternoon,
    '傍晚' || '晚上' || '晚' => _Period.evening,
    _ => _Period.night,
  };
}

List<_Time> _chineseTimes(String text) {
  final times = <_Time>[];
  for (final match in _chineseClock.allMatches(text)) {
    final hour = _chineseNumber(match.namedGroup('h')!);
    if (hour == null) {
      continue;
    }
    var minute = 0;
    if (match.namedGroup('half') != null) {
      minute = 30;
    } else if (match.namedGroup('m') != null) {
      final parsed = _chineseNumber(match.namedGroup('m')!);
      if (parsed == null || parsed > 59) {
        continue;
      }
      minute = parsed;
    } else if (match.namedGroup('m2') != null) {
      minute = int.parse(match.namedGroup('m2')!);
    }
    final period = _chinesePeriod(match.namedGroup('period'));
    final arabic = int.tryParse(match.namedGroup('h')!) != null;
    // "吃一点东西" is not one o'clock: a spelled-out hour needs a period.
    final strong = period != null || arabic;
    var start = match.start;
    // The period word can be separated by spaces; keep it in the span.
    while (start < match.end && text[start] == ' ') {
      start++;
    }
    times.add(
      _Time(
        start: start,
        end: match.end,
        hour: hour,
        minute: minute,
        period: period,
        strong: strong,
      ),
    );
  }
  return times;
}

final _chineseRelative = RegExp(
  '(?<n>\\d{1,3}|[一二两三四五六七八九十]{1,3}|半)\\s*(?:(?<gb>个半)|个)?\\s*(?<u>小时|钟头|分钟|天|周|星期)(?<half>半)?\\s*(?:以后|之后|后)',
);

List<_Date> _chineseRelatives(String text, DateTime now) {
  final result = <_Date>[];
  for (final match in _chineseRelative.allMatches(text)) {
    final raw = match.namedGroup('n')!;
    final unit = match.namedGroup('u')!;
    final perUnit = switch (unit) {
      '小时' || '钟头' => 60,
      '分钟' => 1,
      '天' => 1440,
      _ => 10080,
    };
    var minutes = raw == '半'
        ? perUnit ~/ 2
        : (_chineseNumber(raw) ?? 0) * perUnit;
    if (match.namedGroup('half') != null || match.namedGroup('gb') != null) {
      minutes += perUnit ~/ 2;
    }
    if (minutes <= 0) {
      continue;
    }
    result.add(
      _Date(
        match.start,
        match.end,
        (current, _, _) => _addMinutes(current, minutes),
      ),
    );
  }
  return result;
}
