import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/features/settings/settings_repository.dart';

import '../file_preview/file_preview_fakes.dart';
import 'chat_thread_screen_test.dart' as thread_test;
import 'paged_chat_fakes.dart';

void main() {
  Widget app(PagedChatsRepository repository, {Stream<bool>? connectivity}) {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(repository),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          thread_test.FakeSettingsRepository(),
        ),
        ...filePreviewOverrides(),
        authRepositoryProvider.overrideWithValue(
          thread_test.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
        if (connectivity != null)
          deviceConnectivityProvider.overrideWith((ref) => connectivity),
      ],
      child: const MaterialApp(
        home: ChatThreadScreen(
          conversationId: 'conversation-1',
          title: 'Ada Lovelace',
        ),
      ),
    );
  }

  ScrollPosition listPosition(WidgetTester tester) {
    return tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('chat-message-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('opens on the newest page and loads older ones on the way up', (
    tester,
  ) async {
    final repository = PagedChatsRepository()
      ..rows = [for (var index = 0; index < 200; index++) messageRow(index)];

    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();

    expect(find.text('Message 199'), findsOneWidget);
    // Only the newest page was asked for.
    expect(repository.pageRequests, hasLength(1));
    expect(repository.pageRequests.single.before, isNull);

    final position = listPosition(tester);
    var pages = 1;
    for (
      var step = 0;
      step < 200 && !find.text('Message 0').evaluate().isNotEmpty;
      step++
    ) {
      position.jumpTo(position.pixels + 400);
      await tester.pump();
      await tester.pump();
      pages = repository.pageRequests.length;
    }

    expect(find.text('Message 0', skipOffstage: false), findsOneWidget);
    // Four full pages of 50, then an empty one says the start is reached.
    expect(pages, 5);
    expect(
      repository.pageRequests.skip(1).every((r) => r.before != null),
      isTrue,
    );
  });

  testWidgets('keeps the visible messages in place when older ones load', (
    tester,
  ) async {
    final repository = PagedChatsRepository()
      ..rows = [for (var index = 0; index < 120; index++) messageRow(index)];

    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();

    // Hold the next page so the list can be measured around it.
    final gate = repository.gate = Completer<void>();
    final position = listPosition(tester);
    while (!find.text('Message 72').evaluate().isNotEmpty) {
      position.jumpTo(position.pixels + 200);
      await tester.pump();
    }
    await tester.pump();
    expect(repository.pageRequests.last.before, isNotNull);
    final anchor = find.text('Message 72');
    final before = tester.getTopLeft(anchor);
    final pixels = position.pixels;

    gate.complete();
    repository.gate = null;
    await tester.pump();
    await tester.pump();

    expect(find.text('Message 69', skipOffstage: false), findsOneWidget);
    expect(tester.getTopLeft(anchor), before);
    expect(position.pixels, pixels);
  });

  testWidgets('new messages wait below while the reader is scrolled up', (
    tester,
  ) async {
    final repository = PagedChatsRepository()
      ..rows = [for (var index = 0; index < 60; index++) messageRow(index)];

    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();

    final position = listPosition(tester);
    final visible = find.text('Message 45');
    while (visible.evaluate().isEmpty) {
      position.jumpTo(position.pixels + 100);
      await tester.pump();
    }
    position.jumpTo(position.pixels + 100);
    await settle(tester);
    expect(visible, findsOneWidget);
    final before = tester.getTopLeft(visible);

    repository.rows = [...repository.rows, messageRow(60, body: 'Fresh news')];
    repository.emit(
      const ThreadEvent(
        ThreadEventKind.messageInserted,
        messageId: 'message-0060',
      ),
    );
    await settle(tester);

    expect(repository.byIdRequests.last, ['message-0060']);
    expect(tester.getTopLeft(visible), before);
    expect(find.text('1 new message'), findsOneWidget);

    await tester.tap(find.text('1 new message'));
    await settle(tester);
    expect(find.text('Fresh news'), findsOneWidget);
    expect(find.text('1 new message'), findsNothing);

    // At the bottom again, new messages show as they arrive.
    repository.rows = [...repository.rows, messageRow(61, body: 'And more')];
    repository.emit(
      const ThreadEvent(
        ThreadEventKind.messageInserted,
        messageId: 'message-0061',
      ),
    );
    await settle(tester);
    final newest = tester.getRect(find.text('And more'));
    final list = tester.getRect(
      find.byKey(const ValueKey('chat-message-list')),
    );
    expect(newest.bottom, lessThan(list.bottom));
    expect(newest.top, greaterThan(list.center.dy));
  });

  testWidgets('jumps to a message outside the loaded pages and back', (
    tester,
  ) async {
    final repository = PagedChatsRepository()
      ..rows = [
        for (var index = 0; index < 300; index++) messageRow(index),
        messageRow(
          300,
          id: 'notice',
          type: 'system',
          body: 'Grace pinned a message.',
          attachment: const {'kind': 'pin', 'message_id': 'message-0010'},
        ),
      ];

    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();
    expect(find.text('Message 10', skipOffstage: false), findsNothing);

    await tester.tap(find.text('Grace pinned a message.'));
    await settle(tester);

    expect(repository.byIdRequests.last, ['message-0010']);
    expect(find.text('Message 10'), findsOneWidget);
    // Centred in the list.
    final list = tester.getRect(
      find.byKey(const ValueKey('chat-message-list')),
    );
    expect(
      (tester.getCenter(find.text('Message 10')).dy - list.center.dy).abs(),
      lessThan(list.height / 4),
    );
    expect(find.text('Jump to latest'), findsWidgets);
    expect(find.text('Message 299', skipOffstage: false), findsNothing);

    // Scrolling down loads the newer pages after it.
    final position = listPosition(tester);
    position.jumpTo(position.minScrollExtent);
    await settle(tester);
    expect(repository.pageRequests.where((r) => r.after != null), isNotEmpty);

    await tester.tap(
      find.widgetWithText(GestureDetector, 'Jump to latest').first,
    );
    await settle(tester);
    expect(find.text('Grace pinned a message.'), findsOneWidget);
    expect(find.text('Message 10', skipOffstage: false), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a search result outside the loaded pages loads around it', (
    tester,
  ) async {
    final repository = PagedChatsRepository()
      ..rows = [for (var index = 0; index < 300; index++) messageRow(index)];

    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();
    expect(find.text('Message 10', skipOffstage: false), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatThreadScreen)),
    );
    container
        .read(pendingMessageJumpProvider.notifier)
        .state = const MessageJump(
      conversationId: 'conversation-1',
      messageId: 'message-0010',
    );
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The jump was taken once, the page around the result was fetched and
    // the result is in view and highlighted.
    expect(container.read(pendingMessageJumpProvider), isNull);
    expect(repository.byIdRequests.last, ['message-0010']);
    final target = find.text('Message 10');
    expect(target, findsOneWidget);
    final list = tester.getRect(
      find.byKey(const ValueKey('chat-message-list')),
    );
    expect(
      (tester.getCenter(target).dy - list.center.dy).abs(),
      lessThan(list.height / 4),
    );
    final highlight = tester.widget<AnimatedContainer>(
      find.ancestor(of: target, matching: find.byType(AnimatedContainer)).first,
    );
    expect((highlight.decoration as BoxDecoration?)?.color?.a, greaterThan(0));
    expect(find.text('Message 299', skipOffstage: false), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a message that no longer exists says it is not loaded', (
    tester,
  ) async {
    final repository = PagedChatsRepository()
      ..rows = [
        for (var index = 0; index < 80; index++) messageRow(index),
        messageRow(
          80,
          id: 'notice',
          type: 'system',
          body: 'Grace pinned a message.',
          attachment: const {'kind': 'pin', 'message_id': 'gone'},
        ),
      ];

    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Grace pinned a message.'));
    await settle(tester);

    expect(find.text('That message is not loaded.'), findsOneWidget);
  });

  testWidgets('a message sent offline shows as sending, then sends', (
    tester,
  ) async {
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    final repository = PagedChatsRepository()
      ..rows = [for (var index = 0; index < 5; index++) messageRow(index)];

    await tester.pumpWidget(app(repository, connectivity: connectivity.stream));
    await tester.pump();
    await tester.pump();
    connectivity.add(false);
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Offline — messages will send when you reconnect'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Written offline');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(find.text('Written offline'), findsOneWidget);
    expect(find.text('Sending…'), findsOneWidget);
    expect(repository.queuedSends, isEmpty);

    connectivity.add(true);
    await settle(tester);

    expect(repository.queuedSends.single.body, 'Written offline');
    expect(find.text('Sending…'), findsNothing);
    expect(find.text('Written offline'), findsOneWidget);
    expect(
      find.text('Offline — messages will send when you reconnect'),
      findsNothing,
    );
  });

  testWidgets('a message that keeps failing can be tapped to retry', (
    tester,
  ) async {
    final repository = PagedChatsRepository()
      ..rows = [for (var index = 0; index < 5; index++) messageRow(index)]
      ..queuedSendError = StateError('refused');

    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();

    // A refusal on the first try puts the text back to change.
    await tester.enterText(find.byType(TextField), 'Refused once');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await settle(tester);
    expect(find.text('Could not send message. Try again.'), findsOneWidget);
    expect(find.text('Sending…'), findsNothing);

    repository.queuedSendError = TimeoutException('slow network');
    await tester.enterText(find.byType(TextField), 'Flaky network');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(find.text('Sending…'), findsOneWidget);

    // Retries back off (2, 4, 8 and 16 seconds, give or take), then the
    // message is marked failed.
    for (var second = 0; second < 60; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Failed — tap to retry'), findsOneWidget);
    expect(repository.queuedSends.length, 1 + 5);

    repository.queuedSendError = null;
    await tester.tap(find.text('Failed — tap to retry'));
    await settle(tester);

    expect(find.text('Failed — tap to retry'), findsNothing);
    expect(find.text('Flaky network'), findsOneWidget);
    // The same client id every time: the server keeps it once.
    final ids = {
      for (final send in repository.queuedSends.skip(1)) send.clientId,
    };
    expect(ids, hasLength(1));
    expect(
      repository.rows.where((row) => row['body'] == 'Flaky network'),
      hasLength(1),
    );
  });
}
