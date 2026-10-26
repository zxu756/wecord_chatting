import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/hashtags/hashtag_text.dart';

void main() {
  final cases =
      jsonDecode(File('test/fixtures/hashtag_cases.json').readAsStringSync())
          as Map<String, dynamic>;

  group('the shared cases (the same as the database)', () {
    for (final raw in cases['extract'] as List) {
      final c = raw as Map<String, dynamic>;
      test('extract: ${(c['input'] as String).replaceAll('\n', r'\n')}', () {
        expect(extractHashtags(c['input'] as String), c['tags']);
      });
    }
    for (final raw in cases['clean'] as List) {
      final c = raw as Map<String, dynamic>;
      test('clean: ${c['input']}', () {
        expect(cleanHashtag(c['input'] as String), c['tag']);
      });
    }
  });

  group('places', () {
    test('spans point at the hash and the end of the tag', () {
      const text = 'a #Foo, b #bar';
      final spans = hashtagSpans(text);
      expect(spans.length, 2);
      expect(text.substring(spans[0].start, spans[0].end), '#Foo');
      expect(spans[0].tag, 'foo');
      expect(text.substring(spans[1].start, spans[1].end), '#bar');
    });

    test('a repeat keeps every place but one tag', () {
      final spans = hashtagSpans('#a1 and #A1');
      expect(spans.length, 2);
      expect(extractHashtags('#a1 and #A1'), ['a1']);
    });

    test('an emoji before the hash does not block it', () {
      expect(extractHashtags('🙂#开心'), ['开心']);
    });

    test('no text, no tags', () {
      expect(extractHashtags(null), isEmpty);
      expect(extractHashtags(''), isEmpty);
      expect(hashtagSpans('plain'), isEmpty);
    });

    test('a list is cleaned, folded and kept in order', () {
      expect(cleanHashtagList(['A', 'a', '#b', 'x y', '12', 'c']), [
        'a',
        'b',
        'c',
      ]);
      expect(
        cleanHashtagList([
          'a1',
          'a2',
          'a3',
          'a4',
          'a5',
          'a6',
          'a7',
          'a8',
          'a9',
          'b1',
          'b2',
        ]),
        hasLength(10),
      );
    });
  });
}
