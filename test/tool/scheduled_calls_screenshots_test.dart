// Screenshots of scheduled calls (E2), to look at for overflow: the event card
// with its green "In progress · Join" and the "Join the call" of the minutes
// before, the event sheet, the pinned strip with its short "Join", the event
// form with the "Attach a call" row, and an agenda row for a call.
//
// Always runs (a layout overflow fails the test) and writes PNGs into
// build/scheduled_calls/: phone, narrow phone at 2x text and desktop, light
// and dark, English and Chinese. The text uses a system font found on this
// machine (macOS) so that it can be read in the pictures; without one the
// layout is still checked.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/agenda/agenda_row.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../features/events2/events2_fakes.dart';
import '../features/voice/voice_fakes.dart';

const _fontCandidates = [
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  '/Library/Fonts/Arial Unicode.ttf',
];

Future<void> _loadFont() async {
  for (final path in _fontCandidates) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final bytes = file.readAsBytesSync();
    for (final family in const [
      'Plus Jakarta Sans',
      'Noto Sans SC',
      'PingFang SC',
      'Hiragino Sans GB',
      'Microsoft YaHei',
    ]) {
      final loader = FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await loader.load();
    }
    return;
  }
}

typedef _Variant = ({String label, Size size, bool dark, double text});

const _variants = <_Variant>[
  (label: 'phone-light', size: Size(390, 844), dark: false, text: 1),
  (label: 'phone-dark', size: Size(390, 844), dark: true, text: 1),
  (label: 'narrow-large-text', size: Size(360, 640), dark: false, text: 2),
  (label: 'desktop-light', size: Size(1100, 800), dark: false, text: 1),
  (label: 'desktop-dark', size: Size(1100, 800), dark: true, text: 1),
];

const _code = 'abcdefghjk23';

ChatEvent _event({
  Duration startedAgo = Duration.zero,
  Duration startsIn = Duration.zero,
  bool pinned = false,
  bool call = true,
}) {
  final base = chatEventWith(myStatus: ChatEventRsvp.going);
  final extras = call
      ? const EventExtras(
          callLinkCode: _code,
          recurrence: EventRecurrence.weekly,
          recurrenceTimeZone: 'Pacific/Auckland',
          seriesId: 's-1',
        )
      : EventExtras.none;
  return ChatEvent(
    id: base.id,
    conversationId: base.conversationId,
    title: AppStrings.isChinese
        ? '周四晚上的设计评审会，全组都来'
        : 'Thursday evening design review with the whole team',
    startsAt: DateTime.now().add(startsIn).subtract(startedAgo),
    locationText: AppStrings.isChinese ? '语音通话' : 'Voice call',
    createdBy: base.createdBy,
    creatorName: base.creatorName,
    goingCount: 5,
    maybeCount: 2,
    myStatus: ChatEventRsvp.going,
    canManage: true,
    pinnedAt: pinned ? DateTime.now() : null,
    attendees: base.attendees,
    extras: extras,
  );
}

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required ChatEvent event,
  required Widget home,
  Future<void> Function(WidgetTester tester)? afterPump,
  List<_Variant> variants = _variants,
}) async {
  for (final variant in variants) {
    tester.view.physicalSize = variant.size * 2;
    tester.view.devicePixelRatio = 2;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          retry: noProviderRetry,
          overrides: [
            chatEventsRepositoryProvider.overrideWithValue(
              FakeEventsChatRepository([event]),
            ),
            events2RepositoryProvider.overrideWithValue(
              FakeEvents2Repository(),
            ),
            voiceRepositoryProvider.overrideWithValue(FakeVoiceRepository()),
            voiceCallConnectorProvider.overrideWithValue(
              FakeVoiceCallConnector(),
            ),
            authStateProvider.overrideWith(
              (ref) => Stream.value(const AuthUser(id: 'user-1')),
            ),
            timeTokenFollowsClockProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.dark ? WeCordTheme.dark() : WeCordTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variant.text)),
              child: child!,
            ),
            home: home,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (afterPump != null) {
      await afterPump(tester);
    }
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final png = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final directory = Directory('build/scheduled_calls')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name-${variant.label}${AppStrings.isChinese ? '-zh' : ''}.png',
    ).writeAsBytesSync(png!);
    // The next variant starts from nothing.
    await tester.pumpWidget(const SizedBox());
  }
}

Widget _cardPage() => const Scaffold(
  body: SingleChildScrollView(
    child: ChatEventCard(conversationId: eventsConversationId, eventId: 'e-1'),
  ),
);

