import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/search/search_query.dart';

void main() {
  group('tokenizeSearchQuery', () {
    test('reads words, phrases and exclusions', () {
      final parsed = ParsedSearchQuery.parse(
        '  ship "release notes" -draft -"old plan" ',
      );
      expect(parsed.text, 'ship "release notes" -draft -"old plan"');
      expect(parsed.highlightTerms, ['ship', 'release notes']);
      final tokens = parsed.tokens;
      expect(tokens.map((t) => t.raw), [
        'ship',
        '"release notes"',
        '-draft',
        '-"old plan"',
      ]);
      expect(tokens[1].quoted, isTrue);
      expect(tokens[2].negated, isTrue);
      expect(tokens[3].negated && tokens[3].quoted, isTrue);
      expect(tokens.first.start, 2);
      expect(tokens.first.end, 6);
    });

    test('reads every operator and strips @ and #', () {
      final parsed = ParsedSearchQuery.parse(
        'from:@ada mentions:grace in:#general has:link has:IMAGE '
        'before:2026-10-01 after:2026-9-5 during:2026-10-02 pinned:true hi',
      );
      expect(parsed.fromHandles, ['ada']);
      expect(parsed.mentionHandles, ['grace']);
      expect(parsed.placeNames, ['general']);
      expect(parsed.has, {SearchHas.link, SearchHas.image});
      expect(
        parsed.dateFor(SearchOperator.before),
        const SearchDate(2026, 10, 1),
      );
      expect(
        parsed.dateFor(SearchOperator.after),
        const SearchDate(2026, 9, 5),
      );
      expect(
        parsed.dateFor(SearchOperator.during),
        const SearchDate(2026, 10, 2),
      );
      expect(parsed.pinned, isTrue);
      expect(parsed.text, 'hi');
      expect(parsed.invalidOperators, isEmpty);
      expect(parsed.hasCriteria, isTrue);
    });

    test('operator names ignore case; unknown keys are text', () {
      final parsed = ParsedSearchQuery.parse('FROM:@Ada note:this http://x');
      expect(parsed.fromHandles, ['Ada']);
      expect(parsed.text, 'note:this http://x');
    });

    test('quoted values keep their spaces; unclosed quotes run on', () {
      final parsed = ParsedSearchQuery.parse(
        'in:"design team" from:"Ada L" "unclosed phrase',
      );
      expect(parsed.placeNames, ['design team']);
      expect(parsed.fromHandles, ['Ada L']);
      expect(parsed.highlightTerms, ['unclosed phrase']);
      final open = ParsedSearchQuery.parse('in:"half');
      expect(open.placeNames, ['half']);
    });

    test('bad values are kept as invalid and never sent', () {
      final parsed = ParsedSearchQuery.parse(
        'has:gif before:2026-02-30 during:yesterday pinned:maybe from: x',
      );
      expect(parsed.has, isEmpty);
      expect(parsed.dateFor(SearchOperator.before), isNull);
      expect(parsed.dateFor(SearchOperator.during), isNull);
      expect(parsed.pinned, isNull);
      expect(parsed.fromHandles, isEmpty);
      expect(parsed.invalidOperators.map((t) => t.raw), [
        'has:gif',
        'before:2026-02-30',
        'during:yesterday',
        'pinned:maybe',
      ]);
      // `from:` with nothing after it is still being typed.
      expect(parsed.text, 'x');
    });

    test('only exclusions or empty values are nothing to search for', () {
      expect(ParsedSearchQuery.parse('').hasCriteria, isFalse);
      expect(ParsedSearchQuery.parse('   ').hasCriteria, isFalse);
      expect(ParsedSearchQuery.parse('-spam').hasCriteria, isFalse);
      expect(ParsedSearchQuery.parse('from:').hasCriteria, isFalse);
      expect(ParsedSearchQuery.parse('has:poll').hasCriteria, isTrue);
    });

    test('CJK text and the ideographic space split words', () {
      final parsed = ParsedSearchQuery.parse('发布　新版本 from:@小明');
      expect(parsed.highlightTerms, ['发布', '新版本']);
      expect(parsed.fromHandles, ['小明']);
    });
  });

  group('parseSearchDate', () {
    test('accepts real days only', () {
      expect(parseSearchDate('2026-01-09'), const SearchDate(2026, 1, 9));
      expect(parseSearchDate('2024-02-29'), const SearchDate(2024, 2, 29));
      expect(parseSearchDate('2025-02-29'), isNull);
      expect(parseSearchDate('2026-13-01'), isNull);
      expect(parseSearchDate('10/01/2026'), isNull);
      expect(parseSearchDate('2026-10-01T10:00'), isNull);
    });

    test('days are local days', () {
      const day = SearchDate(2026, 10, 2);
      expect(day.startLocal, DateTime(2026, 10, 2));
      expect(day.endLocal, DateTime(2026, 10, 3));
      expect(day.toString(), '2026-10-02');
      expect(const SearchDate(2026, 12, 31).endLocal, DateTime(2027, 1, 1));
    });
  });

  group('SearchQueryEdit', () {
    test('appends filters, quoting values with spaces', () {
      expect(
        SearchQueryEdit.append('ship', SearchOperator.from, 'ada').text,
        'ship from:@ada ',
      );
      expect(
        SearchQueryEdit.append('', SearchOperator.inPlace, 'design team').text,
        'in:"design team" ',
      );
      expect(
        SearchQueryEdit.append('x ', SearchOperator.has, 'link').text,
        'x has:link ',
      );
    });

    test('removes a token and its space', () {
      const input = 'from:@ada ship has:link';
      final tokens = tokenizeSearchQuery(input);
      expect(SearchQueryEdit.remove(input, tokens.first).text, 'ship has:link');
      expect(SearchQueryEdit.remove(input, tokens.last).text, 'from:@ada ship');
      expect(
        SearchQueryEdit.remove(input, tokens[1]).text,
        'from:@ada has:link',
      );
    });

    test('replaces a token and puts the cursor after it', () {
      const input = 'ship from:@gr';
      final token = tokenizeSearchQuery(input).last;
      final edit = SearchQueryEdit.replace(input, token, 'from:@grace');
      expect(edit.text, 'ship from:@grace ');
      expect(edit.cursor, edit.text.length);
    });

    test('setSingle keeps one value for a filter', () {
      final edit = SearchQueryEdit.setSingle(
        'during:2026-01-01 a during:2026-01-02',
        SearchOperator.during,
        '2026-02-03',
      );
      expect(edit.text, 'a during:2026-02-03 ');
      expect(
        SearchQueryEdit.setSingle(
          'a pinned:true',
          SearchOperator.pinned,
          null,
        ).text,
        'a',
      );
    });
  });

  group('searchCompletionAt', () {
    test('suggests operators for a word that starts one', () {
      final completion = searchCompletionAt('ship fr', 7);
      expect(completion, isA<OperatorCompletion>());
      expect((completion! as OperatorCompletion).prefix, 'fr');
      expect(searchCompletionAt('ship xyz', 8), isNull);
      // Mid-word or after a phrase there is nothing to complete.
      expect(searchCompletionAt('ship fr', 6), isNull);
    });

    test('suggests values while an operator is typed', () {
      final completion = searchCompletionAt('ship from:@ad', 13);
      expect(completion, isA<ValueCompletion>());
      final value = completion! as ValueCompletion;
      expect(value.operator, SearchOperator.from);
      expect(value.prefix, 'ad');
      expect(
        (searchCompletionAt('in:#gen', 7)! as ValueCompletion).prefix,
        'gen',
      );
      // A closed quote ends the value.
      expect(searchCompletionAt('in:"a b"', 8), isNull);
    });

    test('an empty position offers every operator', () {
      final completion = searchCompletionAt('ship ', 5);
      expect(completion, isA<OperatorCompletion>());
      expect((completion! as OperatorCompletion).token, isNull);
      expect(searchCompletionAt('', 0), isA<OperatorCompletion>());
    });
  });

  test('formatOperatorValue quotes and prefixes', () {
    expect(formatOperatorValue(SearchOperator.from, 'ada'), '@ada');
    expect(formatOperatorValue(SearchOperator.inPlace, 'general'), '#general');
    expect(
      formatOperatorValue(SearchOperator.inPlace, 'my "team"'),
      '"my team"',
    );
    expect(formatOperatorValue(SearchOperator.has, 'link'), 'link');
  });
}
