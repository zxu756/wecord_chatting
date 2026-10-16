import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/time_tokens/time_phrase_parser.dart';

// Saturday 17 October 2026, 14:00 local time.
final _now = DateTime(2026, 10, 17, 14);

TimePhrase? _only(String text) {
  final found = findTimePhrases(text, now: _now);
  return found.isEmpty ? null : found.single;
}

void _expectTime(String text, DateTime expected, {String? phrase}) {
  final found = findTimePhrases(text, now: _now);
  expect(found, hasLength(1), reason: 'phrases in "$text": $found');
  expect(found.single.time, expected, reason: text);
  if (phrase != null) {
    expect(found.single.textIn(text), phrase, reason: text);
  }
}

void main() {
  group('English', () {
    test('tomorrow with a clock time', () {
      _expectTime(
        'see you tomorrow 8pm ok?',
        DateTime(2026, 10, 18, 20),
        phrase: 'tomorrow 8pm',
      );
      _expectTime('tomorrow at 8:30 PM', DateTime(2026, 10, 18, 20, 30));
      _expectTime('tmrw 9am', DateTime(2026, 10, 18, 9));
      _expectTime('tomorrow at 12am', DateTime(2026, 10, 18));
      _expectTime('tomorrow at 12pm', DateTime(2026, 10, 18, 12));
    });

    test('today, tonight and parts of the day', () {
      _expectTime('today at 5pm', DateTime(2026, 10, 17, 17));
      _expectTime('tonight at 9', DateTime(2026, 10, 17, 21));
      _expectTime('tonight 11:30', DateTime(2026, 10, 17, 23, 30));
      _expectTime(
        'tomorrow morning at 9',
        DateTime(2026, 10, 18, 9),
        phrase: 'tomorrow morning at 9',
      );
      _expectTime('tomorrow evening at 7', DateTime(2026, 10, 18, 19));
      _expectTime('this evening at 8', DateTime(2026, 10, 17, 20));
      _expectTime('the day after tomorrow at 10am', DateTime(2026, 10, 19, 10));
    });

    test('a time that already passed today is not offered', () {
      expect(_only('today at 9am'), isNull);
    });

    test('weekdays', () {
      // _now is a Saturday.
      _expectTime('on friday at 3pm', DateTime(2026, 10, 23, 15));
      _expectTime('Monday 10:30', DateTime(2026, 10, 19, 10, 30));
      _expectTime('next wednesday at 4pm', DateTime(2026, 10, 21, 16));
      _expectTime('next monday 9am', DateTime(2026, 10, 19, 9));
      _expectTime('saturday at 6pm', DateTime(2026, 10, 17, 18));
      // Saturday 2pm has passed, so the next one is meant.
      _expectTime('saturday at 1pm', DateTime(2026, 10, 24, 13));
      _expectTime('3pm on friday', DateTime(2026, 10, 23, 15));
    });

    test('calendar dates', () {
      _expectTime('10/20 15:00', DateTime(2026, 10, 20, 15));
      _expectTime('10/20 at 3pm', DateTime(2026, 10, 20, 15));
      _expectTime('Oct 20 at 3pm', DateTime(2026, 10, 20, 15));
      _expectTime('october 20th 3:30pm', DateTime(2026, 10, 20, 15, 30));
      _expectTime('20 October at 8am', DateTime(2026, 10, 20, 8));
      _expectTime('2026-10-25 18:45', DateTime(2026, 10, 25, 18, 45));
      _expectTime('dec 5, 2026 7pm', DateTime(2026, 12, 5, 19));
      _expectTime('25/10 9am', DateTime(2026, 10, 25, 9));
    });

    test('a date that passed this year means next year', () {
      _expectTime('Jan 5 at 10am', DateTime(2027, 1, 5, 10));
      _expectTime('3/2 8pm', DateTime(2027, 3, 2, 20));
    });

    test('impossible dates are left alone', () {
      expect(_only('feb 30 at 3pm'), isNull);
      expect(_only('13/45 3pm'), isNull);
    });

    test('offsets from now', () {
      _expectTime(
        'back in 2 hours',
        DateTime(2026, 10, 17, 16),
        phrase: 'in 2 hours',
      );
      _expectTime('in 30 minutes', DateTime(2026, 10, 17, 14, 30));
      _expectTime('in half an hour', DateTime(2026, 10, 17, 14, 30));
      _expectTime('in an hour', DateTime(2026, 10, 17, 15));
      _expectTime('in three days', DateTime(2026, 10, 20, 14));
      _expectTime('in 1 week', DateTime(2026, 10, 24, 14));
    });

    test('a time alone is today, or tomorrow once it has passed', () {
      _expectTime('dinner at 8pm', DateTime(2026, 10, 17, 20));
      _expectTime('call at 9am', DateTime(2026, 10, 18, 9));
      _expectTime('noon', DateTime(2026, 10, 18, 12));
      _expectTime('the party starts at 21:30', DateTime(2026, 10, 17, 21, 30));
    });

    test('ordinary text is not a time', () {
      for (final text in [
        'hello there',
        'I have 3 apples',
        'tomorrow',
        'friday',
        'see you at the gym',
        'score was 10:30 in the end',
        'it costs \$5 at 5 stores',
        'version 1.2.3',
        'amazing 5',
        'call 555-1234',
        'in a bit',
      ]) {
        expect(findTimePhrases(text, now: _now), isEmpty, reason: text);
      }
    });

    test('links, tokens and code are skipped', () {
      expect(
        findTimePhrases('https://example.com/tomorrow-8pm', now: _now),
        isEmpty,
      );
      expect(findTimePhrases('<t:1790000000:R> tomorrow', now: _now), isEmpty);
      expect(findTimePhrases('`tomorrow 8pm`', now: _now), isEmpty);
    });

    test('finds several in order with their offsets', () {
      const text = 'lunch tomorrow at noon or dinner on friday at 7pm';
      final found = findTimePhrases(text, now: _now);
      expect(found.map((phrase) => phrase.textIn(text)).toList(), [
        'tomorrow at noon',
        'on friday at 7pm',
      ]);
      expect(found.first.time, DateTime(2026, 10, 18, 12));
      expect(found.last.time, DateTime(2026, 10, 23, 19));
    });
  });

  group('Chinese', () {
    test('tomorrow and the day after', () {
      _expectTime('我们明天晚上8点见', DateTime(2026, 10, 18, 20), phrase: '明天晚上8点');
      _expectTime('明晚8点半', DateTime(2026, 10, 18, 20, 30));
      _expectTime('明天早上八点', DateTime(2026, 10, 18, 8));
      _expectTime('后天下午3点', DateTime(2026, 10, 19, 15));
      _expectTime('后天下午3点15分', DateTime(2026, 10, 19, 15, 15));
      _expectTime('今晚9点', DateTime(2026, 10, 17, 21));
      _expectTime('明天中午12点', DateTime(2026, 10, 18, 12));
      _expectTime('明天凌晨2点', DateTime(2026, 10, 18, 2));
      _expectTime('明天晚上十二点', DateTime(2026, 10, 19));
      _expectTime('明天 15:30', DateTime(2026, 10, 18, 15, 30));
    });

    test('weekdays', () {
      _expectTime('下周三下午3点开会', DateTime(2026, 10, 21, 15), phrase: '下周三下午3点');
      _expectTime('下星期一上午10点', DateTime(2026, 10, 19, 10));
      _expectTime('下礼拜五晚上7点', DateTime(2026, 10, 23, 19));
      _expectTime('周五晚上8点', DateTime(2026, 10, 23, 20));
      _expectTime('这周日下午2点半', DateTime(2026, 10, 18, 14, 30));
      _expectTime('下下周一9点', DateTime(2026, 10, 26, 9));
    });

    test('repeating and past weekdays are not offered', () {
      expect(findTimePhrases('每周三下午3点', now: _now), isEmpty);
      expect(findTimePhrases('上周三下午3点', now: _now), isEmpty);
    });

    test('calendar dates', () {
      _expectTime('10月20日 15:00', DateTime(2026, 10, 20, 15));
      _expectTime('10月20号下午3点', DateTime(2026, 10, 20, 15));
      _expectTime('十月二十日晚上八点', DateTime(2026, 10, 20, 20));
      _expectTime('2027年1月5日上午9点', DateTime(2027, 1, 5, 9));
      _expectTime('下个月5号下午4点', DateTime(2026, 11, 5, 16));
      _expectTime('1月3日 10点', DateTime(2027, 1, 3, 10));
    });

    test('offsets from now', () {
      _expectTime('两小时后', DateTime(2026, 10, 17, 16));
      _expectTime('30分钟后见', DateTime(2026, 10, 17, 14, 30));
      _expectTime('半小时后', DateTime(2026, 10, 17, 14, 30));
      _expectTime('一个半小时后', DateTime(2026, 10, 17, 15, 30));
      _expectTime('3天后', DateTime(2026, 10, 20, 14));
    });

    test('a time alone', () {
      _expectTime('晚上8点吃饭', DateTime(2026, 10, 17, 20));
      _expectTime('早上7点', DateTime(2026, 10, 18, 7));
      _expectTime('下午5:30', DateTime(2026, 10, 17, 17, 30));
    });

    test('ordinary text is not a time', () {
      for (final text in ['我想吃一点东西', '你好', '明天', '今天天气很好', '周五', '三个人']) {
        expect(findTimePhrases(text, now: _now), isEmpty, reason: text);
      }
    });

    test('mixed languages', () {
      const text = 'Meet 明天下午3点 or tomorrow 5pm';
      final found = findTimePhrases(text, now: _now);
      expect(found.map((phrase) => phrase.time).toList(), [
        DateTime(2026, 10, 18, 15),
        DateTime(2026, 10, 18, 17),
      ]);
    });
  });
}
