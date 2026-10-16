// Renders message search on a phone (390x844) and a desktop (1440x900)
// with real fonts and writes PNGs for eyeballing. Not part of
// `flutter test`; run it with:
//
//   flutter test tool/screenshots/search_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/search/light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=PHONE_SCREENS_ZH=true for the Chinese interface.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/recent_searches.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/navigation/app_router.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/search/light',
);

const _phone = PhoneViewport(
  name: 'phone',
  size: Size(390, 844),
  devicePixelRatio: 2,
  topInset: 47,
  bottomInset: 34,
);

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

const _general = SearchPlace(
  id: 'conv-general',
  type: ConversationType.channel,
  title: 'general',
  circleId: 'circle-1',
  circleName: 'Bay Area Weekend Explorers',
);

const _gear = SearchPlace(
  id: 'conv-gear',
  type: ConversationType.thread,
  title: 'Camera gear for the launch hike',
  circleId: 'circle-1',
  circleName: 'Bay Area Weekend Explorers',
  parentConversationId: 'conv-general',
  parentTitle: 'general',
);

final _dm = SearchPlace(
  id: 'dm-1',
  type: ConversationType.direct,
  title: bart.displayName,
);

const _group = SearchPlace(
  id: 'group-1',
  type: ConversationType.group,
  title: 'Weekend Hiking & Photography Club',
);

SearchHit _hit(
  String id,
  SearchPlace place,
  String sender,
  String body, {
  required int minutesAgo,
  MessageType type = MessageType.text,
  Map<String, dynamic>? attachment,
  bool pinned = false,
}) {
  return SearchHit(
    message: ChatMessage(
      id: id,
      conversationId: place.id,
      senderId: 'user-$sender',
      type: type,
      body: body,
      attachment: attachment,
      createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      isPinned: pinned,
    ),
    senderName: sender,
    place: place,
    pinned: pinned,
  );
}

List<SearchHit> _launchHits() => [
  _hit(
    'h1',
    _general,
    'Grace Hopper',
    'Launch day is Saturday — meet at the north trailhead at 7, '
        'bring layers and the long lens.',
    minutesAgo: 35,
    pinned: true,
  ),
  _hit(
    'h2',
    _general,
    'Linus',
    'Moved the launch checklist to https://notes.example.com/launch',
    minutesAgo: 60 * 26,
  ),
  _hit(
    'h3',
    _dm,
    bart.displayName,
    'Can you double check the permit before the launch? The ranger said '
        'the lot closes early.',
    minutesAgo: 90,
  ),
  _hit(
    'h4',
    _gear,
    'Ada Lovelace',
    'launch-day-shot-list.pdf',
    minutesAgo: 60 * 50,
    type: MessageType.file,
    attachment: const {
      'kind': 'file',
      'name': 'launch-day-shot-list.pdf',
      'mime_type': 'application/pdf',
      'bucket': 'chat-files',
      'path': 'x/launch-day-shot-list.pdf',
      'size': 120000,
    },
  ),
  _hit(
    'h5',
    _group,
    'Grace Hopper',
    'Who is driving to the launch? I have two seats left.',
    minutesAgo: 60 * 75,
  ),
  _hit('h6', _group, 'Linus', '发布会之后一起去吃饭吧 launch 结束后集合', minutesAgo: 60 * 80),
];

class _ShotSearchRepository implements MessageSearchRepository {
  @override
  Future<SearchPage> search(MessageSearchRequest request) async {
    var hits = _launchHits();
    if (request.filters.fromIds.isNotEmpty) {
      hits = [
        for (final hit in hits)
          if (hit.senderName == 'Grace Hopper') hit,
      ];
    }
    if (request.scope is ConversationScope) {
      hits = [
        for (final hit in hits)
          if (hit.place == _general || hit.place == _gear) hit,
      ];
    }
    return SearchPage(
      hits: hits,
      total: hits.length + 41,
      conversationCounts: {for (final hit in hits) hit.conversationId: 7},
    );
  }

