import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/story_viewer_screen.dart';
import 'package:wecord/shared/models/report_reason.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'stories_fakes.dart';

/// Opens the viewer from a button, like the app does, so closing it shows
/// the page underneath.
Widget _app(
  FakeStoriesRepository repository, {
  required List<StoryTrayEntry> entries,
  String? start,
  bool reduceMotion = false,
}) {
  return ProviderScope(
    overrides: storiesOverrides(repository: repository),
    child: MaterialApp(
      theme: WeCordTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => openStoryViewer(
                context,
                entries: entries,
                start: start ?? entries.first.authorId,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

/// Lets a sheet, dialog or route finish moving without running a photo's
/// five second clock out (pumpAndSettle would).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

double _filled(WidgetTester tester, int segment) {
  final bar = find.byKey(const ValueKey('story-progress'));
  final fills = find.descendant(
    of: bar,
    matching: find.byType(FractionallySizedBox),
  );
  return tester.widget<FractionallySizedBox>(fills.at(segment)).widthFactor!;
}

void main() {
  late FakeStoriesRepository repository;

  setUp(() {
    repository = FakeStoriesRepository()
      ..stories['user-2'] = [
        story('s1', caption: 'Morning', viewed: true),
        story('s2', caption: 'Lunch'),
        story('s3', caption: 'Dinner'),
      ];
  });

  Future<void> pumpViewer(
    WidgetTester tester, {
    List<StoryTrayEntry>? entries,
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      _app(
        repository,
        entries: entries ?? [entry('user-2', stories: 3, unseen: 2)],
        reduceMotion: reduceMotion,
      ),
    );
    await _open(tester);
  }

  testWidgets('starts at the first daily not seen and marks it viewed', (
    tester,
  ) async {
    await pumpViewer(tester);

    expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Bart the Bold'), findsOneWidget);
    expect(repository.viewed, ['s2']);
    // Three segments: the first done, the second filling.
    expect(_filled(tester, 0), 1);
    expect(_filled(tester, 2), 0);
  });

  testWidgets('a tap on the right goes on, on the left goes back', (
    tester,
  ) async {
    await pumpViewer(tester);

    final surface = find.byKey(const ValueKey('story-surface'));
    final size = tester.getSize(surface);
    final origin = tester.getTopLeft(surface);

    await tester.tapAt(origin + Offset(size.width * 0.8, size.height * 0.5));
    await tester.pump();
    expect(find.text('Dinner'), findsOneWidget);
    expect(repository.viewed, ['s2', 's3']);

    await tester.tapAt(origin + Offset(size.width * 0.1, size.height * 0.5));
    await tester.pump();
    expect(find.text('Lunch'), findsOneWidget);
    // Nothing is marked twice.
    expect(repository.viewed, ['s2', 's3']);
  });

  testWidgets('a photo lasts five seconds, then the next one comes', (
    tester,
  ) async {
    await pumpViewer(tester);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Lunch'), findsOneWidget);
    expect(_filled(tester, 1), closeTo(0.4, 0.05));

    await tester.pump(const Duration(seconds: 3, milliseconds: 100));
    expect(find.text('Dinner'), findsOneWidget);
  });

  testWidgets('holding pauses, letting go carries on', (tester) async {
    await pumpViewer(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('story-surface'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Lunch'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5, milliseconds: 100));
    expect(find.text('Dinner'), findsOneWidget);
  });

  testWidgets('the last daily closes the viewer', (tester) async {
    repository.stories['user-2'] = [story('only')];
    await pumpViewer(tester, entries: [entry('user-2')]);
    expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);

    await tester.pump(const Duration(seconds: 5, milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
    expect(find.byKey(const ValueKey('open')), findsOneWidget);
  });

  testWidgets('it goes on to the next friend with something new', (
    tester,
  ) async {
    repository.stories['user-2'] = [story('a1')];
    repository.stories['user-3'] = [
      story('b1', authorId: 'user-3', caption: 'From Cy'),
    ];
    await pumpViewer(
      tester,
      entries: [
        entry('user-2'),
        entry('user-3', name: 'Cy Young'),
        entry('user-4', name: 'Seen all', unseen: 0),
      ],
    );

    await tester.pump(const Duration(seconds: 5, milliseconds: 100));
    await tester.pump();
    await tester.pump();
    expect(find.text('From Cy'), findsOneWidget);
    expect(find.text('Cy Young'), findsOneWidget);
    expect(repository.viewed, ['a1', 'b1']);
  });

  testWidgets('close and Escape and a drag down all leave', (tester) async {
    await pumpViewer(tester);
    await tester.tap(find.byKey(const ValueKey('story-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('story-viewer')), findsNothing);

    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('story-viewer')), findsNothing);

    await _open(tester);
    await tester.drag(
      find.byKey(const ValueKey('story-surface')),
      const Offset(0, 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
  });

  testWidgets('arrow keys move between dailies', (tester) async {
    await pumpViewer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Dinner'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('Lunch'), findsOneWidget);
  });

  testWidgets('a short drag does not close it', (tester) async {
    await pumpViewer(tester);
    await tester.drag(
      find.byKey(const ValueKey('story-surface')),
      const Offset(0, 40),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
  });

  group('replying', () {
    testWidgets('a reply goes to the author and pauses the clock', (
      tester,
    ) async {
      await pumpViewer(tester);

      await tester.tap(find.byKey(const ValueKey('story-reply-field')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('story-reply-field')),
        'Love this',
      );
      await tester.pump();
      // Typing holds the clock.
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Lunch'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('story-reply-send')));
      await tester.pump();
      await tester.pump();

      expect(repository.replies, [('s2', 'Love this')]);
      expect(find.text('Reply sent'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('story-reply-field')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('send is off until there is something to send', (tester) async {
      await pumpViewer(tester);
      final send = find.byKey(const ValueKey('story-reply-send'));
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('story-reply-field')),
        '   ',
      );
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNull);
    });

    testWidgets('a daily that is gone says so and keeps the text', (
      tester,
    ) async {
      repository.failNext = const PostgrestException(
        message: 'Daily not found',
        code: 'P0002',
      );
      await pumpViewer(tester);
      await tester.enterText(
        find.byKey(const ValueKey('story-reply-field')),
        'Hello',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('story-reply-send')));
      await tester.pump();
      await tester.pump();

      expect(find.text('This daily is no longer available.'), findsWidgets);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('story-reply-field')),
      );
      expect(field.controller!.text, 'Hello');
    });

    testWidgets('a quick emoji reacts, the same one again takes it back', (
      tester,
    ) async {
      await pumpViewer(tester);

      await tester.tap(find.byKey(const ValueKey('story-emoji-🔥')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('story-emoji-🔥')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('story-emoji-😂')));
      await tester.pump();

      expect(repository.reactions, [('s2', '🔥'), ('s2', null), ('s2', '😂')]);
    });

    testWidgets('a reaction that fails is undone', (tester) async {
      repository.failNext = Exception('offline');
      await pumpViewer(tester);
      await tester.tap(find.byKey(const ValueKey('story-emoji-❤️')));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Could not send the reaction. Try again.'),
        findsWidgets,
      );
    });
  });

  group('reporting', () {
    testWidgets('the menu has Report, and it goes to the team', (tester) async {
      await pumpViewer(tester);

      await tester.tap(find.byKey(const ValueKey('story-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-menu-report')));
      await tester.pumpAndSettle();

      expect(find.text('Report daily'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-report-harassment')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('story-report-details')),
        'rude',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('story-report-also-block')),
      );
      await tester.tap(find.byKey(const ValueKey('story-report-also-block')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('story-report-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('story-report-submit')));
      await _settle(tester);

      expect(repository.reports, [
        ('s2', ReportReason.harassment, 'rude', true),
      ]);
      expect(find.byKey(const ValueKey('story-report-submit')), findsNothing);
      expect(
        find.text('Report sent. Thank you for helping keep WeCord safe.'),
        findsOneWidget,
      );
    });

    testWidgets('a limit reached is said in words', (tester) async {
      repository.failNext = const PostgrestException(
        message: 'too many',
        code: '54000',
      );
      await pumpViewer(tester);
      await tester.tap(find.byKey(const ValueKey('story-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-menu-report')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('story-report-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('story-report-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('You have sent too many reports today. Try again tomorrow.'),
        findsOneWidget,
      );
    });
  });

  group('my own dailies', () {
    setUp(() {
      repository.stories['user-1'] = [
        story('m1', authorId: 'user-1', viewCount: 2, reactionCount: 1),
        story('m2', authorId: 'user-1', viewCount: 1),
      ];
      repository.viewersList = [
        StoryViewerEntry(
          viewerId: 'user-2',
          name: 'Bart the Bold',
          viewedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          emoji: '🔥',
        ),
        StoryViewerEntry(
          viewerId: 'user-3',
          name: 'Cy Young',
          viewedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ];
    });

    Future<void> pumpMine(WidgetTester tester) => pumpViewer(
      tester,
      entries: [
        entry('user-1', name: 'Ada', stories: 2, unseen: 0, isMe: true),
      ],
    );

    testWidgets('I see the counts, not a reply bar, and nothing is marked', (
      tester,
    ) async {
      await pumpMine(tester);

      expect(find.text('Your daily'), findsOneWidget);
      expect(find.text('2 views'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-reply-field')), findsNothing);
      expect(find.byKey(const ValueKey('story-emoji-🔥')), findsNothing);
      expect(repository.viewed, isEmpty);
      expect(find.textContaining('Ends in'), findsOneWidget);
    });

    testWidgets('who viewed opens a list with the emoji, and pauses', (
      tester,
    ) async {
      await pumpMine(tester);

      await tester.tap(find.byKey(const ValueKey('story-views-button')));
      await tester.pumpAndSettle();

      expect(find.text('Viewed by'), findsOneWidget);
      expect(find.text('Only you can see this list.'), findsOneWidget);
      expect(find.text('Bart the Bold'), findsOneWidget);
      expect(find.text('Cy Young'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      // The clock stood still behind the sheet.
      await tester.pump(const Duration(seconds: 10));
      expect(
        tester
            .widget<FractionallySizedBox>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('story-progress')),
                    matching: find.byType(FractionallySizedBox),
                  )
                  .first,
            )
            .widthFactor,
        lessThan(0.05),
      );
    });

    testWidgets('nobody viewing yet is said kindly', (tester) async {
      repository.viewersList = [];
      await pumpMine(tester);
      await tester.tap(find.byKey(const ValueKey('story-views-button')));
      await tester.pumpAndSettle();
      expect(find.text('Nobody has viewed this yet.'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes it and goes on', (
      tester,
    ) async {
      await pumpMine(tester);

      await tester.tap(find.byKey(const ValueKey('story-delete')));
      await _settle(tester);
      expect(find.text('Delete this daily?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(repository.deleted, isEmpty);

      await tester.tap(find.byKey(const ValueKey('story-delete')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('story-delete-confirm')));
      await _settle(tester);

      expect(repository.deleted, ['m1']);
      expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
      expect(find.text('1 view'), findsOneWidget);

      // Deleting the last one closes the viewer.
      await tester.tap(find.byKey(const ValueKey('story-delete')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('story-delete-confirm')));
      await _settle(tester);
      expect(repository.deleted, ['m1', 'm2']);
      expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
    });

    testWidgets('the menu of my own daily deletes, it does not report', (
      tester,
    ) async {
      await pumpMine(tester);
      await tester.tap(find.byKey(const ValueKey('story-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-menu-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-menu-report')), findsNothing);
    });
  });

  group('reduced motion', () {
    testWidgets('nothing moves by itself', (tester) async {
      await pumpViewer(tester, reduceMotion: true);

      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Lunch'), findsOneWidget);
      // The current segment is shown full, not filling.
      expect(_filled(tester, 1), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Dinner'), findsOneWidget);
    });

    testWidgets('a drag down still closes, without sliding', (tester) async {
      await pumpViewer(tester, reduceMotion: true);
      await tester.drag(
        find.byKey(const ValueKey('story-surface')),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
    });
  });

  testWidgets('dailies that ended meanwhile are skipped', (tester) async {
    repository.stories['user-2'] = [
      story('old', caption: 'Gone', hoursLeft: -1),
      story('new', caption: 'Still here'),
    ];
    await pumpViewer(tester, entries: [entry('user-2', stories: 2)]);
    expect(find.text('Gone'), findsNothing);
    expect(find.text('Still here'), findsOneWidget);
  });

  testWidgets('nothing to show closes it', (tester) async {
    repository.stories['user-2'] = [];
    await pumpViewer(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
  });
}
