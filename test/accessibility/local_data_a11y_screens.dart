// Protection of the chats saved on the device (G8: the card at the end of
// Settings -> Storage in each state) and searching them without a connection
// (L3: the "Offline results" notice over local hits, Chinese and English),
// for the accessibility guard (guidelines_test.dart) and the accessibility
// screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';
import 'package:wecord/features/local_search/offline_search_repository.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/storage/storage_screen.dart';

import '../features/chats/global_message_search_screen_test.dart'
    show FakeSearchRepository;
import '../features/local_search/local_search_fakes.dart';
import '../features/storage/storage_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A cipher that only says how well it protects.
class _Protecting extends UnavailableLocalCipher {
  const _Protecting(this._protection);

  final LocalProtection _protection;

  @override
  LocalProtection get protection => _protection;
}

Future<void> _protectionCard(
  WidgetTester tester,
  PhoneWorld world,
  LocalProtection protection,
) async {
  final storage = StorageWorld();
  world.extraOverrides = [
    ...storage.overrides,
    localCipherProvider.overrideWithValue(_Protecting(protection)),
  ];
  await pumpStandalone(tester, world, const StorageScreen());
  final card = find.byKey(const ValueKey('storage-protection'));
  await tester.dragUntilVisible(
    card,
    find.byKey(const ValueKey('settings-page-list')),
    const Offset(0, -150),
  );
  await tester.ensureVisible(card);
  await settle(tester);
}

class _Unreachable extends FakeSearchRepository {}

Future<LocalSearchWorld> _savedChats() async {
  final saved = LocalSearchWorld();
  await saved.cache.writeConversations(meId, [
    conversationRow('c1', 'Launch Crew'),
    conversationRow('c2', '家人群'),
  ]);
  await saved.cacheChat('c1', [
    messageRow('m1', 'c1', 'The launch plan is on the shared drive', minute: 5),
    messageRow(
      'm2',
      'c1',
      'Launch day moved to Friday, please check the checklist again',
      sender: userAda,
      minute: 9,
    ),
  ]);
  await saved.cacheChat('c2', [
    messageRow('m3', 'c2', '周末一起去吃火锅，别忘了带发布会的资料', minute: 3),
  ]);
  return saved;
}

Future<void> _offlineSearch(
  WidgetTester tester,
  PhoneWorld world,
  String query,
) async {
  final saved = await _savedChats();
  world.extraOverrides = [
    messageSearchRepositoryProvider.overrideWithValue(
      OfflineFallbackSearchRepository(
        online: _Unreachable(),
        local: saved.search,
        deviceOffline: () => true,
      ),
    ),
  ];
  await world.open(tester, GlobalMessageSearchScreen.path);
  await tester.enterText(
    find.byKey(const ValueKey('message-search-field')),
    query,
  );
  await tester.pump(MessageSearchController.debounce);
  await settle(tester);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

final localDataA11yScreens = <A11yScreen>[
  A11yScreen(
    'storage-protection-keychain',
    (tester, world) => _protectionCard(tester, world, LocalProtection.keychain),
  ),
  A11yScreen(
    'storage-protection-web',
    (tester, world) =>
        _protectionCard(tester, world, LocalProtection.browserKey),
  ),
  A11yScreen(
    'storage-protection-unavailable',
    (tester, world) =>
        _protectionCard(tester, world, LocalProtection.unavailable),
  ),
  A11yScreen(
    'storage-protection-desktop',
    (tester, world) => _protectionCard(tester, world, LocalProtection.keychain),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'message-search-offline',
    (tester, world) => _offlineSearch(tester, world, 'launch'),
  ),
  A11yScreen(
    'message-search-offline-chinese',
    (tester, world) => _offlineSearch(tester, world, '火锅'),
  ),
];
