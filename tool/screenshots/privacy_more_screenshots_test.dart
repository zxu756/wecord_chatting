// Renders the privacy and chat additions (disappearing messages, view-once
// media, devices, polls, double-tap reactions, profile visibility) on a
// phone (390x844) and a 1440x900 desktop with real fonts, for eyeballing.
// Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/privacy_more_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/privacy-more
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (file names
// end in -light or -dark).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/disappearing_messages.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/view_once.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

import '../../test/features/chats/media_send/media_fakes.dart';
import '../../test/features/privacy/privacy_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/privacy-more',
);
const _dark = bool.fromEnvironment('PHONE_SCREENS_DARK');

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name-${_dark ? 'dark' : 'light'}.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  /// Shoots [name] on the phone and the desktop, as `phone-<name>` and
  /// `desktop-<name>`.
  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world, bool desktop)
    open, {
    bool phone = true,
    bool desktop = true,
  }) {
    if (phone) {
      testWidgets('phone $name', (tester) async {
        usePhoneViewport(tester, notchedPhone);
        final world = PhoneWorld();
        await open(tester, world, false);
        await shoot(tester, 'phone-$name');
      });
    }
    if (desktop) {
      testWidgets('desktop $name', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          usePhoneViewport(tester, _desktop);
          final world = PhoneWorld();
          await open(tester, world, true);
          await shoot(tester, 'desktop-$name');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openDirect(
    WidgetTester tester,
    PhoneWorld world, {
    List<ChatMessage>? messages,
  }) async {
    world.chats.messages = messages ?? richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  // 1. Disappearing messages.
  List<ChatMessage> disappearingMessages() {
    final now = DateTime.now().toUtc();
    return [
      phoneMessage(
        'n1',
        bart,
        'Bartholomew set messages to disappear after 24 hours.',
        minutesAgo: 30,
        type: MessageType.system,
        attachment: const {
          'kind': 'disappearing',
          'seconds': 86400,
          'actor_name': 'Bartholomew',
        },
      ),
      phoneMessage(
        'd1',
        bart,
        'This one is gone by tomorrow.',
        minutesAgo: 20,
      ).copyWith(expiresAt: now.add(const Duration(hours: 23, minutes: 40))),
      phoneMessage(
        'd2',
        me,
        'Good, nothing to keep here.',
        minutesAgo: 10,
      ).copyWith(expiresAt: now.add(const Duration(hours: 23, minutes: 50))),
      phoneMessage(
        'd3',
        bart,
        'Photos too?',
        minutesAgo: 3,
      ).copyWith(expiresAt: now.add(const Duration(hours: 23, minutes: 57))),
    ];
  }

  List<Override> timerOverrides(int? seconds) => [
    disappearingRepositoryProvider.overrideWithValue(_FixedTimer(seconds)),
  ];

  screen('disappearing-thread', (tester, world, desktop) async {
    world.extraOverrides = timerOverrides(86400);
    await openDirect(tester, world, messages: disappearingMessages());
  });

  screen('disappearing-sheet', (tester, world, desktop) async {
    world.extraOverrides = timerOverrides(604800);
    await openDirect(tester, world, messages: disappearingMessages());
    if (desktop) {
      await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    } else {
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Disappearing messages'));
    }
  });

  // 2. View-once media.
  screen('view-once-thread', (tester, world, desktop) async {
    ChatMessage once(
      String id,
      Profile sender,
      int minutes, {
      bool video = false,
    }) => phoneMessage(
      id,
      sender,
      '',
      minutesAgo: minutes,
      type: video ? MessageType.file : MessageType.image,
      attachment: {
        'kind': video ? 'video' : 'image',
        'bucket': video ? 'chat-files' : 'chat-images',
        'path': 'dm-1/once-$id.jpg',
        'mime_type': video ? 'video/mp4' : 'image/jpeg',
        'name': 'view-once.mp4',
        'size': 1024,
        'view_once': true,
      },
    );
    final fake = _FixedOnce({
      'o3': [ViewOnceOpen(userId: 'user-1', openedAt: DateTime.now())],
      'o4': [ViewOnceOpen(userId: 'user-2', openedAt: DateTime.now())],
    });
    world.extraOverrides = [viewOnceRepositoryProvider.overrideWithValue(fake)];
    await openDirect(
      tester,
      world,
      messages: [
        phoneMessage('t0', bart, 'Sending you the pictures.', minutesAgo: 30),
        once('o1', bart, 20),
        once('o2', bart, 18, video: true),
        once('o3', bart, 15),
        phoneMessage('t1', me, 'Thanks! Here is mine.', minutesAgo: 10),
        once('o4', me, 8),
        once('o5', me, 5),
      ],
    );
  });

  screen('view-once-tray', (tester, world, desktop) async {
    world.extraOverrides = timerOverrides(null);
    await openDirect(tester, world);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatThreadScreen)),
    );
    final tray = container.read(mediaTrayProvider('dm-1').notifier);
    await tester.runAsync(
      () => tray.add([testPhoto('lake.jpg'), testPhoto('hike.jpg')]),
    );
    tray.setViewOnce(true);
    await tester.pump();
  });

  screen('view-once-viewer', (tester, world, desktop) async {
    await openDirect(tester, world);
    final context = tester.element(find.byType(ChatThreadScreen));
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => const ViewOnceViewer(
            file: ViewOnceFile(
              url: 'https://example.invalid/x.jpg',
              isVideo: false,
            ),
          ),
        ),
      ),
    );
  });

  // 3. Devices.
  screen('devices', (tester, world, desktop) async {
    world.extraOverrides = deviceOverrides();
    if (desktop) {
      await world.open(tester, '/me');
      await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
      await settle(tester);
    } else {
      await world.open(tester, '/me');
    }
    final tile = find.byKey(const ValueKey('devices-tile'));
    await scrollIntoView(tester, tile);
    await tester.tap(tile);
  });

  // 4. Polls.
  ChatMessage pollMessage(
    String id,
    Profile sender,
    int minutes, {
    required String question,
    required List<String> options,
    bool quiz = false,
    bool anonymous = false,
    bool allowAdd = false,
    PollResults results = const PollResults(),
    DateTime? endsAt,
  }) {
    return phoneMessage(
      id,
      sender,
      question,
      minutesAgo: minutes,
      type: MessageType.poll,
      attachment: {
        'kind': 'poll',
        'question': question,
        'options': [
          for (final (index, option) in options.indexed)
            {'id': 'o${index + 1}', 'text': option},
        ],
        'multi': false,
        'quiz': quiz,
        'anonymous': anonymous,
        'allow_add': allowAdd,
        'ends_at': endsAt?.toIso8601String(),
      },
    ).copyWith(pollResults: results);
  }

  screen('polls-thread', (tester, world, desktop) async {
    await openDirect(
      tester,
      world,
      messages: [
        pollMessage(
          'p1',
          bart,
          40,
          question: 'Capital of France?',
          options: ['Rome', 'Paris', 'Oslo'],
          quiz: true,
          results: const PollResults(
            counts: {'o1': 2, 'o2': 5, 'o3': 1},
            totalVoters: 8,
            myVotes: {'o1'},
            correct: 'o2',
            explanation: 'Paris has been the capital since 987.',
          ),
        ),
        pollMessage(
          'p2',
          me,
          20,
          question: 'Where to this weekend?',
          options: ['Park', 'Beach', 'Museum'],
          anonymous: true,
          allowAdd: true,
          endsAt: DateTime.now().toUtc().add(const Duration(hours: 5)),
          results: const PollResults(
            counts: {'o1': 3, 'o2': 4},
            totalVoters: 7,
            myVotes: {'o2'},
          ),
        ),
      ],
    );
  });

  screen('polls-composer', (tester, world, desktop) async {
    await openDirect(tester, world);
    await tester.tap(find.byTooltip('Attach'));
    await settle(tester);
    await tester.tap(find.text('Create poll'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('poll-question-field')),
      'Capital of France?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-option-field-0')),
      'Rome',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-option-field-1')),
      'Paris',
    );
    final more = find.byKey(const ValueKey('poll-more-options'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pump();
    final quiz = find.byKey(const ValueKey('poll-quiz-switch'));
    await tester.ensureVisible(quiz);
    await tester.tap(quiz);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poll-correct-1')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('poll-anonymous-switch')),
    );
    await tester.tap(find.byKey(const ValueKey('poll-anonymous-switch')));
  });

  // MARKER: more screens
}

class _FixedOnce implements ViewOnceRepository {
  _FixedOnce(this.opens);

  final Map<String, List<ViewOnceOpen>> opens;

  @override
  Future<ViewOnceFile> open(String messageId) async =>
      const ViewOnceFile(url: 'https://example.invalid/x.jpg', isVideo: false);

  @override
  Stream<List<ViewOnceOpen>> watchOpens(String messageId) =>
      Stream.value(opens[messageId] ?? const []);
}

class _FixedTimer implements DisappearingRepository {
  _FixedTimer(this.seconds);

  int? seconds;

  @override
  Future<int?> timer(String conversationId) async => seconds;

  @override
  Future<void> setTimer(String conversationId, int? value) async {
    seconds = value;
  }
}
