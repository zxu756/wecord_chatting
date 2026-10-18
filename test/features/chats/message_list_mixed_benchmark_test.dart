import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/shared/models/chat_status.dart';

import 'mixed_thread_fixture.dart';

/// Measures the chat with a 1,000 message conversation of every kind of
/// content (text, Markdown, pictures, albums, voice, chain / location /
/// contact / chat history / note cards, reactions) over a blurred photo
/// wallpaper: frame build times scrolling through all of it, and how many
/// widgets rebuild when one message changes, when someone types, when
/// presence changes and when a message arrives.
///
/// Widget tests run in debug mode, so timings compare runs with each other;
/// they are not device timings. The rebuild counts are exact.
void main() {
  String stats(String label, List<int> micros) {
    final sorted = [...micros]..sort();
    final mean = sorted.reduce((a, b) => a + b) / sorted.length;
    final p90 =
        sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
    final median = sorted[sorted.length ~/ 2];
    return '$label: mean ${(mean / 1000).toStringAsFixed(2)} ms, '
        'median ${(median / 1000).toStringAsFixed(2)} ms, '
        'p90 ${(p90 / 1000).toStringAsFixed(2)} ms, '
        'max ${(sorted.last / 1000).toStringAsFixed(2)} ms '
        '(${sorted.length} frames)';
  }

  testWidgets('mixed 1,000 message conversation', (tester) async {
    final world = MixedThreadWorld();
    final counter = RebuildCounter();
    final lines = <String>[];

    final first = Stopwatch()..start();
    world.prepare(tester);
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();
    first.stop();
    await tester.pump(const Duration(milliseconds: 400));
    lines.add(
      'providers created while opening: '
      '${ProviderCounter.top(world.providers.added, n: 40)}',
    );
    world.providers.clear();
    lines.add(
      'first frame with messages: '
      '${(first.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms',
    );
    expect(find.byKey(const ValueKey('chat-message-list')), findsOneWidget);

    final position = world.position(tester);

    // Scroll up through all 1,000 messages a viewport at a time; older
    // pages load on the way.
    final scrollFrames = <int>[];
    final scrollRebuilds = <int>[];
    var guard = 0;
    while (guard++ < 400) {
      position.jumpTo(position.pixels + 700);
      counter.start();
      final frame = Stopwatch()..start();
      await tester.pump();
      frame.stop();
      counter.stop();
      scrollFrames.add(frame.elapsedMicroseconds);
      scrollRebuilds.add(counter.total);
      // Let a page that loaded show up.
      if (guard % 6 == 0) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (position.pixels >= position.maxScrollExtent - 1 &&
          world.repository.pageRequests.length > 18) {
        break;
      }
    }
    lines.add(stats('scroll frame', scrollFrames));
    scrollRebuilds.sort();
    lines.add(
      'scroll frame rebuilds: median '
      '${scrollRebuilds[scrollRebuilds.length ~/ 2]}, '
      'max ${scrollRebuilds.last} (${scrollFrames.length} frames)',
    );
    lines.add('pages requested: ${world.repository.pageRequests.length}');
    lines.add(
      'providers created scrolling (autoDispose churn): '
      '${ProviderCounter.top(world.providers.added)}',
    );
    lines.add(
      'providers updated scrolling: '
      '${ProviderCounter.top(world.providers.updated)}',
    );
    world.providers.clear();

    // Back to the newest messages.
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // One message changes: a reaction on a message in view.
    // The newest message but one is on screen.
    const target = 'message-00998';
    final reactionRebuilds = <RebuildCounter>[];
    for (var i = 0; i < 4; i++) {
      final row = world.repository.rows.firstWhere((r) => r['id'] == target);
      row['reactions'] = i.isEven
          ? const [
              {'emoji': '🎉', 'count': 3},
            ]
          : const <Object?>[];
      final run = RebuildCounter()..start();
      world.repository.emit(
        ThreadEvent(ThreadEventKind.reactionsChanged, messageId: target),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      run.stop();
      reactionRebuilds.add(run);
    }
    lines.add(
      'one reaction changes ($target): ${reactionRebuilds[1].summary()}',
    );

    // One message is edited.
    final edit = RebuildCounter();
    final editRow = world.repository.rows.firstWhere((r) => r['id'] == target);
    editRow['body'] = 'Edited body';
    editRow['edited_at'] = DateTime.utc(2027).toIso8601String();
    edit.start();
    world.repository.emit(
      ThreadEvent(ThreadEventKind.messageUpdated, messageId: target),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    edit.stop();
    lines.add('one message is edited: ${edit.summary()}');

    // Typing in the composer.
    final field = find.byKey(const ValueKey('chat-composer-field'));
    expect(field, findsOneWidget);
    final typed = RebuildCounter()..start();
    final typingFrames = <int>[];
    var text = '';
    for (var i = 0; i < 12; i++) {
      text += 'hello world'[i % 11];
      final frame = Stopwatch()..start();
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(EditableText)),
        text,
      );
      await tester.pump();
      frame.stop();
      typingFrames.add(frame.elapsedMicroseconds);
    }
    typed.stop();
    await tester.pump(const Duration(seconds: 1));
    lines.add(
      'typing 12 characters: ${world.drafts.saves} draft writes, '
      '${world.drafts.bytes} bytes written',
    );
    lines.add('typing 12 characters: ${typed.summary()}');
    lines.add(
      'typing: providers updated '
      '${ProviderCounter.top(world.providers.updated)}',
    );
    world.providers.clear();
    lines.add(stats('typing frame', typingFrames));
    lines.add(
      'typing: message bubbles rebuilt ${typed.of('_MessageBubble')}, '
      'list rebuilt ${typed.of('MessageListView')}',
    );

    // Someone else types; presence changes.
    final theirs = RebuildCounter()..start();
    for (var i = 0; i < 6; i++) {
      world.repository.emitActivity(
        ConversationActivity(
          typingUserIds: i.isEven ? const {'user-2'} : const {},
        ),
      );
      await tester.pump();
    }
    theirs.stop();
    lines.add('someone types (6 changes): ${theirs.summary()}');
    final presence = RebuildCounter()..start();
    for (var i = 0; i < 6; i++) {
      world.online.add(i.isEven ? const {'user-2'} : const {'user-3'});
      await tester.pump();
    }
    presence.stop();
    lines.add('presence changes (6 changes): ${presence.summary()}');
    lines.add(
      'presence/typing: providers updated '
      '${ProviderCounter.top(world.providers.updated)}',
    );

    // A message arrives.
    final arrival = RebuildCounter();
    world.repository.rows = [
      ...world.repository.rows,
      {
        ...world.repository.rows.last,
        'id': 'message-new-1',
        'body': 'Fresh message',
        'created_at': DateTime.utc(2027, 2).toIso8601String(),
        'reactions': const <Object?>[],
      },
    ];
    arrival.start();
    world.repository.emit(
      const ThreadEvent(
        ThreadEventKind.messageInserted,
        messageId: 'message-new-1',
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    arrival.stop();
    lines.add('a message arrives: ${arrival.summary()}');

    debugPrint('Mixed thread benchmark ($mixedMessageCount messages):');
    for (final line in lines) {
      debugPrint('  $line');
    }
    await world.close(tester);
  });

  // Each kind of content on its own: what a screenful of it costs to build
  // and lay out while scrolling.
  const kinds = <String, List<int>>{
    'text': [0],
    'markdown': [1],
    'reply': [2],
    'image': [3],
    'album': [4, 5, 6],
    'voice': [7],
    'chain card': [8],
    'location card': [9],
    'contact card': [10],
    'chat history card': [11],
    'note card': [12],
    'file': [13],
  };
  for (final MapEntry(key: label, value: slots) in kinds.entries) {
    testWidgets('scrolling $label messages', (tester) async {
      final world = MixedThreadWorld(count: 120, slots: slots);
      await world.open(tester);
      final position = world.position(tester);
      final counter = RebuildCounter();
      final frames = <int>[];
      final rebuilds = <int>[];
      for (var step = 0; step < 60; step++) {
        position.jumpTo(position.pixels + 500);
        counter.start();
        final frame = Stopwatch()..start();
        await tester.pump();
        frame.stop();
        counter.stop();
        frames.add(frame.elapsedMicroseconds);
        rebuilds.add(counter.total);
      }
      rebuilds.sort();
      debugPrint(
        'Kind $label: ${stats('frame', frames)}; '
        'rebuilds median ${rebuilds[rebuilds.length ~/ 2]}',
      );
      await world.close(tester);
    });
  }
}