  @override
  Future<SearchContext> context(
    String messageId, {
    int before = 1,
    int after = 1,
  }) async {
    return SearchContext(
      before: [
        _hit(
          'c0',
          _general,
          bart.displayName,
          'What time are we meeting?',
          minutesAgo: 40,
        ),
      ],
      after: [
        _hit(
          'c2',
          _general,
          'Linus',
          'Perfect, see you there 👋',
          minutesAgo: 30,
        ),
      ],
    );
  }

  @override
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async {
    final people = [
      SearchPerson(
        id: grace.id,
        username: 'grace',
        displayName: 'Grace Hopper',
      ),
      SearchPerson(
        id: bart.id,
        username: bart.username,
        displayName: bart.displayName,
      ),
      SearchPerson(id: linus.id, username: 'linus', displayName: 'Linus'),
      SearchPerson(id: me.id, username: 'ada', displayName: 'Ada Lovelace'),
    ];
    return [
      for (final person in people)
        if (person.username.startsWith(prefix) ||
            person.displayName.toLowerCase().contains(prefix.toLowerCase()))
          person,
    ];
  }

  @override
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async => [_general, _gear, _group, _dm];
}

class _ShotRecents implements RecentSearchesStore {
  @override
  Future<List<String>> load() async => [
    'launch has:link',
    'from:@grace permit',
    'in:#general during:2026-10-11',
  ];

  @override
  Future<void> save(List<String> searches) async {}
}

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> open(
    WidgetTester tester,
    PhoneWorld world,
    String location,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...world.overrides,
          messageSearchRepositoryProvider.overrideWithValue(
            _ShotSearchRepository(),
          ),
          recentSearchesStoreProvider.overrideWithValue(_ShotRecents()),
        ],
        child: const WeCordApp(),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WeCordApp)),
    );
    world.router = container.read(appRouterProvider);
    await settle(tester);
    world.router.go(location);
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      text,
    );
    await tester.pump(MessageSearchController.debounce);
    await settle(tester);
  }

  for (final viewport in [_phone, _desktop]) {
    final prefix = viewport.name;
    void screen(
      String name,
      Future<void> Function(WidgetTester tester, PhoneWorld world) body,
    ) {
      testWidgets('$prefix $name', (tester) async {
        if (viewport == _desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, viewport);
          final world = PhoneWorld();
          await body(tester, world);
          await shoot(tester, '$prefix-$name');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    screen('1-results', (tester, world) async {
      await open(tester, world, GlobalMessageSearchScreen.path);
      await type(tester, 'launch');
      FocusManager.instance.primaryFocus?.unfocus();
    });

    screen('2-options', (tester, world) async {
      await open(tester, world, GlobalMessageSearchScreen.path);
      await tester.tap(find.byKey(const ValueKey('message-search-field')));
    });

    screen('3-autocomplete', (tester, world) async {
      await open(tester, world, GlobalMessageSearchScreen.path);
      await tester.tap(find.byKey(const ValueKey('message-search-field')));
      await type(tester, 'launch from:@');
      await tester.pump(const Duration(milliseconds: 200));
    });

    screen('4-filters-context', (tester, world) async {
      await open(tester, world, GlobalMessageSearchScreen.path);
      await type(tester, 'launch from:@grace has:link');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('search-hit-context-h1')));
    });

    screen('5-scoped', (tester, world) async {
      await open(
        tester,
        world,
        GlobalMessageSearchScreen.location(
          conversationId: 'conv-general',
          conversationTitle: 'general',
          conversationType: ConversationType.channel,
          circleId: 'circle-1',
          circleName: 'Bay Area Weekend Explorers',
          query: 'launch',
        ),
      );
      await tester.pump(MessageSearchController.debounce);
      FocusManager.instance.primaryFocus?.unfocus();
    });

    if (viewport == _phone) {
      screen('6-date-filter', (tester, world) async {
        await open(tester, world, GlobalMessageSearchScreen.path);
        await type(tester, 'launch');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('search-add-during')),
        );
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('search-add-during')));
      });

      screen('7-has-filter', (tester, world) async {
        await open(tester, world, GlobalMessageSearchScreen.path);
        await type(tester, 'launch');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('search-add-has')));
      });
    }
  }
}
