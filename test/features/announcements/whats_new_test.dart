import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/announcements/whats_new_content.dart';
import 'package:wecord/features/announcements/whats_new_host.dart';
import 'package:wecord/features/feature_flags/feature_flags_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

const _entries = [
  WhatsNewEntry(
    version: '2.0.0',
    title: WhatsNewText('What is new', '有什么新功能'),
    items: [
      WhatsNewText('Faster chats.', '聊天更快了。'),
      WhatsNewText('Dark mode.', '深色模式。'),
    ],
  ),
];

class _BrokenStore implements WhatsNewStore {
  @override
  Future<String?> lastSeenVersion() async => throw StateError('no storage');

  @override
  Future<void> markSeen(String version) async => throw StateError('no storage');
}

Future<void> _open(
  WidgetTester tester, {
  required WhatsNewStore store,
  required String version,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        whatsNewStoreProvider.overrideWithValue(store),
        whatsNewEntriesProvider.overrideWithValue(_entries),
        appVersionProvider.overrideWithValue(version),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const WhatsNewHost(child: Scaffold(body: Text('home'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => WhatsNewHost.checkedThisRun = false);
  tearDown(() => AppStrings.isChinese = false);

  group('the content', () {
    test('finds the entry of a version, and nothing for another', () {
      expect(whatsNewFor('2.0.0', _entries)?.items, hasLength(2));
      expect(whatsNewFor('2.0.1', _entries), isNull);
    });

    test('ships in both languages', () {
      for (final entry in whatsNewEntries) {
        expect(entry.title.en, isNotEmpty);
        expect(entry.title.zh, isNotEmpty);
        for (final item in entry.items) {
          expect(item.en, isNotEmpty, reason: item.zh);
          expect(item.zh, isNotEmpty, reason: item.en);
        }
      }
    });
  });

  group('the popup', () {
    testWidgets('shows the first time WeCord opens after an update', (
      tester,
    ) async {
      final store = InMemoryWhatsNewStore('1.0.0');
      await _open(tester, store: store, version: '2.0.0');
      expect(find.text('What is new'), findsOneWidget);
      expect(find.text('Faster chats.'), findsOneWidget);
      expect(find.text('Dark mode.'), findsOneWidget);
      expect(find.text('WeCord 2.0.0'), findsOneWidget);
      // It is remembered at once, so closing the app unread does not bring
      // it back.
      expect(store.version, '2.0.0');
      await tester.tap(find.byKey(const ValueKey('whats-new-got-it')));
      await tester.pumpAndSettle();
      expect(find.text('What is new'), findsNothing);
    });

    testWidgets('is in Chinese for a Chinese app', (tester) async {
      AppStrings.isChinese = true;
      await _open(
        tester,
        store: InMemoryWhatsNewStore('1.0.0'),
        version: '2.0.0',
      );
      expect(find.text('有什么新功能'), findsOneWidget);
      expect(find.text('聊天更快了。'), findsOneWidget);
      expect(find.text('Faster chats.'), findsNothing);
    });

    testWidgets('does not show twice for the same version', (tester) async {
      final store = InMemoryWhatsNewStore('2.0.0');
      await _open(tester, store: store, version: '2.0.0');
      expect(find.text('What is new'), findsNothing);
    });

    testWidgets('a new person has nothing to compare with: noted, not shown', (
      tester,
    ) async {
      final store = InMemoryWhatsNewStore();
      await _open(tester, store: store, version: '2.0.0');
      expect(find.text('What is new'), findsNothing);
      expect(store.version, '2.0.0');
    });

    testWidgets('a version with nothing to say shows nothing', (tester) async {
      final store = InMemoryWhatsNewStore('2.0.0');
      await _open(tester, store: store, version: '2.0.1');
      expect(find.text('What is new'), findsNothing);
      expect(store.version, '2.0.1');
    });

    testWidgets(
      'a device that cannot store anything shows no popup and no error',
      (tester) async {
        await _open(tester, store: _BrokenStore(), version: '2.0.0');
        expect(find.text('home'), findsOneWidget);
        expect(find.text('What is new'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('is asked once per run, not every time the shell is rebuilt', (
      tester,
    ) async {
      final store = InMemoryWhatsNewStore('1.0.0');
      await _open(tester, store: store, version: '2.0.0');
      await tester.tap(find.byKey(const ValueKey('whats-new-got-it')));
      await tester.pumpAndSettle();
      // A second shell (after signing out and in) does not ask again.
      store.version = '1.0.0';
      await _open(tester, store: store, version: '2.0.0');
      expect(find.text('What is new'), findsNothing);
    });
  });
}