AgendaItem _agendaItem(String title, Map<String, dynamic> meta) {
  return AgendaItem.tryParse({
    'kind': 'chat_event',
    'title': title,
    'starts_at': DateTime.now()
        .add(const Duration(hours: 5))
        .toUtc()
        .toIso8601String(),
    'ends_at': DateTime.now()
        .add(const Duration(hours: 6))
        .toUtc()
        .toIso8601String(),
    'all_day': false,
    'conversation_id': 'conv-1',
    'target_id': title,
    'place_name': AppStrings.isChinese ? '徒步小队' : 'Hike crew',
    'meta': meta,
  })!;
}

void main() {
  setUpAll(() async {
    await _loadFont();
  });

  for (final chinese in [false, true]) {
    final suffix = chinese ? ' in Chinese' : '';

    void screen(
      String description,
      String name,
      Future<void> Function(WidgetTester tester) body,
    ) {
      testWidgets('$description$suffix', (tester) async {
        AppStrings.isChinese = chinese;
        addTearDown(() => AppStrings.isChinese = false);
        addTearDown(tester.view.reset);
        await body(tester);
        expect(tester.takeException(), isNull);
      });
    }

    screen('the card of a call that is on', 'card-live', (tester) async {
      await _shoot(
        tester,
        'card-live',
        event: _event(startedAgo: const Duration(minutes: 35)),
        home: _cardPage(),
      );
    });

    screen('the card in the minutes before', 'card-soon', (tester) async {
      await _shoot(
        tester,
        'card-soon',
        event: _event(startsIn: const Duration(minutes: 8)),
        home: _cardPage(),
      );
    });

    screen('the card of a call days away', 'card-later', (tester) async {
      await _shoot(
        tester,
        'card-later',
        event: _event(startsIn: const Duration(days: 2)),
        home: _cardPage(),
      );
    });

    screen('the event sheet of a call that is on', 'sheet-live', (
      tester,
    ) async {
      await _shoot(
        tester,
        'sheet-live',
        event: _event(startedAgo: const Duration(minutes: 35)),
        home: const Scaffold(body: SizedBox.expand()),
        afterPump: (tester) async {
          final context = tester.element(find.byType(Scaffold));
          unawaited(showChatEventSheet(context, 'e-1', eventsConversationId));
          await tester.pump(const Duration(milliseconds: 600));
        },
      );
    });

    screen('the pinned strip with Join', 'strip-live', (tester) async {
      await _shoot(
        tester,
        'strip-live',
        event: _event(startedAgo: const Duration(minutes: 35), pinned: true),
        home: const Scaffold(
          body: Column(
            children: [ChatEventStrip(conversationId: eventsConversationId)],
          ),
        ),
      );
    });

    screen('the event form with Attach a call', 'editor', (tester) async {
      await _shoot(
        tester,
        'editor',
        event: _event(startsIn: const Duration(days: 2)),
        home: const Scaffold(body: SizedBox.expand()),
        afterPump: (tester) async {
          final context = tester.element(find.byType(Scaffold));
          unawaited(
            showChatEventEditor(
              context,
              conversationId: eventsConversationId,
              event: _event(startsIn: const Duration(days: 2)),
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(ChatEventEditor),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.ensureVisible(
            find.byKey(const ValueKey('event-option-call')),
          );
        },
      );
    });

    screen('Schedule a call, a new form', 'schedule-call', (tester) async {
      await _shoot(
        tester,
        'schedule-call',
        event: _event(startsIn: const Duration(days: 2)),
        home: const Scaffold(body: SizedBox.expand()),
        afterPump: (tester) async {
          final context = tester.element(find.byType(Scaffold));
          unawaited(
            showChatEventEditor(
              context,
              conversationId: eventsConversationId,
              scheduleCall: true,
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
        },
      );
    });

    screen('the agenda rows of a call and an event', 'agenda', (tester) async {
      await _shoot(
        tester,
        'agenda',
        event: _event(),
        home: Scaffold(
          body: Column(
            children: [
              AgendaRow(
                item: _agendaItem(chinese ? '周四同步会' : 'Thursday sync', {
                  'status': 'going',
                  'call_link_code': _code,
                }),
                now: DateTime.now(),
                onPressed: () {},
              ),
              AgendaRow(
                item: _agendaItem(chinese ? '攀岩之夜' : 'Climbing night', {
                  'status': 'going',
                }),
                now: DateTime.now(),
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
    });
  }
}
