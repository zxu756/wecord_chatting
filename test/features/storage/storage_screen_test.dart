import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/storage/disk_cache.dart';
import 'package:wecord/features/storage/storage_providers.dart';
import 'package:wecord/features/storage/storage_screen.dart';

import '../../mobile/phone_test_support.dart';
import 'storage_fakes.dart';

void main() {
  late PhoneWorld world;
  late StorageWorld storage;

  Future<void> open(WidgetTester tester) async {
    usePhoneViewport(tester, notchedPhone);
    world = PhoneWorld()..extraOverrides = storage.overrides;
    await pumpStandalone(tester, world, const StorageScreen());
  }

  /// Scrolls the page until [finder] is on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byKey(const ValueKey('settings-page-list')),
      const Offset(0, -150),
    );
    await tester.ensureVisible(finder);
    await settle(tester);
  }

  Future<void> fill() async {
    await cacheMessagesOf(storage.cache, 'user-1', 'dm-1', 3000);
    await cacheMessagesOf(storage.cache, 'user-1', 'group-1', 800);
    await storage.addWallpaper(2000);
  }

  testWidgets('shows what the device keeps, by kind and by chat', (
    tester,
  ) async {
    storage = StorageWorld(
      disk: [
        download('report.pdf', 5 * 1024 * 1024, conversationId: 'dm-1'),
        download('photo.jpg', 2 * 1024 * 1024, conversationId: 'group-1'),
        download('old.bin', 1024),
        DiskEntry(
          kind: DiskKind.unsent,
          path: '/support/c1',
          bytes: 4096,
          lastUsed: DateTime.utc(2026, 10, 19),
        ),
      ],
    );
    await fill();
    await open(tester);

    expect(find.byKey(const ValueKey('storage-total')), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Cached messages'), findsOneWidget);
    expect(find.text('Downloaded files'), findsOneWidget);
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.text('7.0 MB'), findsWidgets);
    // The chats, largest first, named as the chat list names them.
    await reveal(tester, find.byKey(const ValueKey('storage-chat-dm-1')));
    final dm = world.chats.conversations.firstWhere((c) => c.id == 'dm-1');
    expect(find.text(dm.title!), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('storage-unassigned')));
    expect(find.byKey(const ValueKey('storage-unassigned')), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('clearing a kind asks first, warns about data, then frees it', (
    tester,
  ) async {
    storage = StorageWorld(
      disk: [download('report.pdf', 5 * 1024 * 1024, conversationId: 'dm-1')],
    );
    await fill();
    await open(tester);

    await reveal(tester, find.byKey(const ValueKey('storage-downloads')));
    await tester.tap(find.byKey(const ValueKey('storage-downloads')));
    await settle(tester);

    expect(find.text('Clear downloaded files?'), findsOneWidget);
    expect(
      find.textContaining('downloaded again, which uses data'),
      findsOneWidget,
    );
    // Backing out changes nothing.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(storage.diskCache.entries, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('storage-downloads')));
    await settle(tester);
    await tester.tap(find.byKey(StorageScreen.confirmKey));
    await settle(tester);

    expect(storage.diskCache.entries, isEmpty);
    expect(find.text('Freed 5.0 MB.'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('clear all empties the caches but keeps what waits to send', (
    tester,
  ) async {
    storage = StorageWorld(
      disk: [
        download('report.pdf', 1024 * 1024, conversationId: 'dm-1'),
        DiskEntry(
          kind: DiskKind.unsent,
          path: '/support/c1',
          bytes: 4096,
          lastUsed: DateTime.utc(2026, 10, 19),
        ),
      ],
    );
    await fill();
    await storage.cache.writeOutbox('user-1', [
      {'client_id': 'waiting'},
    ]);
    await open(tester);

    await reveal(tester, find.byKey(StorageScreen.clearAllKey));
    await tester.tap(find.byKey(StorageScreen.clearAllKey));
    await settle(tester);
    expect(find.text('Clear all cached data?'), findsOneWidget);
    await tester.tap(find.byKey(StorageScreen.confirmKey));
    await settle(tester);

    expect(storage.diskCache.entries.single.kind, DiskKind.unsent);
    expect(await storage.cache.readMessages('user-1', 'dm-1'), isEmpty);
    expect(await storage.cache.readOutbox('user-1'), hasLength(1));
    expect(storage.wallpapers.photos, isEmpty);
    await world.close(tester);
  });

  testWidgets('clearing one chat leaves the others', (tester) async {
    storage = StorageWorld(
      disk: [
        download('report.pdf', 1024 * 1024, conversationId: 'dm-1'),
        download('photo.jpg', 2 * 1024 * 1024, conversationId: 'group-1'),
      ],
    );
    await fill();
    await open(tester);

    final row = find.byKey(const ValueKey('storage-chat-dm-1'));
    await reveal(tester, row);
    await tester.tap(row);
    await settle(tester);
    expect(find.textContaining('Clear what is kept for'), findsOneWidget);
    await tester.tap(find.byKey(StorageScreen.confirmKey));
    await settle(tester);

    expect(await storage.cache.readMessages('user-1', 'dm-1'), isEmpty);
    expect(await storage.cache.readMessages('user-1', 'group-1'), hasLength(1));
    expect(storage.diskCache.entries.single.conversationId, 'group-1');
    await world.close(tester);
  });

  testWidgets('the auto clean choice is remembered', (tester) async {
    storage = StorageWorld();
    await open(tester);

    final option = find.byKey(const ValueKey('auto-clean-days30'));
    await reveal(tester, option);
    await tester.tap(option);
    await settle(tester);

    expect(storage.settings.period, AutoCleanPeriod.days30);
    expect(find.textContaining('not opened for 30 days'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('on the web there are no files to count, and no auto clean', (
    tester,
  ) async {
    storage = StorageWorld(diskAvailable: false);
    await fill();
    await open(tester);

    expect(find.text('Cached messages'), findsOneWidget);
    expect(find.text('Downloaded files'), findsNothing);
    expect(find.text('Previews'), findsNothing);
    expect(find.byKey(StorageScreen.autoCleanKey), findsNothing);
    await world.close(tester);
  });

  testWidgets('an empty device says so and offers nothing to clear', (
    tester,
  ) async {
    storage = StorageWorld();
    await open(tester);

    expect(find.text('0 B'), findsWidgets);
    expect(find.byKey(const ValueKey('storage-chat-dm-1')), findsNothing);
    await world.close(tester);
  });
}
