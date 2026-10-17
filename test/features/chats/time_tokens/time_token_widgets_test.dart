import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/shared/calendar/calendar_file_saver.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

class _FakeSaver implements CalendarFileSaver {
  final saved = <({String fileName, String contents})>[];

  @override
  Future<CalendarSaveResult> save({
    required String fileName,
    required String contents,
    Rect? origin,
  }) async {
    saved.add((fileName: fileName, contents: contents));
    return CalendarSaveResult.downloaded;
  }
}

Future<_FakeSaver> _pump(WidgetTester tester, Widget child) async {
  final saver = _FakeSaver();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarFileSaverProvider.overrideWithValue(saver),
        timeTokenFollowsClockProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
  return saver;
}

void main() {
  testWidgets('a time in a message shows in the reader time zone with a hint', (
    tester,
  ) async {
    final soon = DateTime.now().add(const Duration(hours: 2, minutes: 10));
    final token = TimeToken.fromDateTime(soon);
    await _pump(
      tester,
      MessageMarkdownText(
        body: 'dinner ${token.markup} ok?',
        color: Colors.black,
      ),
    );
    final label = timeTokenLabel(token, now: DateTime.now(), use24Hour: false);
    expect(find.textContaining(label.text, findRichText: true), findsOneWidget);
    expect(
      find.textContaining('in 2 hours', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('tapping opens the details and adds the time to a calendar', (
    tester,
  ) async {
    final start = DateTime.now().add(const Duration(days: 2));
    final token = TimeToken.fromDateTime(start, TimeTokenStyle.longDateTime);
    final saver = await _pump(
      tester,
      MessageMarkdownText(
        body: 'Team sync ${token.markup}',
        color: Colors.black,
      ),
    );

    await tester.tapOnText(find.textRange.ofSubstring('in 2 days'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('time-token-full')), findsOneWidget);
    expect(find.byKey(const ValueKey('time-token-relative')), findsOneWidget);
    expect(find.textContaining('time zone'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('time-token-add-to-calendar')));
    await tester.pumpAndSettle();

    expect(saver.saved, hasLength(1));
    expect(saver.saved.single.fileName, 'team-sync.ics');
    final ics = saver.saved.single.contents;
    expect(ics, contains('SUMMARY:Team sync'));
    expect(
      ics,
      contains(
        'DTSTART:${start.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').substring(0, 15)}',
      ),
    );
    expect(find.textContaining('Calendar file downloaded'), findsOneWidget);
  });

  group('composer suggestion', () {
    testWidgets('offers to convert a date and time and swaps in a token', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var changed = 0;
      final now = DateTime(2026, 10, 17, 14);
      await _pump(
        tester,
        TimePhraseSuggestion(
          controller: controller,
          clock: () => now,
          onConverted: () => changed++,
        ),
      );
      expect(
        find.byKey(const ValueKey('time-phrase-suggestion')),
        findsNothing,
      );

      controller.text = 'lunch tomorrow 8pm then home';
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('time-phrase-suggestion')),
        findsOneWidget,
      );
      expect(find.textContaining('tomorrow 8pm'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('time-phrase-convert')));
      await tester.pump();
      final expected = TimeToken.fromDateTime(DateTime(2026, 10, 18, 20));
      expect(controller.text, 'lunch ${expected.markup} then home');
      expect(changed, 1);
      expect(
        find.byKey(const ValueKey('time-phrase-suggestion')),
        findsNothing,
      );
    });

    testWidgets('can be dismissed and stays away for those words', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'call at 9am tomorrow');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        TimePhraseSuggestion(
          controller: controller,
          clock: () => DateTime(2026, 10, 17, 14),
          onConverted: () {},
        ),
      );
      expect(
        find.byKey(const ValueKey('time-phrase-suggestion')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('time-phrase-dismiss')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('time-phrase-suggestion')),
        findsNothing,
      );
      controller.text = 'call at 9am tomorrow!';
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('time-phrase-suggestion')),
        findsNothing,
      );
    });

    testWidgets('says nothing about ordinary text', (tester) async {
      final controller = TextEditingController(text: 'hello there');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        TimePhraseSuggestion(
          controller: controller,
          clock: () => DateTime(2026, 10, 17, 14),
          onConverted: () {},
        ),
      );
      expect(
        find.byKey(const ValueKey('time-phrase-suggestion')),
        findsNothing,
      );
    });
  });

  testWidgets('Insert time returns a token for the picked moment', (
    tester,
  ) async {
    TimeToken? picked;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await showInsertTimeSheet(context),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert-time-preview')), findsOneWidget);

    await tester.tap(find.text('Tomorrow 9 AM'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('insert-time-confirm')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final expected = DateTime(now.year, now.month, now.day + 1, 9);
    expect(picked, isNotNull);
    expect(picked!.time, expected);
    expect(picked!.style, TimeTokenStyle.shortDateTime);
  });
}
