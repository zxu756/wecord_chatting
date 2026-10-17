// Renders multi-select, merged forwards (the chat-history card and page) and
// contact cards on a phone and a desktop, light and dark, with real fonts,
// and writes PNGs for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/multi_select_screenshots_test.dart \
//     --dart-define=MULTI_SCREENS_DIR=build/multi-select
//
// Pick screens with --dart-define=MULTI_ONLY=select,cards.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_repository.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/features/contact_cards/contact_cards_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/features/chats/merged_forward/merged_forward_fakes.dart';
import '../../test/features/wallpapers/wallpaper_fakes.dart'
    show samplePhotoBytes;
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'MULTI_SCREENS_DIR',
  defaultValue: 'build/multi-select',
);
const _only = String.fromEnvironment('MULTI_ONLY');

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
  final photo = samplePhotoBytes(width: 480, height: 320);

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
          final merged = FakeMergedForwardRepository(
            bundles: {
              'history-1': ChatHistoryBundle.fromJson({
                'title': 'Climbing crew',
                'items': _historyItems(),
              }),
            },
          );
          world.extraOverrides = [
            mergedForwardRepositoryProvider.overrideWithValue(merged),
            contactCardsRepositoryProvider.overrideWithValue(
              FakeContactCardsRepository(),
            ),
            chatImageProviderFactoryProvider.overrideWithValue(
              (url) => MemoryImage(photo),
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

  List<ChatMessage> plan() => [
    phoneMessage(
      'p1',
      bart,
      'Are we still climbing on Saturday?',
      minutesAgo: 50,
    ),
    phoneMessage('p2', me, 'Yes! Meet at the gym at 10.', minutesAgo: 48),
    phoneMessage(
      'p3',
      bart,
      'Here is the route sheet',
      minutesAgo: 45,
      type: MessageType.file,
      attachment: const {
        'kind': 'file',
        'bucket': 'chat-files',
        'path': 'dm-1/routes.pdf',
        'name': 'routes.pdf',
        'mime_type': 'application/pdf',
        'size': 184320,
      },
    ),
    phoneMessage(
      'p4',
      me,
      'Perfect, I will bring chalk and snacks.',
      minutesAgo: 40,
    ),
    phoneMessage('p5', bart, 'And the new shoes!', minutesAgo: 38),
  ];

  Future<void> beginSelecting(
    WidgetTester tester,
    PhoneWorld world,
    List<String> ids,
  ) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatThreadScreen)),
    );
    final controller = container.read(chatSelectionProvider('dm-1').notifier);
    final messages = world.chats.messages;
    controller.begin(messages.firstWhere((m) => m.id == ids.first));
    for (final id in ids.skip(1)) {
      controller.toggle(messages.firstWhere((m) => m.id == id));
    }
    await settle(tester);
  }

  // ------------------------------------------------------- selection

  screen('select', 'select1-menu', (tester, world, variant) async {
    world.chats.messages = plan();
    await openDirect(tester, world);
    if (variant.desktop) {
      await tester.tap(
        find.text('Yes! Meet at the gym at 10.'),
        buttons: kSecondaryButton,
        warnIfMissed: false,
      );
    } else {
      await tester.longPress(find.text('Yes! Meet at the gym at 10.'));
    }
    await settle(tester);
  });

  screen('select', 'select2-mode', (tester, world, variant) async {
    world.chats.messages = plan();
    await openDirect(tester, world);
    await beginSelecting(tester, world, ['p2', 'p3', 'p4']);
  });

  screen('select', 'select3-merge', (tester, world, variant) async {
    world.chats.messages = plan();
    await openDirect(tester, world);
    await beginSelecting(tester, world, ['p1', 'p2', 'p3']);
    await tester.tap(find.byKey(const ValueKey('selection-merge')));
    await settle(tester);
  });

  // ------------------------------------------------------------ cards

  List<ChatMessage> cardMessages() {
    final now = DateTime.now();
    return [
      phoneMessage(
        'c0',
        bart,
        'Sending you the thread from the climbing crew',
        minutesAgo: 9,
      ),
      chatHistoryMessage(
        senderId: bart.id,
        createdAt: now.subtract(const Duration(minutes: 8)),
      ),
      phoneMessage(
        'c1',
        me,
        'Thanks! And Grace is who you meant?',
        minutesAgo: 6,
      ),
      contactCardMessage(
        id: 'contact-1',
        senderId: bart.id,
        createdAt: now.subtract(const Duration(minutes: 5)),
        card: {
          'kind': 'contact_card',
          'card': 'user',
          'user_id': grace.id,
          'name': grace.displayName,
          'username': grace.username,
        },
      ),
      contactCardMessage(
        id: 'contact-2',
        senderId: me.id,
        createdAt: now.subtract(const Duration(minutes: 3)),
        card: {
          'kind': 'contact_card',
          'card': 'circle',
          'circle_id': 'circle-5',
          'name': 'Climbing',
          'member_count': 14,
          'invite_code': 'abcdefghij',
        },
      ),
    ];
  }

  screen('cards', 'cards1-in-chat', (tester, world, variant) async {
    world.chats.messages = cardMessages();
    await openDirect(tester, world);
  });

  screen('cards', 'cards2-history-page', (tester, world, variant) async {
    world.chats.messages = cardMessages();
    await openDirect(tester, world);
    await tester.tap(find.byKey(const ValueKey('chat-history-card-history-1')));
    await settle(tester);
  });

  screen('cards', 'cards3-picker-friends', (tester, world, variant) async {
    world.chats.messages = plan();
    await openDirect(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('composer-contact-card-entry')));
    await settle(tester);
  });

  screen('cards', 'cards4-picker-circles', (tester, world, variant) async {
    world.circles.circles = [
      const CircleSummary(
        id: 'c1',
        name: 'Climbing',
        memberCount: 14,
        channelCount: 4,
        currentUserRole: 'owner',
      ),
      CircleSummary(
        id: 'c2',
        name: 'Book Club',
        memberCount: 9,
        channelCount: 2,
        currentUserRole: 'member',
        currentUserPermissions: CirclePermission.maskOf([
          CirclePermission.viewChannel,
          CirclePermission.createInvites,
        ]),
      ),
      CircleSummary(
        id: 'c3',
        name: 'Family',
        memberCount: 6,
        channelCount: 3,
        currentUserRole: 'member',
        currentUserPermissions: CirclePermission.maskOf([
          CirclePermission.viewChannel,
        ]),
      ),
    ];
    world.chats.messages = plan();
    await openDirect(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('composer-contact-card-entry')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('contact-card-tab-circles')));
    await settle(tester);
  });
}

