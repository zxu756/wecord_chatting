import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/captions/caption_segmenter.dart';

void main() {
  var now = DateTime(2026, 10, 19, 12);
  CaptionSegmenter make({int maxChars = 100}) {
    now = DateTime(2026, 10, 19, 12);
    return CaptionSegmenter(maxChars: maxChars);
  }

  void pass(int ms) => now = now.add(Duration(milliseconds: ms));

  test('words being spoken are partial until the speaker pauses', () {
    final s = make();
    expect(s.hear('hello', now), [
      const CaptionSegment('hello', isFinal: false),
    ]);
    pass(300);
    expect(s.hear('hello there', now), [
      const CaptionSegment('hello there', isFinal: false),
    ]);
    // The same text again says nothing new.
    expect(s.hear('hello there', now), isEmpty);
    pass(800);
    expect(s.tick(now), isEmpty);
    pass(500);
    expect(s.tick(now), [const CaptionSegment('hello there', isFinal: true)]);
    expect(s.pending, isEmpty);
    expect(s.tick(now), isEmpty);
  });

  test('speech after a pause is the next line, not the old one again', () {
    final s = make();
    s.hear('good morning', now);
    pass(1300);
    s.tick(now);
    expect(s.hear('good morning everyone', now), [
      const CaptionSegment('everyone', isFinal: false),
    ]);
    pass(1300);
    expect(s.tick(now), [const CaptionSegment('everyone', isFinal: true)]);
  });

  test('a long line is cut at a sentence end', () {
    final s = make(maxChars: 40);
    final out = s.hear(
      'We should ship on Friday. Then we can review the numbers next week',
      now,
    );
    expect(
      out.first,
      const CaptionSegment('We should ship on Friday.', isFinal: true),
    );
    expect(out.last.isFinal, isFalse);
    expect(out.last.text, 'Then we can review the numbers next week');
  });

  test('Chinese is cut at punctuation, and without spaces', () {
    final s = make(maxChars: 12);
    final out = s.hear('我们周五上线，然后下周一起看一下数据结果怎么样', now);
    expect(out.first, const CaptionSegment('我们周五上线，', isFinal: true));
  });

  test('a line with no break is cut at a space, then at the limit', () {
    final s = make(maxChars: 20);
    final out = s.hear('alpha beta gamma delta epsilon zeta', now);
    expect(out.first.isFinal, isTrue);
    expect(out.first.text.length, lessThanOrEqualTo(20));
    final blob = make(maxChars: 10).hear('x' * 25, now);
    expect(blob.first, CaptionSegment('x' * 10, isFinal: true));
  });

  test('finishing settles what is left and starts clean', () {
    final s = make();
    s.hear('one two', now);
    expect(s.finish(), [const CaptionSegment('one two', isFinal: true)]);
    expect(s.finish(), isEmpty);
    // The next session starts from nothing, so its words are all new.
    expect(s.hear('three', now), [
      const CaptionSegment('three', isFinal: false),
    ]);
  });

  test('words rewritten inside a settled line are not taken back', () {
    final s = make();
    s.hear('wreck a nice beach', now);
    pass(1300);
    s.tick(now);
    final out = s.hear('recognize speech today', now);
    expect(out.single.isFinal, isFalse);
    expect(out.single.text, isNotEmpty);
  });

  test('reset forgets without settling', () {
    final s = make();
    s.hear('hello', now);
    s.reset();
    expect(s.pending, isEmpty);
    expect(s.finish(), isEmpty);
  });
}
