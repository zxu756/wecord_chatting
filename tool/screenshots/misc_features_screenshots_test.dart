// Renders the time tokens, group events, group clean-up and data export
// screens on a phone and a desktop, light and dark, with real fonts, and
// writes PNGs for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/misc_features_screenshots_test.dart \
//     --dart-define=MISC_SCREENS_DIR=build/misc-features
//
// Pick screens with --dart-define=MISC_ONLY=time,events.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/features/groups/group_cleanup.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/features/chats/events/chat_events_test.dart'
    show FakeChatEventsRepository, chatEvent;
import '../../test/features/groups/group_cleanup_test.dart' show quietGroup;
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'MISC_SCREENS_DIR',
  defaultValue: 'build/misc-features',
);
const _only = String.fromEnvironment('MISC_ONLY');

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

class _Variant {
  const _Variant(this.name, this.viewport, this.dark);

  final String name;
  final PhoneViewport viewport;
  final bool dark;

  bool get desktop => viewport == _desktop;
}

const _variants = [
  _Variant('phone-light', notchedPhone, false),
  _Variant('phone-dark', notchedPhone, true),
  _Variant('desktop-light', _desktop, false),
  _Variant('desktop-dark', _desktop, true),
];

void main() {
  setUpAll(loadScreenshotFonts);
  late FakeChatEventsRepository eventsRepo;

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

  final only = _only.isEmpty ? null : _only.split(',').toSet();

  void screen(
    String group,
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      _Variant variant,
    )
    open,
  ) {
    if (only != null && !only.contains(group)) {
      return;
    }
    for (final variant in _variants) {
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          eventsRepo = FakeChatEventsRepository([]);
          world.extraOverrides = [
            timeTokenFollowsClockProvider.overrideWithValue(false),
            chatEventsRepositoryProvider.overrideWithValue(eventsRepo),
            groupCleanupRepositoryProvider.overrideWithValue(
              _ScreenshotCleanupRepository(),
            ),
          ];
          await open(tester, world, variant);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openDirect(WidgetTester tester, PhoneWorld world) async {
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  // ------------------------------------------------------- time tokens

  List<ChatMessage> timeMessages() {
    final soon = TimeToken.fromDateTime(
      DateTime.now().add(const Duration(hours: 2, minutes: 5)),
    );
    final dinner = TimeToken.fromDateTime(
      DateTime.now().add(const Duration(days: 2, hours: 4)),
      TimeTokenStyle.longDateTime,
    );
    final countdown = TimeToken.fromDateTime(
      DateTime.now().add(const Duration(hours: 30)),
      TimeTokenStyle.relative,
    );
    return [
      phoneMessage(
        't1',
        bart,
        'Are we still on for the climbing gym at ${soon.markup}?',
        minutesAgo: 20,
      ),
      phoneMessage(
        't2',
        me,
        'Yes! And dinner after, ${dinner.markup}. Booking closes ${countdown.markup}.',
        minutesAgo: 18,
      ),
      phoneMessage(
        't3',
        bart,
        'Perfect, I will add it to my calendar.',
        minutesAgo: 17,
      ),
    ];
  }

  screen('time', 'time1-message', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
  });

  screen('time', 'time2-details', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
    await tester.tapOnText(find.textRange.ofSubstring('in 2 hours'));
    await settle(tester);
  });

  screen('time', 'time3-suggestion', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
    await tester.enterText(
      find.byType(EditableText).last,
      'see you tomorrow 8pm at the gym',
    );
    await tester.pump(const Duration(milliseconds: 500));
  });

  screen('time', 'time4-insert', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.text('Insert time'));
    await settle(tester);
  });

  // ------------------------------------------------------------ events

  void seedEvents() {
    final soon = DateTime.now().add(const Duration(hours: 5));
    final next = DateTime.now().add(const Duration(days: 6, hours: 3));
    eventsRepo.events = [
      chatEvent(
        id: 'e-1',
        title: 'Bouldering night',
        startsAt: soon,
        endsAt: soon.add(const Duration(hours: 2)),
        pinned: true,
        myStatus: ChatEventRsvp.going,
        description: 'Bring chalk and a friend. Shoes can be rented.',
        link: 'https://example.com/gym/map',
        reminders: const [15, 60],
      ),
      chatEvent(
        id: 'e-2',
        title: 'Gear swap at the community hall',
        startsAt: next,
        going: 7,
        maybe: 3,
        declined: 1,
        location: 'Community hall, 5th Street',
      ),
      chatEvent(
        id: 'e-3',
        title: 'Summer trip planning',
        startsAt: DateTime.now().subtract(const Duration(days: 12)),
        cancelled: true,
      ),
    ];
    eventsRepo.reminders = [
      ChatEventReminder(
        id: 'r-1',
        eventId: 'e-1',
        conversationId: 'dm-1',
        title: 'Bouldering night',
        startsAt: DateTime.now().add(const Duration(minutes: 14)),
        leadMinutes: 15,
        createdAt: DateTime.now(),
        isUnread: true,
      ),
    ];
  }

  List<ChatMessage> eventMessages() => [
    phoneMessage(
      'ev0',
      bart,
      'Who is in for climbing this week?',
      minutesAgo: 40,
    ),
    phoneMessage(
      'ev1',
      me,
      'Ada created an event: Bouldering night',
      minutesAgo: 30,
      type: MessageType.system,
      attachment: const {'kind': 'event', 'event_id': 'e-1'},
    ),
    phoneMessage('ev2', bart, 'Count me in!', minutesAgo: 25),
  ];

  screen('events', 'events1-card', (tester, world, variant) async {
    seedEvents();
    world.chats.messages = eventMessages();
    await openDirect(tester, world);
  });

  screen('events', 'events2-details', (tester, world, variant) async {
    seedEvents();
    world.chats.messages = eventMessages();
    await openDirect(tester, world);
    await tester.tap(find.byKey(const ValueKey('chat-event-card-e-1')));
    await settle(tester);
  });

  screen('events', 'events3-list', (tester, world, variant) async {
    seedEvents();
    world.chats.messages = eventMessages();
    await openDirect(tester, world);
    if (find.byTooltip('Events').evaluate().isEmpty) {
      // Phones keep the rest of the header actions under More.
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Events'));
    } else {
      await tester.tap(find.byTooltip('Events'));
    }
    await settle(tester);
  });

  screen('events', 'events4-editor', (tester, world, variant) async {
    seedEvents();
    world.chats.messages = eventMessages();
    await openDirect(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.text('Events'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('chat-events-new')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chat-event-title-field')),
      'Pizza night',
    );
    await settle(tester);
  });

  screen('events', 'events5-inbox', (tester, world, variant) async {
    seedEvents();
    await world.open(tester, '/notifications');
  });

  // ------------------------------------- settings pages: cleanup, export

  /// The scrollable of the page on top (settings pages stack).
  Finder topPageScrollable() => find
      .descendant(
        of: find.byKey(const ValueKey('settings-page-list')).last,
        matching: find.byType(Scrollable),
      )
      .first;

  /// Opens Settings and taps [tile], on the phone page or in the desktop
  /// window's [section].
  Future<void> openSettingsRow(
    WidgetTester tester,
    PhoneWorld world,
    _Variant variant, {
    required String section,
    required String tile,
  }) async {
    await world.open(tester, '/me');
    await settle(tester);
    if (variant.desktop) {
      await tester.tap(find.byKey(ValueKey('settings-nav-$section')));
      await settle(tester);
    }
    final target = find.byKey(ValueKey(tile));
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: topPageScrollable(),
    );
    await settle(tester);
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  screen('cleanup', 'cleanup1-list', (tester, world, variant) async {
    await openSettingsRow(
      tester,
      world,
      variant,
      section: 'chats',
      tile: 'group-cleanup-tile',
    );
    await tester.tap(find.byKey(const ValueKey('group-cleanup-select-all')));
    await settle(tester);
  });

  screen('cleanup', 'cleanup2-undo', (tester, world, variant) async {
    await openSettingsRow(
      tester,
      world,
      variant,
      section: 'chats',
      tile: 'group-cleanup-tile',
    );
    await tester.tap(find.byKey(const ValueKey('group-cleanup-30')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('group-cleanup-select-all')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('group-cleanup-leave')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('group-cleanup-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  });
}

class _ScreenshotCleanupRepository implements GroupCleanupRepository {
  @override
  Future<List<InactiveGroup>> listInactiveGroups(int days) async {
    final all = [
      quietGroup('a', title: 'Summer trip 2025', days: 400, members: 8),
      quietGroup('b', title: 'Flat 4B', days: 220, members: 4, canLeave: false),
      quietGroup('c', title: 'Office lunch crew', days: 130, members: 23),
      quietGroup('d', title: 'Book club', days: 95, members: 11, pinned: true),
      quietGroup('e', title: 'Wedding planning', days: 45, members: 6),
    ];
    return [
      for (final group in all)
        if (DateTime.now().difference(group.lastActivityAt).inDays >= days)
          group,
    ];
  }
}