List<Map<String, dynamic>> _historyItems() {
  final day = DateTime.now().subtract(const Duration(days: 1));
  String at(int hour, int minute) => DateTime(
    day.year,
    day.month,
    day.day,
    hour,
    minute,
  ).toUtc().toIso8601String();
  return [
    {
      'message_id': 'h1',
      'sender_id': 'user-2',
      'sender_name': 'Ada',
      'created_at': at(18, 30),
      'type': 'text',
      'body': 'Are we still on for the climbing gym on Saturday?',
    },
    {
      'message_id': 'h2',
      'sender_id': 'user-3',
      'sender_name': 'Bart the Bold',
      'created_at': at(18, 31),
      'type': 'text',
      'body': 'Yes! I booked the **10 am** slot.',
    },
    {
      'message_id': 'h3',
      'sender_id': 'user-3',
      'sender_name': 'Bart the Bold',
      'created_at': at(18, 33),
      'type': 'image',
      'body': '',
      'attachment': {
        'kind': 'image',
        'bucket': 'chat-images',
        'path': 'src/wall.jpg',
        'mime_type': 'image/jpeg',
        'size': 52000,
        'width': 480,
        'height': 320,
      },
    },
    {
      'message_id': 'h4',
      'sender_id': 'user-2',
      'sender_name': 'Ada',
      'created_at': at(18, 40),
      'type': 'file',
      'body': '',
      'attachment': {
        'kind': 'file',
        'bucket': 'chat-files',
        'path': 'src/routes.pdf',
        'name': 'routes.pdf',
        'mime_type': 'application/pdf',
        'size': 184320,
      },
    },
    {
      'message_id': 'h5',
      'sender_id': 'user-3',
      'sender_name': 'Bart the Bold',
      'created_at': at(18, 42),
      'type': 'text',
      'body': 'Perfect, see you there.',
    },
  ];
}
